# Claude Usage Bar

A small macOS menu bar app that shows your Claude subscription usage: the
5-hour session window and the 7-day weekly window, for example
`5h 4% · 7d 24%`. It works with the long-lived token from
`claude setup-token`, so it needs no browser login or cookies.

Requires macOS 14 or later on Apple silicon.

## Install

### Homebrew

```sh
brew install --cask zhan9san/tap/claude-usage-bar
```

Homebrew only loads casks from third-party taps that you trust. Installing
by the full name above trusts this cask for you. If you tapped first and
installed by the short name, Homebrew stops with:

```text
Error: Refusing to load cask zhan9san/tap/claude-usage-bar from untrusted tap zhan9san/tap.
```

Trust the cask, then install again:

```sh
brew trust --cask zhan9san/tap/claude-usage-bar
brew install --cask claude-usage-bar
```

The cask also clears the Gatekeeper quarantine flag, so the app opens
without a warning.

### Manual

1. Download `ClaudeUsageBar-vX.Y.Z.zip` from
   [Releases](https://github.com/zhan9san/claude-usage-bar/releases), unzip
   it and move `Claude Usage Bar.app` to `/Applications`.
2. The app is ad-hoc signed and not notarized, so macOS blocks it until you
   clear the quarantine flag:

   ```sh
   xattr -dr com.apple.quarantine "/Applications/Claude Usage Bar.app"
   ```

### From source

Needs only the Command Line Tools. This builds the app, copies it to
`~/Applications` and launches it:

```sh
scripts/build-app.sh --install
```

## Set up

1. Create a token with `claude setup-token` and copy it (`sk-ant-oat…`).
2. Click the gauge in the menu bar, open Settings, paste the token and click
   Save.
3. When macOS asks for Keychain access, choose Always Allow. It asks again
   after each upgrade because the ad-hoc signature changes.

Settings also has the refresh interval, label style, probe model and launch
at login.

## Good to know

- Each refresh sends one 1-token request to a Haiku model and reads the
  usage from the response headers. That request counts as usage and can
  start a new 5-hour window; pick a longer interval to reduce it.
- The probe model must be a Haiku model. Other models are rejected without
  usage data for `setup-token` tokens.
- Tokens expire after about a year. When the app says the token was
  rejected, create a new one with `claude setup-token`.
- The token is stored only in the login Keychain and is sent only to
  `api.anthropic.com`.

## Update and uninstall

```sh
brew upgrade --cask claude-usage-bar
brew uninstall --cask --zap claude-usage-bar
```

Uninstalling leaves the token in the Keychain. Click Remove in Settings
first, or delete it afterwards:

```sh
security delete-generic-password -s io.github.zhan9san.claude-usage-bar
```

## Development

```sh
scripts/test.sh
scripts/build-app.sh
```

Requirements and design notes are in [docs/PRD.md](docs/PRD.md).
