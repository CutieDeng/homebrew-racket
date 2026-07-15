# GENERATED CODE - DO NOT EDIT IN homebrew-racket.
# Source of truth: https://github.com/CutieDeng/package-racket
# Humans and LLM agents must change package-racket and regenerate; manual tap edits are not production-safe.

class RacketAT9 < Formula
  desc "Modern programming language in the Lisp/Scheme family"
  homepage "https://racket-lang.org/"
  url "https://github.com/CutieDeng/racket/releases/download/v9.2.3/racket-minimal-9.2.3-src.tgz"
  version "9.2.3.2"
  sha256 "3a0c633eefe21a86a6ab328773b6033767dde0e5a02c94553b180020fbde4054"
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

  def system_cache_root
    prefix/"var/cache/racket/compiled"
  end

  def configure_racket
    config_entries = [
      "(default-scope . \"installation\")",
      "(compiled-file-cache-roots . (user system))",
      "(compiled-file-system-cache-root . \"#{system_cache_root}\")",
    ].join(" ")
    content = racket_config.read
    %w[
      default-scope
      compiled-file-cache-roots
      compiled-file-system-cache-root
    ].each do |key|
      content = content.gsub(/\s*\(#{Regexp.escape(key)}\s+\.\s+(?:"[^"]*"|\([^)]*\)|[^\s)]*)\)/, "")
    end
    raise "could not append Racket config entries" unless content.sub!(/\)\s*\z/, " #{config_entries})\n")

    racket_config.atomic_write content
  end

  def install
    # Prefer Homebrew OpenSSL 3 over older OpenSSL variants.
    inreplace %w[libssl.rkt libcrypto.rkt].map { |file| buildpath/"collects/openssl"/file },
              '"1.1"', '"3"'

    cd "src" do
      args = %W[
        --disable-debug
        --disable-dependency-tracking
        --enable-origtree=no
        --enable-sharezo
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

    system bin/"raco", "setup", "--no-user", "--no-zo"
    configure_racket
    if build.bottle?
      setup_system_cache
      remove_precompiled_cache
    end
  end

  def system_cache_roots
    [
      prefix/"var/cache/racket/compiled#{share}/racket/collects",
      prefix/"var/cache/racket/compiled#{share}/racket/pkgs",
    ]
  end

  def system_cache_populated?
    system_cache_roots.all? { |root| !Dir["#{root}/**/compiled/*.zo"].empty? }
  end

  def with_setup_bootstrap_config
    require "tmpdir"

    Dir.mktmpdir("racket-setup-bootstrap-config") do |dir|
      config_dir = Pathname(dir)
      content = racket_config.read.gsub(/\s*\(compiled-file-cache-roots\s+\.\s+\([^)]*\)\)/, "")
      unless content.include?("compiled-file-system-cache-root")
        raise "could not prepare Racket setup bootstrap config"
      end

      (config_dir/"config.rktd").write content
      yield config_dir
    end
  end

  def setup_system_cache
    system_cache_root.mkpath
    with_setup_bootstrap_config do |config_dir|
      system bin/"racket", "-U", "-G", config_dir.to_s, "-N", "raco", "-l-", "raco", "setup",
             "--system", "--no-user", "--reset-cache", "-D", "--no-pkg-deps", "--no-launcher"
    end
    system bin/"racket", "-U", "-R", system_cache_root.to_s, "-N", "rhombus",
           "-l-", "rhombus/run.rhm", "--version"
    system bin/"racket", "-U", "-R", system_cache_root.to_s, "-N", "rhombus",
           "-l-", "rhombus/run.rhm", "-e", "println(\"package-racket-rhombus-cache\")"
  end

  def post_install
    setup_system_cache unless system_cache_populated?
    remove_precompiled_cache
  end

  def preserve_compiled_cache_dir?(path)
    path = Pathname(path).cleanpath
    preserved_roots = [system_cache_root].map(&:cleanpath)
    preserved_roots.any? do |root|
      path == root || path.to_s.start_with?("#{root}/") || root.to_s.start_with?("#{path}/")
    end
  end

  def remove_precompiled_cache
    Dir["#{prefix}/**/compiled"].sort_by(&:length).reverse_each do |dir|
      next if preserve_compiled_cache_dir?(dir)
      next if dir.end_with?("/info-domain/compiled")

      rm_r dir
    end
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

    assert_match "9.2.3", shell_output("#{bin}/racket -e '(displayln (version))'")
    output = shell_output("#{bin}/racket -e '(require racket/pvector) (displayln (pvector->list (pvector 1 2 3)))'")
    assert_match "(1 2 3)", output
    assert system_cache_populated?, "system compiled cache is empty"

    empty_home = testpath/"empty-home"
    empty_home.mkpath
    output = shell_output(
      "HOME=#{empty_home} #{bin}/racket " \
      "-e '(require racket/list racket/match racket/file) (displayln \"brew-empty-home-ok\")'",
    )
    assert_match "brew-empty-home-ok", output

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
    assert_match "Welcome to Racket v9.2.3 [cs].", output
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
    assert_match "Welcome to Racket v9.2.3 [cs].", pty_output
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
