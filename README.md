# Vyspec Homebrew Tap

Install the Vyspec CLI on macOS:

```bash
brew install ramonzubiate/tap/vyspec
vsy install-browser
```

Verify the installation:

```bash
vsy --version
vsy doctor
```

Homebrew will update Vyspec with the rest of your installed formulae. To update it directly:

```bash
brew upgrade ramonzubiate/tap/vyspec
```

For a `Brewfile`:

```ruby
tap "ramonzubiate/tap"
brew "vyspec"
```

## Documentation

Visit [vyspec.com](https://vyspec.com) or run `vsy --help`.
