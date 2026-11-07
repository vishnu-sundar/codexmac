# CodexMac

A small floating usage monitor for macOS 14 Sonoma and later. A glass capsule shows your five-hour and weekly Codex allowances, how much remains, and the next reported session reset. Click it for separate progress bars and reset times. Drag the waveform at the left to move the bar between displays.

[Download the latest DMG](https://github.com/vishnu-sundar/codexmac/releases/latest/download/CodexMac.dmg) · [Release assets and screenshots](https://github.com/vishnu-sundar/codexmac/releases) · [Builds and test logs](https://github.com/vishnu-sundar/codexmac/actions/workflows/macos.yml)

## Install

1. Download **CodexMac.dmg** from a published release. Open it, drag **CodexMac.app** to **Applications**, eject the disk image, and open the installed app. If desired, compare the DMG's SHA-256 with the release's SHA256SUMS.txt using `shasum -a 256 CodexMac.dmg`.
2. Install the official [Codex CLI](https://developers.openai.com/codex/cli/), run `codex login` in Terminal, and choose **Sign in with ChatGPT**. The app delegates authentication to that CLI. CodexMac has no password, API-key, or browser-cookie input.
3. Click the menu bar percentages and choose **Refresh**. If CodexMac cannot find the CLI, run `command -v codex` in Terminal, then select that executable under **Settings → Codex CLI**. Finder-launched apps do not inherit all shell configuration. With a custom CODEX_HOME, ensure the app's launch environment points to the same Codex home.
4. For desktop widgets, open **Edit Widgets** on the desktop, search for **CodexMac** and add a small, medium, or large widget. Leave the menu bar app running to collect new readings.

CI produces universal arm64/x86_64 binaries. The public build is ad-hoc signed. macOS may require **System Settings → Privacy & Security → Open Anyway** after the first launch attempt. Only approve a copy you trust. The release has no Developer ID notarization. Managed Macs may require an administrator-approved build.

## Floating bar and menu

The waveform is the drag handle. Position is stored relative to each display's visible area; disconnecting a display brings the bar back onto an available screen. Select an anchor or restore the selected position in Settings. Auto-hide leaves a small handle you can hover to reveal. Choose Aurora, Ember, or Frost, adjust glass opacity, and toggle always-on-top.

The menu bar opens the dashboard and settings. The compact countdown uses the five-hour reset when present, then the weekly reset. The expanded view shows both. A solid dot means live, a clock badge means cached, and a question mark means unavailable. Hover for the label. A hollow circle in the menu bar indicates cached data.

## Available reset credits

Click the floating bar and select **Resets**, or open the menu bar dashboard and look under **Usage limit resets**. The count comes from the CLI's `rateLimitResetCredits.availableCount`. CodexMac lists available credits in expiry order and shows their reported titles, descriptions and local expiration times. Some CLI versions or accounts supply only the count or omit reset credits entirely. The displayed count and details share the dashboard's Live or Cached status. Use the Codex web usage dashboard for redemption and account history.

## Data and privacy

CodexMac launches a short-lived **codex app-server** process over standard input/output. It completes the initialization handshake, calls **account/read**, and requests **account/rateLimits/read**. It does not start a thread, submit a prompt, read session logs, or consume reset credits. This protocol and its JSON fields are described in [OpenAI's Codex app-server reference](https://developers.openai.com/codex/app-server#rate-limits-chatgpt). CLI versions and account plans can expose different buckets.

The parser prefers the Codex bucket, accepts the legacy default bucket, and matches explicit durations of 300 and 10,080 minutes, regardless of primary/secondary order. Remaining is 100 minus the reported used percentage. Unknown windows and absent fields show a dash. Wall-clock countdown expiry shows **Due** until another successful read supplies a new reset.

| Status | Meaning |
| --- | --- |
| Live | The last read succeeded and is within the configured refresh interval. |
| Cached | The last successful snapshot is older, or the latest read failed. The dashboard shows its timestamp. |
| Unavailable | No matching limits are available. The dashboard explains missing sign-in, CLI, or window data. |

The app refreshes every 15 minutes by default, with 5, 30 and 60 minute alternatives. It also checks on launch, wake, and manual refresh. App and extension share an atomically replaced, local JSON snapshot. It contains quota windows, timestamps, and a one-way account fingerprint for comparing alerts. A detected sign-out or different account invalidates the previous reading. Widgets display that snapshot on a WidgetKit-managed timeline. Actual widget reload timing is controlled by macOS.

Optional alerts compare two successful readings from the same account. Dropping below 25% or 10%, or reaching 0%, triggers the most urgent enabled alert crossed in that observation. A reset alert requires a later reset timestamp, the old reset time to have passed, and improved remaining capacity. The clock alone never triggers it. If macOS denies alerts, allow CodexMac in Notification Settings.

## Build and test

Requires Xcode 16 or later, Xcode command line tools and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
swift test
xcodegen generate
open CodexMac.xcodeproj
# Or build, capture native PNGs, and create and verify the DMG:
bash Scripts/package.sh
```

The macOS workflow runs the Swift tests and builds both architectures, checks the embedded widget, verifies the signatures, renders the actual app views on the runner, and mounts and validates the DMG. The screenshots depict a fresh installation without a signed-in account. They contain no simulated account balances. Tagged builds publish versioned GitHub Releases. A maintainer can also publish the version in VERSION with a successful main-branch commit carrying the release marker used in the workflow.

**Widget storage:** The app runs outside App Sandbox to launch the user's selected CLI. It writes one snapshot in a private directory under `~/Library/Application Support/CodexMac/Usage/`. The WidgetKit extension runs in App Sandbox with a home-relative read exception for the exact snapshot file. It cannot change the snapshot or read Codex credentials using that entitlement. This direct-download setup works independently of Apple Developer app-group provisioning. For Developer ID distribution, sign and notarize with your own Apple team.

**Source layout:** Core contains the quota parser, cache, freshness and alert rules. App contains the bounded CLI transport, observable monitor, AppKit panel, dashboard and preferences. Widgets contains the read-only WidgetKit extension. Tests covers parsing, missing windows, cache freshness, threshold crossings and confirmed resets.
