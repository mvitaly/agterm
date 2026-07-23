cask "agterm-intel" do
  version "0.16.1-7-g94aa1a6"
  sha256 "a7a98fe94a07a2a4ff5a1b8a962f0189650f35308c03776d5c4827fccc26c8fb"

  url "https://github.com/mvitaly/agterm/releases/download/intel-latest/agterm-intel.dmg"
  name "agterm (Intel build)"
  desc "Native macOS terminal on libghostty — unofficial x86_64 build for Intel Macs"
  homepage "https://github.com/mvitaly/agterm"

  depends_on macos: :sonoma
  depends_on arch: :x86_64

  app "agterm.app"
  binary "#{appdir}/agterm.app/Contents/MacOS/agtermctl", target: "agtermctl"

  # unlike upstream's releases this build is ad-hoc signed (not
  # notarized), so stripping quarantine is what makes first launch clean
  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-dr", "com.apple.quarantine", "#{appdir}/agterm.app"],
                   sudo: false
  end

  zap trash: [
    "~/Library/Application Support/agterm",
    "~/Library/Preferences/com.umputun.agterm.plist",
    "~/Library/Saved Application State/com.umputun.agterm.savedState",
  ]
end
