# CutieDeng Racket Homebrew Tap

This tap packages private Racket builds maintained from
`https://github.com/CutieDeng/racket`.

## How do I install these formulae?

Install the private Racket 9 build directly:

```sh
brew install cutiedeng/racket/racket@9
```

Or tap first:

```sh
brew tap cutiedeng/racket
brew install racket@9
```

Or, in a `brew bundle` `Brewfile`:

```ruby
tap "cutiedeng/racket"
brew "racket@9"
```

`racket@9` is intended to provide the active Homebrew `racket` and `raco`
commands. If an official Racket formula or cask is already installed, remove it
before installing this formula:

```sh
brew uninstall minimal-racket
brew uninstall --cask racket
```

If only a linked formula is in the way, unlinking it is also enough:

```sh
brew unlink minimal-racket
```

## Release Checklist

Generate the source artifact and Formula from the packaging project:

```sh
racket package-racket.rkt \
  --target brew \
  --racket-root /path/to/racket.git \
  --homebrew-tap /opt/homebrew/Library/Taps/cutiedeng/homebrew-racket \
  --bottle-root-url https://github.com/CutieDeng/homebrew-racket/releases/download/v9.2.1
```

The command writes `artifacts/racket-minimal-9.2.1-src.tgz` in the packaging
project and replaces `Formula/racket@9.rb` in this tap after validation. Before
validating the formula, upload the generated source artifact:

```text
https://github.com/CutieDeng/racket/releases/download/v9.2.1/racket-minimal-9.2.1-src.tgz
```

Then verify that the formula `sha256` matches:

```sh
curl -L https://github.com/CutieDeng/racket/releases/download/v9.2.1/racket-minimal-9.2.1-src.tgz | shasum -a 256
```

Local validation:

```sh
brew audit --strict --formula cutiedeng/racket/racket@9
brew install --build-from-source --verbose cutiedeng/racket/racket@9
brew test cutiedeng/racket/racket@9
```

## Documentation

`brew help`, `man brew` or check [Homebrew's documentation](https://docs.brew.sh).
