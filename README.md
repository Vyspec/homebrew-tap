# Vyspec Homebrew Tap

Install the Vyspec CLI on macOS:

```bash
brew install vyspec/tap/vyspec
vsy install-browser
```

Verify the installation:

```bash
vsy --version
vsy --help
```

Homebrew will update Vyspec with the rest of your installed formulae. To update it directly:

```bash
brew upgrade vyspec/tap/vyspec
```

New PyPI releases are detected, rebuilt, and verified automatically before this tap is updated.

For a `Brewfile`:

```ruby
tap "vyspec/tap"
brew "vyspec"
```

## Documentation

Visit [vyspec.com](https://vyspec.com) or run `vsy --help`.
