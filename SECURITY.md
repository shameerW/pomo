# Security

## Reporting a vulnerability

Please report security issues privately through GitHub's
[**Report a vulnerability**](../../security/advisories/new) form on this repository, not in a public issue.
You'll get a reply within a week.

## What Pomo does and doesn't do

- **No accounts, analytics or telemetry.** There are no servers. Settings and history stay in your macOS user defaults.
- **Network:** YouTube only, and only while music or break talks are on. With an API key set, it also uses
  Google's YouTube Data API. All traffic is HTTPS.
- **Secrets:** the optional YouTube API key is stored in your login Keychain, never in preferences or files.
- **Embedded player:**
  - YouTube runs in a web view with a non-persistent data store, so no cookies are kept between launches.
  - The view can load only the player page and YouTube's own domains.
  - Links clicked inside it open in your default browser.
  - Video ids are validated before they reach the page.
- **`pomo://` URL scheme:** any app or web page can open these links (macOS asks before a browser opens one).
  - The commands only control the timer: start, pause, skip, reset, extend, show/hide.
  - Text input is stripped of control characters and capped at 140 characters.
  - Numbers are clamped.
  - Nothing reads or writes files, runs commands or exposes data.
- **Build:** no third-party code. `build.sh` compiles with `swiftc` and signs ad hoc, or with your own local
  identity if you configure one in the git-ignored `signing/env`.
