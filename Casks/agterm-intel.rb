cask "agterm-intel" do
  version "0.16.1-20-gb7c2331"
  sha256 "a5ec780ee2ab5027b1916983a358624473f9715fdcaa43a2e302716acc447ac8"

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
