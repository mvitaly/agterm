import agtCore
import AppKit
import Darwin
import Foundation

/// Orchestrates per-session git-status refreshes.
///
/// `@MainActor`: all model access (the `AppStore`, `Session`, and the throttle
/// state below) is main-actor isolated. The actual git work runs OFF the main
/// actor in a `Task.detached` worker that calls the `nonisolated static` runner
/// `runGit(cwd:)` — a bare `nonisolated func … async` would run on the caller's
/// (main) executor under Xcode 26 `NonisolatedNonsendingByDefault` and block the
/// UI while git runs. The worker takes only a `cwd: String` and returns only a
/// `Sendable GitStatus?`; it never captures `Session`, `AppStore`, or `Process`.
@MainActor
final class GitStatusService {
    private let store: AppStore

    /// The minimum interval between refreshes of the same cwd; a prompt redraw
    /// re-reporting the same cwd within this window is coalesced away.
    private let minInterval: TimeInterval = 2.5

    /// The per-process git timeout. A git call that does not finish within this
    /// is terminated and treated as a transient failure (keeps the prior status).
    private let gitTimeout: TimeInterval = 2

    /// The active-session poll interval. The active session is re-checked on this
    /// cadence while the app is frontmost; background sessions are never polled.
    private let activeInterval: Duration = .seconds(3)

    // throttle state, read/written ONLY on the main actor (before spawning a
    // worker and again on the completion hop). The worker never touches these.
    private var inFlight: Set<UUID> = []
    private var lastRanCwd: [UUID: String] = [:]
    private var lastRanAt: [UUID: Date] = [:]

    /// The active-session poll loop. Cancelled when the app resigns active and
    /// recreated when it becomes active, so a backgrounded app spawns no git.
    private var activeLoop: Task<Void, Never>?

    /// Retained `NotificationCenter` observer tokens for the focus pair. Removed
    /// in `deinit`. An app-lifetime service never tears down at runtime, but the
    /// tokens are held so removal is possible and the closures don't leak intent.
    ///
    /// `nonisolated(unsafe)`: assigned only on the main actor (in
    /// `registerFocusObservers`) and read once in the nonisolated `deinit`, when
    /// no concurrent access is possible — the same teardown pattern
    /// `GhosttySurfaceView` uses for its surface buffers.
    nonisolated(unsafe) private var observers: [NSObjectProtocol] = []

    init(store: AppStore) {
        self.store = store
    }

    deinit {
        // deinit is nonisolated; removeObserver(_:) is safe to call from any
        // thread. The loop Task is cancelled separately (it captures [weak self]).
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    /// Requests a git-status refresh for a session, subject to the throttle.
    ///
    /// Reads the session's `id` + `currentCwd` on the main actor, asks
    /// `GitRefreshPolicy` whether to proceed, and (if so) spawns the off-main
    /// worker. A nil/empty cwd is ignored — there is nothing to inspect yet.
    func requestRefresh(sessionID: UUID) {
        guard let session = store.session(withID: sessionID) else { return }
        // the effective cwd is currentCwd ?? initialCwd: a restored session has no
        // currentCwd until the shell emits OSC 7, so refreshing against initialCwd
        // surfaces git state immediately on launch/select instead of waiting for the
        // first PWD report. the live `cd` path still updates currentCwd, which then
        // becomes the effective cwd.
        let cwd = session.effectiveCwd
        guard !cwd.isEmpty else { return }
        let proceed = GitRefreshPolicy.shouldRefresh(
            cwd: cwd, lastRanCwd: lastRanCwd[sessionID], lastRanAt: lastRanAt[sessionID],
            now: Date(), minInterval: minInterval, inFlight: inFlight.contains(sessionID)
        )
        guard proceed else { return }
        spawnRefresh(sessionID: sessionID, cwd: cwd)
    }

    /// Refreshes the currently selected session, if any.
    func refreshActive() {
        guard let id = store.selectedSessionID else { return }
        requestRefresh(sessionID: id)
    }

    /// Starts the active-session refresh loop and registers the focus observers.
    ///
    /// Idempotent: a second call is a no-op (the observers are registered once and
    /// the loop is already running). Called when the scene appears.
    func start() {
        guard observers.isEmpty else { return }
        startActiveLoop()
        registerFocusObservers()
    }

    /// Spawns the active-session poll loop: a `Task { @MainActor … }` that wakes
    /// every `activeInterval` and refreshes the active session. A `Task.sleep`
    /// loop is used over a `Timer` to avoid a second `MainActor.assumeIsolated`
    /// site (ARCHITECTURE keeps `assumeIsolated` to the one RunLoop tick).
    private func startActiveLoop() {
        activeLoop?.cancel()
        let interval = activeInterval
        activeLoop = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard let self, !Task.isCancelled else { return }
                self.refreshActive()
            }
        }
    }

    /// Registers the single focus observer pair. On resign-active the poll loop is
    /// cancelled so a backgrounded app spawns no git; on become-active the loop is
    /// recreated and one immediate refresh runs (no separate become-active
    /// observer — the launch-time double-fire with the selection refresh is
    /// absorbed by the GitRefreshPolicy min-interval).
    private func registerFocusObservers() {
        let center = NotificationCenter.default
        // the forName:object:queue: closures are @Sendable, not statically
        // @MainActor, so reach the service via a single DispatchQueue.main.async hop
        // (the codebase convention) rather than MainActor.assumeIsolated. queue is
        // left nil so the closure isn't first enqueued onto main only to re-hop to
        // main — it runs on the posting thread, then makes exactly one hop.
        let resign = center.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: nil
        ) { [weak self] _ in
            DispatchQueue.main.async { self?.activeLoop?.cancel() }
        }
        let become = center.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: nil
        ) { [weak self] _ in
            DispatchQueue.main.async {
                self?.startActiveLoop()
                self?.refreshActive()
            }
        }
        observers = [resign, become]
    }

    /// Records the run as in-flight, spawns the detached worker against `cwd`, and
    /// hops back to the main actor with the result.
    private func spawnRefresh(sessionID: UUID, cwd: String) {
        inFlight.insert(sessionID)
        lastRanCwd[sessionID] = cwd
        lastRanAt[sessionID] = Date()
        let timeout = gitTimeout
        Task.detached {
            let status = GitStatusService.runGit(cwd: cwd, timeout: timeout)
            await MainActor.run {
                self.applyResult(sessionID: sessionID, ranCwd: cwd, status: status)
            }
        }
    }

    /// The completion hop, on the main actor. Clears the in-flight flag, then
    /// defers to the pure `GitApplyDecision` for the three guards before writing
    /// `session.gitStatus`:
    ///   1. stale-result: if the session's current cwd no longer equals the cwd
    ///      the worker ran for, discard and re-enqueue for the latest cwd;
    ///   2. equality-gate: only write when the value actually changed (an
    ///      `@Observable` write invalidates regardless of value, so an identical
    ///      tick would storm the sidebar reload + toolbar re-eval);
    ///   3. transient-failure: a nil result from a timeout/transient failure keeps
    ///      the previous status — never clobbers a known status to nil.
    private func applyResult(sessionID: UUID, ranCwd: String, status: GitRunResult) {
        guard let session = store.session(withID: sessionID) else {
            // the session was closed while the worker ran; drop its throttle state
            // (including the in-flight flag) so the dicts don't grow unbounded across
            // a long-lived run.
            forget(sessionID: sessionID)
            return
        }
        inFlight.remove(sessionID)

        let succeeded: Bool
        let parsed: GitStatus?
        switch status {
        case .failure: succeeded = false; parsed = nil
        case .success(let value): succeeded = true; parsed = value
        }

        // the three guards (stale-result / equality-gate / keep-prior-on-failure)
        // are the pure GitApplyDecision from agtCore; the service only acts on it.
        // compare against the session's *current* effective cwd so a run started from
        // initialCwd isn't treated as stale (currentCwd is nil until OSC 7 lands), while
        // a real `cd a; cd b` race — currentCwd has moved on — still re-enqueues.
        switch GitApplyDecision.decide(ranCwd: ranCwd, currentCwd: session.effectiveCwd,
                                       succeeded: succeeded, parsed: parsed, existing: session.gitStatus) {
        case .reEnqueue:
            requestRefresh(sessionID: sessionID)
        case .keepExisting:
            break
        case .write(let newValue):
            session.gitStatus = newValue
        }
    }

    /// Drops a closed session's throttle state so the per-session dicts don't grow
    /// unbounded over the app's lifetime. Called when a completion hop finds the
    /// session gone.
    private func forget(sessionID: UUID) {
        inFlight.remove(sessionID)
        lastRanCwd.removeValue(forKey: sessionID)
        lastRanAt.removeValue(forKey: sessionID)
    }

    /// The result of the off-main git run: a parsed status (possibly nil when the
    /// cwd is not a git work tree), or a transient failure (timeout / spawn error)
    /// that must not clobber a known status.
    private enum GitRunResult: Sendable {
        case success(GitStatus?)
        case failure
    }

    /// Runs the two git calls for `cwd` off the main actor and parses the result.
    ///
    /// `nonisolated static` so the `Task.detached` body runs on a background
    /// executor (not the main actor). The `Process`/`Pipe` are created, run, and
    /// drained entirely inside `runProcess(_:_:timeout:)` — never captured across
    /// a hop. A non-zero `git status` exit means the cwd is not a git work tree →
    /// `.success(nil)`. A timeout or spawn error → `.failure`.
    nonisolated private static func runGit(cwd: String, timeout: TimeInterval) -> GitRunResult {
        guard let statusRun = runProcess(["-C", cwd, "status", "--porcelain=v2", "--branch"], timeout: timeout) else {
            return .failure
        }
        // non-zero exit → not a git work tree (the "only if git controlled" gate).
        guard statusRun.exitCode == 0 else { return .success(nil) }

        // worktree detection is best-effort; a failed second call just omits the chip.
        let gitDir = runProcess(["-C", cwd, "rev-parse", "--git-dir"], timeout: timeout)
            .flatMap { $0.exitCode == 0 ? $0.output : nil }

        return .success(GitStatus.parse(porcelainV2: statusRun.output, gitDir: gitDir))
    }

    /// The output and exit code of a finished git process.
    private struct ProcessResult {
        let output: String
        let exitCode: Int32
    }

    /// Runs `git` with the given arguments, draining stdout and enforcing the
    /// timeout INLINE on this thread.
    ///
    /// The `Process`/`Pipe` live entirely within this call — never captured across
    /// an isolation boundary. stdout is drained by a dedicated reader `Thread` that
    /// blocks on `readDataToEndOfFile()` and signals `done` when it returns; this
    /// thread enforces the deadline via `done.wait(timeout:)`. Draining on a separate
    /// thread is what makes the timeout real: a blocking read on THIS thread would
    /// hang forever if git produces no output and never exits, leaving the timeout as
    /// dead code. `readDataToEndOfFile()` (no `readabilityHandler`) avoids the
    /// historically deadlock-/EOF-flaky `readabilityHandler` teardown on the macOS 14
    /// deployment target.
    ///
    /// On timeout, `terminate()` (SIGTERM, from this thread, which owns the `Process`)
    /// closes the child's write end, so the reader's blocking read hits EOF and
    /// returns; a short bounded wait absorbs that, then `waitUntilExit()` reaps the
    /// child so it doesn't zombie. If git ignores SIGTERM, the bounded wait times out
    /// and an uncatchable SIGKILL forces it down, so a wedged git can't hang the worker
    /// (and leave the session's in-flight flag stuck) indefinitely. A large dirty tree
    /// whose status exceeds the 64 KB pipe buffer can't deadlock, because the reader
    /// keeps draining the pipe while git writes. Returns nil on a spawn error or a
    /// timeout.
    nonisolated private static func runProcess(_ arguments: [String], timeout: TimeInterval) -> ProcessResult? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        // harden the auto-run: the cwd is terminal-reported (OSC 7), so disable
        // fsmonitor (don't auto-launch a repo-configured helper program) and opt out of
        // optional index locks. inherit the rest of the environment so git still finds
        // HOME/PATH for its normal config.
        process.arguments = ["-c", "core.fsmonitor=false"] + arguments
        process.environment = ProcessInfo.processInfo.environment.merging(
            ["GIT_OPTIONAL_LOCKS": "0"]) { _, override in override }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        let buffer = DrainBuffer()
        let done = DispatchSemaphore(value: 0)
        let readHandle = pipe.fileHandleForReading
        let reader = Thread {
            buffer.set(readHandle.readDataToEndOfFile())
            done.signal()
        }
        reader.start()

        do {
            try process.run()
        } catch {
            // the child never started, so the reader is blocked on a read that will
            // never see EOF; close the write end to unblock it before returning.
            try? pipe.fileHandleForWriting.close()
            _ = done.wait(timeout: .now() + 1)
            NSLog("agt: git spawn failed for %@: %@", arguments.joined(separator: " "), String(describing: error))
            return nil
        }

        if done.wait(timeout: .now() + timeout) == .timedOut {
            // terminate the child (this thread owns the Process); closing its write end
            // makes the reader's blocking read hit EOF and return. if git ignores
            // SIGTERM (e.g. wedged on an unresponsive mount), the reader never sees EOF
            // and the bounded wait times out → escalate to an uncatchable SIGKILL so a
            // stuck git can't hang this worker indefinitely.
            process.terminate()
            if done.wait(timeout: .now() + 1) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                _ = done.wait(timeout: .now() + 1)
            }
            process.waitUntilExit()
            return nil
        }
        process.waitUntilExit()

        let output = String(data: buffer.data, encoding: .utf8) ?? ""
        return ProcessResult(output: output, exitCode: process.terminationStatus)
    }

    /// A lock-guarded holder for the git stdout drained on the reader thread. The
    /// reader sets `data` before signalling `done`; the worker reads it only after
    /// the signal, and the `NSLock` keeps the cross-thread access data-race-free
    /// under strict concurrency.
    private final class DrainBuffer: @unchecked Sendable {
        private let lock = NSLock()
        private var storage = Data()

        func set(_ data: Data) {
            lock.lock()
            storage = data
            lock.unlock()
        }

        var data: Data {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }
    }
}
