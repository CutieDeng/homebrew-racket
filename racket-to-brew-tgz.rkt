#lang reader tstring/lang/reader racket/base

(require file/tar
         racket/cmdline
         racket/file
         racket/list
         racket/match
         racket/path
         racket/port
         racket/runtime-path
         racket/string)

(define-runtime-path script-dir ".")

(define stage-marker-file ".racket-to-brew-tgz-stage")

(define default-packages
  '("base"
    "racket-lib"
    "racket-aarch64-macosx-4"
    "racket-tstring"
    "tstring"
    "xrepl-lib"
    "expeditor-lib"
    "readline-lib"
    "scribble-text-lib"
    "syntax-color-lib"
    "parser-tools-lib"
    "option-contract-lib"
    "scheme-lib"
    "at-exp-lib"
    "rackunit-lib"
    "testing-util-lib"
    "compiler-lib"
    "zo-lib"))

(define package-links
  '(("base" . root)
    ("racket-lib" . root)
    ("racket-aarch64-macosx-4" . root)
    ("racket-tstring" . "racket-tstring")
    ("tstring" . "tstring")
    ("xrepl-lib" . root)
    ("expeditor-lib" . "expeditor")
    ("readline-lib" . root)
    ("scribble-text-lib" . root)
    ("syntax-color-lib" . root)
    ("parser-tools-lib" . root)
    ("option-contract-lib" . root)
    ("scheme-lib" . root)
    ("at-exp-lib" . root)
    ("rackunit-lib" . root)
    ("testing-util-lib" . root)
    ("compiler-lib" . root)
    ("zo-lib" . root)))

(define (println/flush msg)
  (displayln msg)
  (flush-output))

(define (clean-path-string p)
  (path->string (simplify-path (path->complete-path p))))

(define (assert-directory who p)
  (unless (directory-exists? p)
    (raise-user-error who f"directory does not exist: {(clean-path-string p)}")))

(define (assert-file who p)
  (unless (file-exists? p)
    (raise-user-error who f"file does not exist: {(clean-path-string p)}")))

(define (read-racket-version racket-root)
  (define version-file (build-path racket-root "racket" "src" "version" "racket_version.h"))
  (assert-file 'read-racket-version version-file)
  (define content (file->string version-file))
  (define (macro-int name)
    (define rx (pregexp f"#define[ \t]+{(regexp-quote name)}[ \t]+([0-9]+)"))
    (match (regexp-match rx content)
      [(list _ n) (string->number n)]
      [_ (raise-user-error 'read-racket-version
                           f"could not find {name} in {(clean-path-string version-file)}")]))
  (define x (macro-int "MZSCHEME_VERSION_X"))
  (define y (macro-int "MZSCHEME_VERSION_Y"))
  (define z (macro-int "MZSCHEME_VERSION_Z"))
  (define w (macro-int "MZSCHEME_VERSION_W"))
  (cond
    [(not (zero? w)) f"{x}.{y}.{z}.{w}"]
    [(not (zero? z)) f"{x}.{y}.{z}"]
    [else f"{x}.{y}"]))

(define (release-catalog-url version)
  (match (regexp-match #rx"^([0-9]+)[.]([0-9]+)" version)
    [(list _ major minor)
     f"https://download.racket-lang.org/releases/{major}.{minor}/catalog/"]
    [_ (raise-user-error 'release-catalog-url
                         f"cannot derive release catalog from version: {version}")]))

(define (write-source-readme dest version)
  (call-with-output-file dest
    #:exists 'truncate/replace
    (lambda (out)
      (display f"The Racket Programming Language
===============================

This is the
  Minimal Racket | All Platforms | Source
distribution for version {version}.

This distribution provides source for the Racket run-time system;
for build and installation instructions, see \"src/README.txt\".
(The distribution also includes the core Racket collections and any
installed packages in source form.)

The distribution has been configured so that when you install or
update packages, the package catalogs at
  {(release-catalog-url version)}
  https://download.rhombus-lang.org/releases/current/catalog/
are consulted first.

Visit http://racket-lang.org/ for more Racket resources.


License
-------

Racket is distributed under the MIT license and the Apache version 2.0
license, at your option.

The Racket runtime system includes components distributed under
other licenses. See \"src/LICENSE.txt\" for more information.

Racket packages that are included in the distribution have their own
licenses. See the package files in \"pkgs\" within \"share\" for more
information.
" out))))

(define (write-config dest version)
  (define catalogs
    (list (release-catalog-url version)
          "https://download.rhombus-lang.org/releases/current/catalog/"
          #f))
  (call-with-output-file dest
    #:exists 'truncate/replace
    (lambda (out)
      (write `#hash((catalogs . ,catalogs)
                    (gui-interactive-file . racket/gui/interactive)
                    (installation-name . ,version)
                    (interactive-file . racket/interactive/tstring))
             out)
      (newline out))))

(define (skip-path? rel)
  (define elems (map path->string (explode-path rel)))
  (define base (if (null? elems) "" (last elems)))
  (or (for/or ([elem (in-list elems)])
        (member elem '(".git" ".hg" ".svn" ".github" "compiled")))
      (member base '(".gitattributes" ".gitignore"))
      (string-prefix? base ".LOCK")
      (member base '(".DS_Store" "_zuo.db" "_zuo_tc.db"))
      (regexp-match? #rx"[.]zo$" base)
      (regexp-match? #rx"[.]dep$" base)
      (regexp-match? #rx"[.]bak$" base)
      (regexp-match? #rx"[.]orig$" base)
      (regexp-match? #rx"[.]rej$" base)
      (regexp-match? #rx"~$" base)))

(define (copy-tree* src dest #:skip-first-components [skip-first-components '()])
  (assert-directory 'copy-tree* src)
  (when (directory-exists? dest)
    (delete-directory/files dest))
  (make-directory* dest)
  (define src/ (path->directory-path src))
  (for ([path (in-list (sort (find-files (lambda (_) #t) src)
                             path<?
                             #:key (lambda (p) (find-relative-path src/ p))))])
    (unless (equal? (simplify-path path) (simplify-path src))
      (define rel (find-relative-path src/ path))
      (define rel-elems (map path->string (explode-path rel)))
      (unless (or (skip-path? rel)
                  (and (pair? rel-elems)
                       (member (car rel-elems) skip-first-components)))
        (define target (build-path dest rel))
        (cond
          [(directory-exists? path)
           (make-directory* target)
           (file-or-directory-permissions target (file-or-directory-permissions path 'bits))]
          [(file-exists? path)
           (make-directory* (path-only target))
           (copy-file path target #t)
           (file-or-directory-permissions target (file-or-directory-permissions path 'bits))]
          [(link-exists? path)
           (make-directory* (path-only target))
           (copy-file path target #t)])))))

(define (package-source racket-root name)
  (define candidates
    (list (build-path racket-root "pkgs" name)
          (build-path racket-root "racket" "share" "pkgs" name)))
  (or (for/or ([candidate (in-list candidates)])
        (and (directory-exists? candidate) candidate))
      (raise-user-error 'package-source
                        f"cannot find package {name} in {(clean-path-string racket-root)}/pkgs or {(clean-path-string racket-root)}/racket/share/pkgs")))

(define (datum->source v)
  (call-with-output-string (lambda (out) (write v out))))

(define (write-links dest packages)
  (define entries
    (for/list ([name (in-list packages)])
      (define link-name (cdr (assoc name package-links)))
      (cond
        [(eq? link-name 'root) `(root (#"pkgs" ,(string->bytes/utf-8 name)))]
        [else `(,link-name (#"pkgs" ,(string->bytes/utf-8 name)))])))
  (call-with-output-file dest
    #:exists 'truncate/replace
    (lambda (out)
      (write entries out)
      (newline out))))

(define (write-pkgs-db dest packages)
  (define entries
    (for/hash ([name (in-list packages)])
      (define auto? (not (member name '("racket-lib" "tstring"))))
      (define value
        (cond
          [(member name '("racket-tstring" "tstring"))
           f"#s((sc-pkg-info pkg-info 3) (catalog {(datum->source name)}) \"\" {(if auto? "#t" "#f")} {(datum->source name)})"]
          [else
           f"#s(pkg-info (catalog {(datum->source name)}) \"\" {(if auto? "#t" "#f")})"]))
      (values name value)))
  (call-with-output-file dest
    #:exists 'truncate/replace
    (lambda (out)
      (fprintf out "#hash(")
      (for ([name (in-list (sort packages string<?))]
            [idx (in-naturals)])
        (unless (zero? idx)
          (display " " out))
        (fprintf out "(~s . ~a)" name (hash-ref entries name)))
      (fprintf out ")\n"))))

(define (copy-licenses racket-root dest-share)
  (for ([name (in-list '("LICENSE-APACHE.txt"
                        "LICENSE-GPL.txt"
                        "LICENSE-LGPL.txt"
                        "LICENSE-MIT.txt"
                        "LICENSE-libscheme.txt"
                        "LICENSE.txt"))])
    (define src
      (let ([share-src (build-path racket-root "racket" "share" name)]
            [src-src (build-path racket-root "racket" "src" name)])
        (cond
          [(file-exists? share-src) share-src]
          [(file-exists? src-src) src-src]
          [else (raise-user-error 'copy-licenses f"missing license file: {name}")])))
    (copy-file src (build-path dest-share name) #t)))

(define (stage-source racket-root stage-root version packages)
  (define dist-root (build-path stage-root f"racket-{version}"))
  (when (directory-exists? dist-root)
    (delete-directory/files dist-root))
  (make-directory* dist-root)
  (write-source-readme (build-path dist-root "README") version)
  (make-directory* (build-path dist-root "etc"))
  (write-config (build-path dist-root "etc" "config.rktd") version)
  (copy-tree* (build-path racket-root "racket" "collects")
              (build-path dist-root "collects"))
  (copy-tree* (build-path racket-root "racket" "src")
              (build-path dist-root "src")
              #:skip-first-components '("build"))
  (define share-dir (build-path dist-root "share"))
  (define pkgs-dir (build-path share-dir "pkgs"))
  (make-directory* pkgs-dir)
  (copy-licenses racket-root share-dir)
  (write-links (build-path share-dir "links.rktd") packages)
  (write-pkgs-db (build-path pkgs-dir "pkgs.rktd") packages)
  (for ([name (in-list packages)])
    (copy-tree* (package-source racket-root name)
                (build-path pkgs-dir name)))
  dist-root)

(define (relative-files-from base root)
  (define base/ (path->directory-path base))
  (sort
   (for/list ([p (in-list (find-files file-exists? root))])
     (find-relative-path base/ p))
   path<?))

(define (make-tgz dist-root tgz-path)
  (define parent (path-only dist-root))
  (define tar-path (path-replace-extension tgz-path #".tar"))
  (when (file-exists? tar-path)
    (delete-file tar-path))
  (when (file-exists? tgz-path)
    (delete-file tgz-path))
  (parameterize ([current-directory parent])
    (call-with-output-file tar-path
      #:exists 'truncate/replace
      (lambda (out)
        (tar->output (relative-files-from parent (file-name-from-path dist-root))
                     out
                     #:timestamp 0
                     #:format 'pax))))
  (define-values (proc out in err)
    (subprocess #f #f #f (find-executable-path "gzip") "-n" "-c" (path->string tar-path)))
  (close-output-port in)
  (call-with-output-file tgz-path
    #:exists 'truncate/replace
    (lambda (tgz-out)
      (copy-port out tgz-out)))
  (define stderr (port->string err))
  (subprocess-wait proc)
  (define status (subprocess-status proc))
  (close-input-port out)
  (close-input-port err)
  (delete-file tar-path)
  (unless (zero? status)
    (raise-user-error 'make-tgz f"gzip failed with exit {status}: {stderr}")))

(define (default-formula-path)
  (build-path script-dir "Formula" "racket@9.rb"))

(define (default-artifact-dir)
  (build-path script-dir "artifacts"))

(define (default-stage-dir)
  (build-path script-dir ".build" "racket-to-brew-tgz-stage"))

(define (formula-version content)
  (match (regexp-match #px"racket-minimal-([^/\"]+)-src[.]tgz" content)
    [(list _ version) version]
    [_ #f]))

(define (update-formula! formula-path version digest)
  (assert-file 'update-formula! formula-path)
  (define content (file->string formula-path))
  (define old-version (or (formula-version content) version))
  (define version-updated
    (if (string=? old-version version)
        content
        (regexp-replace* (regexp-quote old-version) content version)))
  (define source-url
    f"https://github.com/CutieDeng/racket/releases/download/v{version}/racket-minimal-{version}-src.tgz")
  (define formula-lines
    (let loop ([lines (string-split version-updated "\n" #:trim? #f)])
      (cond
        [(and (pair? lines) (string=? (last lines) ""))
         (loop (drop-right lines 1))]
        [else lines])))
  (define saw-source-url? #f)
  (define source-url-updated? #f)
  (define source-sha-updated? #f)
  (define root-url-updated? #f)
  (define updated-lines
    (for/list ([line (in-list formula-lines)])
      (cond
        [(regexp-match? #px"^  url \"[^\"]+\"$" line)
         (set! saw-source-url? #t)
         (set! source-url-updated? #t)
         f"  url \"{source-url}\""]
        [(and saw-source-url?
              (regexp-match? #px"^  sha256 \"[0-9a-f]{64}\"$" line))
         (set! saw-source-url? #f)
         (set! source-sha-updated? #t)
         f"  sha256 \"{digest}\""]
        [(regexp-match? #px"^    root_url \"[^\"]+\"$" line)
         (set! saw-source-url? #f)
         (set! root-url-updated? #t)
         f"    root_url \"https://github.com/CutieDeng/racket/releases/download/v{version}\""]
        [else
         (set! saw-source-url? #f)
         line])))
  (unless (and source-url-updated? source-sha-updated? root-url-updated?)
    (raise-user-error 'update-formula!
                      f"could not update all formula fields: source-url={source-url-updated?} source-sha={source-sha-updated?} root-url={root-url-updated?}"))
  (define with-root-url (string-join updated-lines "\n"))
  (call-with-output-file formula-path
    #:exists 'truncate/replace
    (lambda (out)
      (display with-root-url out)
      (newline out)))
  (println/flush f"Updated formula: {(clean-path-string formula-path)}"))

(define (bytes->lower-hex bs)
  (define digits "0123456789abcdef")
  (list->string
   (for*/list ([b (in-bytes bs)]
               [n (in-list (list (arithmetic-shift b -4)
                                 (bitwise-and b #xF)))])
     (string-ref digits n))))

(define (sha256-file path)
  (call-with-input-file path
    (lambda (in)
      (bytes->lower-hex (sha256-bytes in)))))

(define (empty-directory? path)
  (null? (directory-list path)))

(define (prepare-stage-dir! stage-dir)
  (define marker (build-path stage-dir stage-marker-file))
  (cond
    [(directory-exists? stage-dir)
     (cond
       [(file-exists? marker)
        (delete-directory/files stage-dir)]
       [(empty-directory? stage-dir)
        (void)]
       [else
        (raise-user-error 'prepare-stage-dir!
                          f"stage directory exists and is not managed by this tool: {(clean-path-string stage-dir)}")])]
    [(file-exists? stage-dir)
     (raise-user-error 'prepare-stage-dir!
                       f"stage path exists but is not a directory: {(clean-path-string stage-dir)}")]
    [else
     (void)])
  (make-directory* stage-dir)
  (call-with-output-file marker
    #:exists 'truncate/replace
    (lambda (out)
      (displayln "managed by racket-to-brew-tgz.rkt" out))))

(define racket-root-arg #f)
(define artifact-dir-arg #f)
(define stage-dir-arg #f)
(define version-arg #f)
(define keep-stage? #f)
(define update-formula? #t)
(define formula-path-arg #f)
(define package-args '())

(command-line
 #:program "racket-to-brew-tgz.rkt"
 #:once-each
 [("--racket-root") path "Racket checkout root (default: current directory)"
                    (set! racket-root-arg path)]
 [("--artifact-dir" "--output-dir") path "Directory for the generated .tgz (default: ./artifacts)"
                                  (set! artifact-dir-arg path)]
 [("--stage-dir") path "Independent staging directory (default: ./.build/racket-to-brew-tgz-stage)"
                  (set! stage-dir-arg path)]
 [("--version") version "Override version derived from racket_version.h"
                (set! version-arg version)]
 [("--formula") path "Formula to update (default: Formula/racket@9.rb next to this script)"
                (set! formula-path-arg path)]
 [("--no-update-formula") "Do not update Formula/racket@9.rb after packaging"
                          (set! update-formula? #f)]
 [("--keep-stage") "Keep the temporary staging directory"
                   (set! keep-stage? #t)]
 #:multi
 [("--package") name "Add an extra package name from pkgs/ or racket/share/pkgs/"
                (set! package-args (append package-args (list name)))]
 #:args ()
 (void))

(define racket-root
  (simplify-path (path->complete-path (or racket-root-arg (current-directory)))))
(assert-directory 'main (build-path racket-root "racket" "src"))
(assert-directory 'main (build-path racket-root "racket" "collects"))

(define version (or version-arg (read-racket-version racket-root)))
(define packages (remove-duplicates (append default-packages package-args) string=?))
(define output-dir
  (simplify-path
   (path->complete-path
    (or artifact-dir-arg (default-artifact-dir)))))
(define stage-root
  (simplify-path
   (path->complete-path
    (or stage-dir-arg (default-stage-dir)))))
(define tgz-path (build-path output-dir f"racket-minimal-{version}-src.tgz"))
(define formula-path
  (simplify-path
   (path->complete-path
    (or formula-path-arg (default-formula-path)))))

(make-directory* output-dir)
(prepare-stage-dir! stage-root)
(println/flush f"Racket root: {(clean-path-string racket-root)}")
(println/flush f"Version: {version}")
(println/flush f"Output: {(clean-path-string tgz-path)}")
(println/flush f"Stage: {(clean-path-string stage-root)}")
(println/flush f"Packages: {(string-join packages " ")}")

(define dist-root (stage-source racket-root stage-root version packages))
(make-tgz dist-root tgz-path)
(define digest (sha256-file tgz-path))
(println/flush f"sha256: {digest}")

(when update-formula?
  (update-formula! formula-path version digest))

(unless keep-stage?
  (delete-directory/files stage-root))
