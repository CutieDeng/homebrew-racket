class RacketAT9 < Formula
  desc "Modern programming language in the Lisp/Scheme family"
  homepage "https://racket-lang.org/"
  url "https://github.com/CutieDeng/racket/releases/download/v9.2.1/racket-minimal-9.2.1-src.tgz"
  sha256 "e2058689ccc65280bfbd58aa7016632982da72f90949e07766cf2a3e9ac84765"
  license any_of: ["MIT", "Apache-2.0"]

  livecheck do
    skip "Private Racket fork releases are managed manually"
  end

  depends_on "openssl@3"

  uses_from_macos "libffi"

  on_linux do
    depends_on "zlib-ng-compat"
  end

  # These files are amended when packages are installed or removed.
  skip_clean "lib/racket/launchers.rktd", "lib/racket/mans.rktd"

  def racket_config
    etc/"racket/config.rktd"
  end

  def install
    # Configure racket's package tool (raco) to use installation scope.
    inreplace "etc/config.rktd", /\)\)\n$/, ") (default-scope . \"installation\"))\n"

    # Prefer Homebrew OpenSSL 3 over older OpenSSL variants.
    inreplace %w[libssl.rkt libcrypto.rkt].map { |file| buildpath/"collects/openssl"/file },
              '"1.1"', '"3"'

    cd "src" do
      args = %W[
        --disable-debug
        --disable-dependency-tracking
        --enable-origtree=no
        --enable-macprefix
        --prefix=#{prefix}
        --mandir=#{man}
        --sysconfdir=#{etc}
        --enable-useprefix
      ]

      ENV["LDFLAGS"] = "-rpath #{Formula["openssl@3"].opt_lib}"
      ENV["LDFLAGS"] = "-Wl,-rpath=#{Formula["openssl@3"].opt_lib}" if OS.linux?

      system "./configure", *args
      system "make"
      system "make", "install"

      if OS.mac?
        openssl = Formula["openssl@3"]
        racket_libdir = lib/"racket"

        %w[libssl.3.dylib libcrypto.3.dylib].each do |dylib|
          path = racket_libdir/dylib
          path.unlink if path.exist?
        end

        ln_s openssl.opt_lib/"libssl.3.dylib",    racket_libdir/"libssl.3.dylib"
        ln_s openssl.opt_lib/"libcrypto.3.dylib", racket_libdir/"libcrypto.3.dylib"
      end
    end

    inreplace racket_config, prefix, opt_prefix
  end

  def post_install
    system bin/"raco", "setup"

    return unless racket_config.read.include?(HOMEBREW_CELLAR)

    ohai "Fixing up Cellar references in #{racket_config}..."
    inreplace racket_config, %r{#{Regexp.escape(HOMEBREW_CELLAR)}/racket@9/[^/]+}o, opt_prefix
  end

  def caveats
    <<~EOS
      This formula is intended to provide the active Homebrew `racket` and
      `raco` commands.

      If an official Racket formula or cask is already installed, remove it
      before installing this formula:
        brew uninstall minimal-racket
        brew uninstall --cask racket
    EOS
  end

  test do
    assert_match "9.2.1", shell_output("#{bin}/racket -e '(displayln (version))'")

    output = shell_output("#{bin}/racket -e '(require racket/pvector) (displayln (pvector->list (pvector 1 2 3)))'")
    assert_match "(1 2 3)", output

    assert_match '(default-scope . "installation")', racket_config.read

    if OS.mac?
      output = shell_output("DYLD_PRINT_LIBRARIES=1 #{bin}/racket -e '(require openssl)' 2>&1")
      assert_match(%r{.*openssl@3/.*/libssl.*\.dylib}, output)
    else
      output = shell_output("LD_DEBUG=libs #{bin}/racket -e '(require openssl)' 2>&1")
      assert_match "init: #{Formula["openssl@3"].opt_lib/shared_library("libssl")}", output
    end
  end
end
