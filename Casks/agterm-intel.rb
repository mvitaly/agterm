cask "agterm-intel" do
  version "0.15.3-5-gca753a2"
  sha256 "45c799068b958e7e81e588c62b11dd73deb88b1fe84685291e5f7a05cf623d09"

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
