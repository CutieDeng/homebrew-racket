class RacketAT9 < Formula
  desc "Modern programming language in the Lisp/Scheme family"
  homepage "https://racket-lang.org/"
  url "https://github.com/CutieDeng/racket/releases/download/v9.2.1/racket-minimal-9.2.1-src.tgz"
  sha256 "7c465fb85f7f838d5cd1354d56e66515c14bd5b2c4ac0038947e749e80e2e2d7"
  license any_of: ["MIT", "Apache-2.0"]

  livecheck do
    skip "Private Racket fork releases are managed manually"
  end

  bottle do
    root_url "https://github.com/CutieDeng/racket/releases/download/v9.2.1"
    rebuild 1
    sha256 arm64_tahoe:  "9dcc1ed0e90d74195ce959e5e2bcc8118dd22dc7a3b76a16ffb4caf0a683d28e"
    sha256 x86_64_linux: "206e03b56657e2a3fac43af131fc9dcdadfc0163f1756032e87daf647382b473"
  end

  depends_on "openssl@3"

  uses_from_macos "libffi"

  on_linux do
    depends_on "libedit"
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
    require "pty"
    require "timeout"

    assert_match "9.2.1", shell_output("#{bin}/racket -e '(displayln (version))'")

    output = shell_output("#{bin}/racket -e '(require racket/pvector) (displayln (pvector->list (pvector 1 2 3)))'")
    assert_match "(1 2 3)", output

    (testpath/"interactive-packages.rkt").write <<~RACKET
      #lang racket/base
      (for ([p '(("main.rkt" "xrepl")
                 ("main.rkt" "expeditor")
                 ("pread.rkt" "readline"))])
        (unless (collection-file-path (car p) (cadr p) #:fail (lambda _ #f))
          (error (cadr p) "collection missing")))
      (displayln "interactive-packages-ok")
    RACKET
    output = shell_output("#{bin}/racket #{testpath/"interactive-packages.rkt"}")
    assert_match "interactive-packages-ok", output

    output = shell_output("printf '1\\n' | #{bin}/racket")
    assert_match "Welcome to Racket v9.2.1 [cs].", output
    assert_match(/^> 1$/, output)

    output = shell_output("printf 'f\"hi\"\\n' | #{bin}/racket")
    assert_match(/^> "hi"$/, output)

    pty_output = +""
    read_available = lambda do |reader, timeout|
      loop do
        pty_output << Timeout.timeout(timeout) { reader.readpartial(4096) }
        timeout = 0.1
      end
    rescue Timeout::Error, EOFError
      pty_output
    end
    read_until_result = lambda do |reader|
      loop do
        pty_output << Timeout.timeout(0.5) { reader.readpartial(4096) }
        break if pty_output.include?("#t")
      end
    rescue Timeout::Error, EOFError
      pty_output
    end
    Timeout.timeout(5) do
      PTY.spawn({ "TERM" => "xterm-256color" }, "#{bin}/racket") do |r, w, pid|
        read_available.call(r, 0.5)
        w.write "\n"
        read_available.call(r, 0.5)
        w.puts "(= 1 1)"
        read_until_result.call(r)
        w.write "\x04"
        Process.kill("KILL", pid)
        Process.detach(pid)
      end
    end
    assert_match "Welcome to Racket v9.2.1 [cs].", pty_output
    assert_match "\n#t", pty_output
    if OS.mac?
      assert_match(/\e\[/, pty_output)
    else
      refute_match(/no readline support/, pty_output)
    end
    assert !pty_output.match?(/> \r?\n\(/), "empty input fell back to the plain REPL reader"

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
