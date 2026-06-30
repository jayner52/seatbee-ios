# Seatbee Metrics Widget — setup & ship checklist

A home-screen widget showing **Revenue today · MRR · ARR · Active subs · New subs today · New users today**, RevenueCat-style. Admin-only.

> ⚠️ Open Xcode from the **correct clone**: `~/Documents/Shayan's Cowork/Seatbee/seatbee-ios`. (The `Vibes/Seatbee Mobile` copy is stale and caused an App Store rejection before.)

## How it works (architecture)

```
App (signed in as admin) ──POST /api/admin?resource=widget-token──▶ backend mints
   │                                                                  HMAC-signed,
   │  stores token in shared keychain (group: com.shayan.seatbee.shared)   90-day,
   ▼                                                                  read-only token
Widget ──GET /api/admin?resource=widget-metrics (X-Widget-Token)──▶ { 6 numbers }
```

The widget never holds the Supabase session — Supabase rotates refresh tokens, so sharing one would log the app out. It carries a narrow minted token instead. Revoke everything by rotating `WIDGET_TOKEN_SECRET` in Vercel.

## Files already in the repo (this branch: `shayan/admin-widget`)

| File | Target membership |
|---|---|
| `Shared/WidgetSharedAuth.swift` | **App + Widget** (both) |
| `SeatbeeWidget/WidgetMetrics.swift` | Widget |
| `SeatbeeWidget/MetricsService.swift` | Widget |
| `SeatbeeWidget/MetricsWidget.swift` | Widget |
| `SeatbeeWidget/MetricsWidgetView.swift` | Widget |
| `SeatbeeWidget/SeatbeeWidgetBundle.swift` | Widget (`@main`) |
| `SeatbeeWidget/Info.plist` | Widget |
| `SeatbeeWidget/SeatbeeWidget.entitlements` | Widget |
| `seatbee/Services/WidgetTokenProvider.swift` | App |
| `seatbee/seatbee.entitlements` | App (edited — added keychain group) |
| `seatbee/Services/AuthService.swift` | App (edited — `currentUser` didSet) |

## Xcode steps (~10 min)

1. **Create the target.** File → New → Target → **Widget Extension**. Product name `SeatbeeWidget`. **Uncheck** "Include Configuration App Intent" (we use `StaticConfiguration`). Team `L67AL7FS38`. Embed in the `seatbee` app. Activate the scheme when prompted.
2. **Delete the generated stubs** Xcode created inside the new `SeatbeeWidget` group (the template `SeatbeeWidget.swift` and `SeatbeeWidgetBundle.swift`). Keep its generated `Assets.xcassets`.
3. **Add my files to the target.** In Finder the files already exist under `SeatbeeWidget/` and `Shared/`. Add them to the project (drag in, or "Add Files…"), and set **Target Membership** in the File Inspector:
   - All `SeatbeeWidget/*.swift` → **SeatbeeWidget** only.
   - `Shared/WidgetSharedAuth.swift` → **both** seatbee **and** SeatbeeWidget.
   - `seatbee/Services/WidgetTokenProvider.swift` → **seatbee** only.
4. **Widget Info.plist + entitlements.** SeatbeeWidget target → Build Settings → set *Info.plist File* to `SeatbeeWidget/Info.plist` and *Code Signing Entitlements* to `SeatbeeWidget/SeatbeeWidget.entitlements` (or just add the **Keychain Sharing** capability with group `com.shayan.seatbee.shared`).
5. **Keychain Sharing on the app target.** seatbee target → Signing & Capabilities → **+ Capability → Keychain Sharing** → add group `com.shayan.seatbee.shared`. (The entitlements file already lists it; this makes the provisioning profile include it.)
6. **Same team on both targets** (`L67AL7FS38`) with Automatic signing, so `$(AppIdentifierPrefix)` resolves identically.
7. **⌘B** to build. SourceKit "cannot find type" errors disappear once the files are in the targets.

> If the widget shows "Sign in as admin" even when you're signed in, the keychain group prefix is the thing to check: `WidgetSharedAuth.swift` hardcodes `L67AL7FS38.com.shayan.seatbee.shared`. Confirm your **App ID Prefix** equals `L67AL7FS38` (Apple Developer → Identifiers); if not, update that constant.

## Backend prerequisite (one-time)

Set **`WIDGET_TOKEN_SECRET`** in Vercel (Project → Settings → Environment Variables, Production) to a long random string, then redeploy. Without it, token minting returns 500 and the widget stays signed-out. The metrics endpoint itself is already live.

## Ship it

1. Run on a real device, **sign in as an admin** (email in `ADMIN_EMAILS`). The app mints + stores the token automatically.
2. Long-press home screen → **+** → search "Seatbee" → add the widget. Pick small / medium / large.
3. For it to live on your phone for real: **Product → Archive → distribute to TestFlight** (per the team PR workflow, open a PR for this branch first).

## Notes
- Refresh cadence ~30 min (WidgetKit budgets ~40–70/day). Not real-time by design.
- On fetch failure the widget shows the last successful values with an "offline" badge.
- Numbers are computed server-side from the same queries as the daily digest email, so widget and inbox always agree.
