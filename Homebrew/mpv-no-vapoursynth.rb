# Custom mpv formula without vapoursynth dependency
# This removes the Python 3.14 requirement for Glass Player users
# who only need playback and Anime4K upscaling (not vapoursynth filters).
#
# Installation:
#   brew uninstall mpv
#   brew install ./Homebrew/mpv-no-vapoursynth.rb
#
# Verification:
#   otool -L /opt/homebrew/lib/libmpv.2.dylib | grep vapoursynth
#   (should return nothing if built without vapoursynth)

class MpvNoVapoursynth < Formula
  desc "Media player based on MPlayer and mplayer2 (without vapoursynth)"
  homepage "https://mpv.io"
  url "https://github.com/mpv-player/mpv/archive/refs/tags/v0.41.0.tar.gz"
  sha256 "ee21092a5ee427353392360929dc64645c54479aefdb5babc5cfbb5fad626209"
  license :cannot_represent

  depends_on "docutils" => :build
  depends_on "meson" => :build
  depends_on "ninja" => :build
  depends_on "pkgconf" => [:build, :test]
  depends_on xcode: :build

  # Core dependencies (same as stock mpv)
  depends_on "ffmpeg"
  depends_on "jpeg-turbo"
  depends_on "libarchive"
  depends_on "libass"
  depends_on "libbluray"
  depends_on "libplacebo"
  depends_on "little-cms2"
  depends_on "luajit"
  depends_on "mujs"
  depends_on "rubberband"
  depends_on "uchardet"
  # NOTE: vapoursynth intentionally disabled to remove Python 3.14 dependency
  depends_on "vulkan-loader"
  depends_on "yt-dlp"
  depends_on "zimg"

  on_macos do
    depends_on "molten-vk"
  end

  on_linux do
    depends_on "alsa-lib"
    depends_on "libva"
    depends_on "libvdpau"
    depends_on "libx11"
    depends_on "libxext"
    depends_on "libxfixes"
    depends_on "libxkbcommon"
    depends_on "libxpresent"
    depends_on "libxrandr"
    depends_on "libxscrnsaver"
    depends_on "libxv"
    depends_on "mesa"
    depends_on "pulseaudio"
    depends_on "wayland"
    depends_on "wayland-protocols" => :no_linkage
    depends_on "zlib-ng-compat"
  end

  conflicts_with "mpv", because: "both install mpv binaries"

  def install
    # LANG is unset by default on macOS and causes issues with getlocale
    ENV["LC_ALL"] = "C"

    # Force meson to use homebrew ninja
    ENV["NINJA"] = which("ninja")

    # libarchive is keg-only
    ENV.prepend_path "PKG_CONFIG_PATH", Formula["libarchive"].opt_lib/"pkgconfig" if OS.mac?

    args = %W[
      -Dbuild-date=false
      -Dhtml-build=enabled
      -Djavascript=enabled
      -Dlibmpv=true
      -Dlua=luajit
      -Dlibarchive=enabled
      -Duchardet=enabled
      -Dvulkan=enabled
      -Dvapoursynth=disabled
      --sysconfdir=#{pkgetc}
      --datadir=#{pkgshare}
      --mandir=#{man}
    ]

    if OS.linux?
      args += %w[
        -Degl=enabled
        -Dwayland=enabled
        -Dx11=enabled
      ]
    end

    system "meson", "setup", "build", *args, *std_meson_args
    system "meson", "compile", "-C", "build", "--verbose"
    system "meson", "install", "-C", "build"

    if OS.mac?
      # `pkg-config --libs mpv` includes libarchive, but that package is
      # keg-only so it needs to look for the pkgconfig file in libarchive's opt
      # path.
      libarchive = Formula["libarchive"].opt_prefix
      inreplace lib/"pkgconfig/mpv.pc" do |s|
        s.gsub!(/^Requires\.private:(.*)\blibarchive\b(.*?)(,.*)?$/,
                "Requires.private:\\1#{libarchive}/lib/pkgconfig/libarchive.pc\\3")
      end
    end

    bash_completion.install "etc/mpv.bash_completions" => "mpv" if File.exist?("etc/mpv.bash_completions")
    zsh_completion.install "etc/_mpv.zsh" => "_mpv" if File.exist?("etc/_mpv.zsh")
  end

  test do
    system bin/"mpv", "--ao=null", "--vo=null", test_fixtures("test.wav")

    # Verify vapoursynth is NOT available (should return error or empty)
    vs_output = shell_output("#{bin}/mpv --vf=help 2>&1")
    raise "vapoursynth should not be available" if vs_output.include?("vapoursynth")

    # Make sure `pkgconf` can parse `mpv.pc`
    system "pkgconf", "--print-errors", "mpv"
  end
end
