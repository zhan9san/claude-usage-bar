# Claude Usage Bar - Product Requirements

| Field    | Value                       |
| -------- | --------------------------- |
| Status   | Draft v0.1                  |
| Date     | 2026-11-11                  |
| Platform | macOS 14+ menu bar app      |
| Auth     | `claude setup-token` token  |

## 1. Summary

Claude Usage Bar is a small native macOS menu bar app that shows the current
Claude subscription usage: the 5-hour session window and the 7-day weekly
window. It authenticates with a long-lived Claude Code OAuth token created by
`claude setup-token`, the same token used in `CLAUDE_CODE_OAUTH_TOKEN`.

## 2. Problem

- Claude Code authenticated through `CLAUDE_CODE_OAUTH_TOKEN` gives no
  glanceable view of how much of the 5-hour and weekly limits is used.
- Existing trackers expect a claude.ai session cookie or a Claude Code
  Keychain login, ship many unrelated features, and read the user's Claude
  Code credentials.
- `setup-token` tokens only carry the `user:inference` scope, so the
  per-model usage endpoint (`/api/oauth/usage`) rejects them with
  `403 oauth_scope_insufficient`. Only the totals are reachable, and totals
  are all this app needs.

## 3. Goals

- G1: Show 5-hour and 7-day utilization in the menu bar at a glance.
- G2: Show reset times and limit status in a popover.
- G3: Work with a `setup-token` token only: no cookies, no browser login,
  no token refresh.
- G4: Keep the token in the macOS Keychain; never write it to plain-text
  files or logs.
- G5: Stay small: one process, no third-party dependencies, builds with the
  Command Line Tools only.

## 4. Non-goals

- Per-model (Opus, Sonnet, Fable) breakdown.
- Console API billing or spend tracking.
- Multiple accounts or profiles.
- Token refresh, browser login, or claude.ai cookie handling.
- App Store distribution or notarization.

## 5. Data source

Usage is read from the unified rate-limit headers that the Messages API
returns on every response.

One request per refresh:

- `POST https://api.anthropic.com/v1/messages`
- Headers: `Authorization: Bearer <token>`,
  `anthropic-beta: oauth-2025-04-20`, `anthropic-version: 2023-06-01`,
  `content-type: application/json`
- Body: `{"model":"claude-haiku-4-5-20251001","max_tokens":1,
  "messages":[{"role":"user","content":"hi"}]}`

Response headers used:

| Header                                             | Meaning                                    |
| -------------------------------------------------- | ------------------------------------------ |
| `anthropic-ratelimit-unified-5h-utilization`       | Session window usage, 0.0 to 1.0           |
| `anthropic-ratelimit-unified-5h-reset`             | Session reset time, Unix seconds           |
| `anthropic-ratelimit-unified-7d-utilization`       | Weekly window usage, 0.0 to 1.0            |
| `anthropic-ratelimit-unified-7d-reset`             | Weekly reset time, Unix seconds            |
| `anthropic-ratelimit-unified-status`               | `allowed`, `allowed_warning` or `rejected` |
| `anthropic-ratelimit-unified-representative-claim` | Window that is currently binding           |

Observed on 2026-11-11 with a `setup-token` token:

- Haiku requests return `200` with all headers above.
- Sonnet, Opus and Fable requests return a bare `429 rate_limit_error`
  without usage headers, so the probe model must be a Haiku model.
- A `429` caused by the real limit still carries the usage headers.

## 6. Functional requirements

### 6.1 Menu bar label

- FR-1: Show a gauge icon followed by usage text. Label styles:
  Full `5h 4% · 7d 24%` (default), Compact `4% · 24%`, Session only `4%`.
- FR-2: The gauge icon reflects the higher of the two utilizations:
  below 50%, 50% to 79%, and 80% or more.
- FR-3: Show `—` before the first successful fetch, and a warning icon with
  `Set token` when no token is configured.

### 6.2 Popover

- FR-4: One row per window (Session 5h, Weekly 7d) with a progress bar,
  percentage, relative reset ("Resets in 2h 14m") and absolute reset time.
- FR-5: Show the limit status as a badge when it is not `allowed`.
- FR-6: Show "Updated N min ago" and the last error, if any, while keeping
  the last good values on screen.
- FR-7: Buttons: Refresh, Settings, Quit.

### 6.3 Refresh

- FR-8: Fetch on launch, then every refresh interval: 1, 5 (default), 10,
  15 or 30 minutes.
- FR-9: Fetch again after wake from sleep and whenever the token, probe
  model or refresh interval changes.
- FR-10: When fetches overlap, only the newest result is applied; stale
  responses are discarded.
- FR-11: A window whose reset time has passed is shown as 0% until the next
  fetch. Countdowns and the label update every minute without a fetch.

### 6.4 Settings (inside the popover)

- FR-12: Token: secure field with Save and Remove. Whitespace is trimmed and
  the token must start with `sk-ant-oat`.
- FR-13: Token source order: Keychain, then the `CLAUDE_CODE_OAUTH_TOKEN`
  environment variable (only present when the app is launched from a
  shell). The popover shows which source is in use.
- FR-14: Probe model text field, default `claude-haiku-4-5-20251001`.
- FR-15: Refresh interval and label style pickers.
- FR-16: Launch at login toggle backed by `SMAppService`.

### 6.5 Error states

| Condition                       | Message shown                                                 |
| ------------------------------- | ------------------------------------------------------------- |
| No token                        | Add your setup-token in Settings                              |
| `401` or `403`                  | Token rejected; create a new one with `claude setup-token`    |
| `400` or `404`                  | Request rejected; check the probe model in Settings           |
| `429` without usage headers     | Rejected without usage data; use a Haiku probe model          |
| Success without usage headers   | The response had no usage headers                             |
| `5xx`                           | Server error with status code                                 |
| Network failure                 | System error description                                      |

## 7. Non-functional requirements

- NFR-1 Security: the token is stored only in the login Keychain as a
  generic password, is never logged or written to files, and is sent only to
  `api.anthropic.com`.
- NFR-2 Privacy: no analytics and no other network calls.
- NFR-3 Cost: one 1-token Haiku request per refresh, which is 288 requests a
  day at the 5-minute default.
- NFR-4 Footprint: no Dock icon (`LSUIElement`), idle CPU near 0%, memory
  under 50 MB.
- NFR-5 Build: Swift Package Manager with the Command Line Tools; no Xcode
  project and no third-party packages; a script builds an ad-hoc signed
  `.app`.
- NFR-6 Compatibility: macOS 14 or later on Apple silicon.
- NFR-7 Testability: header parsing, response handling, request building,
  token validation and time formatting are covered by unit tests.
- NFR-8 Distribution: each `v*.*.*` tag publishes a zip and SHA-256 checksum
  to GitHub Releases and updates the `claude-usage-bar` cask in the
  `zhan9san/tap` Homebrew tap. Pull requests install the cask from the
  freshly built zip to prove it works before release. The README documents
  Homebrew, manual and source installs, including `brew trust` and the
  quarantine command.

## 8. Risks

| Risk                                                         | Mitigation                                                        |
| ------------------------------------------------------------ | ----------------------------------------------------------------- |
| Headers are undocumented and may change                      | Parsing is in one tested module; clear "no usage headers" error   |
| The probe model is retired                                   | Probe model is configurable                                       |
| Each probe counts as usage and likely starts a new 5h window | Documented; longer intervals reduce it                            |
| Ad-hoc signature changes on every rebuild                    | Keychain asks once per rebuild; choose "Always Allow"             |
| `setup-token` tokens expire after about a year               | `401` message tells the user to create a new token                |
| The app is not notarized, so Gatekeeper blocks it            | Cask clears the quarantine flag; release notes give the command   |
| Homebrew refuses casks from untrusted third-party taps       | Install by full name to trust the cask; README shows `brew trust` |

## 9. Acceptance criteria

- AC-1: With a valid token, the label shows the same 5h and 7d percentages
  as a manual `curl` that reads the same headers.
- AC-2: Removing the token shows the `Set token` state; saving it again
  restores data without restarting the app.
- AC-3: With the network off, the last values stay visible with a network
  error; data recovers on the next refresh after the network returns.
- AC-4: The launch at login setting survives logging out and back in.
- AC-5: `scripts/test.sh` passes and `scripts/build-app.sh` produces a
  runnable `.app`.

## 10. Future

- Threshold notifications, for example at 80% and 95%.
- An "Import from shell" button for `CLAUDE_CODE_OAUTH_TOKEN`.
- A usage history sparkline.
- Optional per-model breakdown when a full-scope token is available.
