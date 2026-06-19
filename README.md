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

`racket@9` is keg-only, so it does not replace another `racket` on PATH
automatically. Use `/opt/homebrew/opt/racket@9/bin/racket` directly or add
that directory to PATH when this build should be the active Racket.

## Release Checklist

Before committing `Formula/racket@9.rb`, upload this source artifact:

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
