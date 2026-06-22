# GENERATED CODE - DO NOT EDIT IN homebrew-racket.
# Source of truth: /Users/cutiedeng/Y2026/M06/D21/package-racket
# Humans and LLM agents must change package-racket and regenerate; manual tap edits are not production-safe.

class RacketAT9 < Formula
  desc "Modern programming language in the Lisp/Scheme family"
  homepage "https://racket-lang.org/"
  url "https://github.com/CutieDeng/racket/releases/download/v9.2.1/racket-minimal-9.2.1-src.tgz"
  version "9.2.1.3"
  sha256 "8000263185bdf872f299fe0dfc072cb1a5782995aae52f753e176c158d556166"
  license any_of: ["MIT", "Apache-2.0"]

  livecheck do
    skip "Private Racket fork releases are managed manually"
  end

  depends_on "openssl@3"

  uses_from_macos "libffi"

  on_linux do
    depends_on "libedit"
    depends_on "ncurses"
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

      ENV["LDFLAGS"] = "-rpath #{formula_opt_lib("openssl@3")}"
      ENV["LDFLAGS"] = "-Wl,-rpath=#{formula_opt_lib("openssl@3")}" if OS.linux?

      system "./configure", *args
      system "make"
      system "make", "install"

      if OS.mac?
        openssl_opt_lib = formula_opt_lib("openssl@3")
        racket_libdir = lib/"racket"

        %w[libssl.3.dylib libcrypto.3.dylib].each do |dylib|
          path = racket_libdir/dylib
          path.unlink if path.exist?
        end

        ln_s openssl_opt_lib/"libssl.3.dylib",    racket_libdir/"libssl.3.dylib"
        ln_s openssl_opt_lib/"libcrypto.3.dylib", racket_libdir/"libcrypto.3.dylib"
      end
    end

    inreplace racket_config,
              /\(compiled-file-roots \. \(same ("[^"]+")\)\)/,
              '(compiled-file-roots . (\1))'
    system bin/"raco", "setup", "--no-user"
    prune_build_compile_cache
  end

  def post_install
    system bin/"raco", "setup", "--no-user"
    prune_build_compile_cache
  end

  def prune_build_compile_cache
    rm_r Dir["#{lib}/racket/compiled/**/ephemeral"]
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

    (testpath/"rhombus-smoke.rhm").write <<~RHOMBUS
      #lang rhombus
      println("rhombus-lang-ok")
    RHOMBUS
    output = shell_output("#{bin}/racket #{testpath/"rhombus-smoke.rhm"}")
    assert_match "rhombus-lang-ok", output

    output = shell_output("#{bin}/rhombus --version")
    assert_match "Welcome to Rhombus v1.0", output

    output = shell_output("#{bin}/rhombus -e '1 + 2'")
    assert_match "3", output

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
    refute_match(/no readline support/, pty_output)
    assert !pty_output.match?(/> \r?\n\(/), "empty input fell back to the plain REPL reader"

    assert_match '(default-scope . "installation")', racket_config.read

    if OS.mac?
      output = shell_output("DYLD_PRINT_LIBRARIES=1 #{bin}/racket -e '(require openssl)' 2>&1")
      assert_match(%r{.*openssl@3/.*/libssl.*\.dylib}, output)
    else
      output = shell_output("LD_DEBUG=libs #{bin}/racket -e '(require openssl)' 2>&1")
      assert_match "init: #{formula_opt_lib("openssl@3")/shared_library("libssl")}", output
    end
  end
end
