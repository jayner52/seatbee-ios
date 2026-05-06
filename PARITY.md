# Cross-App Parity — Seatbee Web ↔ Seatbee iOS

**Read this file before making any change to data that persists to Supabase.**

This rule applies equally to **Jayne's Claude** (working from `~/Desktop/Seating Plan App` or `~/Desktop/seatbee-ios`) and **Shayan's Claude** (working from his clones of the same two repos). Identical content lives in both repos as `PARITY.md` at the root.

Last major update: **2026-05-03** — the day we built the proper round-trip-safe architecture.

---

## Why this exists

The Seatbee web app and the Seatbee iOS app share the same Supabase backend (`puckyaxybgxipoqdrekt`). The entire plan state — guests, tables, rules, room objects, parties, groups, categories — is persisted to a JSONB `data` column on the `seating_plans` table. Both apps read and write that same shape.

When the two apps disagree on the shape — a different enum value, a missing field, a renamed property — opening a plan on one app and saving it can silently corrupt the data when the other app reads it back.

### The 2026-05-03 incident

**Day-of summary.** Jayne opened a plan in the iOS simulator that had been authored on web. After interacting with the canvas (moving a table), the iOS app auto-saved. On next web load: every rule showed as "Unknown rule," every party showed as empty, the web app crashed on the rules page entirely.

**Two underlying bugs were involved:**

1. **`SeatingRule.RuleType` enum mismatch.** iOS had 4 camelCase values (`seatTogether`, `keepApart`, `assignTable`, `seatNear`); web's evaluator expected 10 snake_case values (`must_together`, `prefer_together`, `must_not`, `must_table`, `near_table`, `near_object`, `category_together`, `vip_priority`, `side_together`, `seat_adjacent`). Zero overlap. iOS used a silent `?? .seatTogether` fallback on read, so any rule whose type iOS didn't recognize was coerced to `seatTogether` and re-saved with that string.

2. **`PartyDTO` field name mismatch.** Web stores parties with field `guestIds: [String]`. iOS's `PartyDTO` defined the field as `members: [String]?`. **Same concept, different name.** When iOS decoded a web party with `{id, name, guestIds, priority, color}`, Swift Codable looked for `members`, found none, and silently set every party's iOS-side `members` to nil. On save, iOS wrote `{id, name}` — no member list at all. Web's renderer then crashed trying to call `.forEach` on `undefined`.

**The deeper architectural lesson.** Multiple iOS DTOs were *partial decoders* — they only knew about a subset of the fields the web app persists. When iOS read JSONB into one of these partial DTOs, every field the DTO didn't know about was silently dropped during decode. Then when iOS saved, only the known fields made it back. Result: every iOS save was a lossy compression.

**What the resolution looks like.** Each iOS DTO now mirrors the full web shape, even fields iOS doesn't display. Domain models (`Guest`, `SeatTable`, `RoomObject`, `SeatingPlan`) gained matching passthrough fields with `= nil` defaults. The DTO read populates them; the DTO write reads them back. iOS now *preserves* every web field on round-trip, regardless of whether iOS UI renders it.

User data in production was never at risk — RLS scopes iOS to the authenticated dev's own plans, and the iOS app isn't on the App Store — but the round-trip safety story now extends past the dev sandbox: any future user who eventually runs iOS will have the same lossless round-trip.

---

## How iOS↔Web round-trip works (architecture, post-fix)

### Shared backend

- One Supabase project: `puckyaxybgxipoqdrekt`
- Plan data lives in `seating_plans.data` (JSONB column)
- Both apps authenticate via Supabase auth (web uses `@supabase/supabase-js`, iOS uses Supabase Swift SDK directly)
- RLS on `seating_plans` (set up via earlier migrations and migration 033 for collab) scopes each authenticated user to plans where `user_id = auth.uid()` or where they are an explicit collaborator
- iOS isn't on the App Store yet — only Jayne and Shayan can run it via Xcode simulator
- Web is in production at `seatbee.app`

### Plan data shape (top-level keys in JSONB)

`event`, `guests`, `tables`, `rules`, `objects`, `categories`, `assignments`, `parties`, `groups`, `floorPlanImage`, `floorPlanOpacity`. Plus optional `genResults` (recomputable, intentionally not preserved).

Each entity has a defined schema — see "Field reference" below.

### iOS round-trip flow (post-fix)

1. **Read.** `DatabaseService.fetchPlans` queries Supabase → array of `SeatingPlanDTO` → `toDomain()` builds a `SeatingPlan`. The DTO struct includes every field the web persists. Fields iOS doesn't model in its domain layer (categories, parties, groups, floorPlanImage) are stored as raw arrays on `SeatingPlan` (`rawCategories`, `rawParties`, `rawGroups`, `rawFloorPlanImage`, `rawFloorPlanOpacity`).
2. **Edit in memory.** User moves a table, edits a rule, adds a guest — domain mutations. The raw passthrough arrays are never modified during normal iOS use, so they survive untouched.
3. **Write.** `SeatingPlan.toPlanData()` serializes the full domain model into a `PlanDataDTO`. Modeled fields come from the domain object; unmodeled fields come from the raw arrays. `DatabaseService.savePlanData` writes this back to Supabase.
4. **Web reads.** Existing rendering works because every field is still present.

### Defensive layers (belt + suspenders)

Even after the proper fix, three defensive mechanisms remain in place to make future drift detectable and survivable:

- **iOS `RuleType.parse()`** — preserves unknown rule type strings via `.unknown(raw)` instead of silent coercion. Logs a warning. Round-trip preserves the raw string unchanged.
- **Web `console.warn` on unknown rule type** — `src/App.jsx:5036`-area logs the offending `r.type` so the next drift incident is diagnosable in seconds.
- **Web defensive normalizers** — `src/App.jsx` (3 state-ingress points: localStorage hydration, `loadPlanDirect`, cloud-sync `setRaw`) coalesce missing array fields to `[]` and translate `party.members` → `party.guestIds` if any older legacy data slips through. UnitCard rendering also coalesces locally as final-mile protection.

These layers exist not because the proper fix is incomplete, but because the proper fix can only protect the data going forward. Any plan still in a degraded state (e.g., from earlier iOS saves) needs the web defensive layer to render without crashing.

---

## The Cardinal Rule

**Every shared data shape must be identical across web and iOS.**

- Same field names
- Same types
- Same enum values (case-sensitive string match)
- Same semantics (a `boolean` and a `String?` are NOT the same field even if they happen to be truthy in the same cases)
- Same nullability

If you touch a shared field on one side, **mirror the change on the other side in the same PR cycle**, or coordinate an explicit follow-up via Telegram with the other developer.

---

## What counts as "shared"

A field is shared if it is persisted to Supabase `seating_plans.data` (JSONB). Specifically, the entities below are shared:

| Entity | Web location | iOS location |
|---|---|---|
| Plan-level metadata | `state.event`, `state.tier`, `state.event_pass_expires_at`, `state.event_pass_purchased_at`, etc. | `Models/SeatingPlan.swift` (root) |
| Guest | `state.guests[]` | `Models/SeatingPlan.swift` `Guest` struct |
| SeatTable | `state.tables[]` | `Models/SeatingPlan.swift` `SeatTable` struct |
| SeatingRule | `state.rules[]` | `Models/SeatingPlan.swift` `SeatingRule` struct |
| RoomObject (venue object) | `state.objects[]` | `Models/SeatingPlan.swift` `RoomObject` struct |
| Category | `state.categories[]` | `Models/DTOs/SeatingPlanDTO.swift` `CategoryDTO` (no domain model — preserved via `SeatingPlan.rawCategories`) |
| Party | `state.parties[]` | `Models/DTOs/SeatingPlanDTO.swift` `PartyDTO` (no domain model — preserved via `SeatingPlan.rawParties`) |
| Group | `state.groups[]` | `Models/DTOs/SeatingPlanDTO.swift` `GroupDTO` (no domain model — preserved via `SeatingPlan.rawGroups`) |

Internal-only fields (UI state, ephemeral selection, drag offsets, panel toggles) are NOT shared. If it never round-trips to Supabase, it's safe to differ.

---

## Field reference (canonical schema)

These are the field shapes each entity must use on **both sides**. iOS DTOs and web `state.*` shapes both conform to this.

### `event` (EventData)

`name`, `date`, `venue`, `eventType`, `roomWidth`, `roomHeight`, `roomShape`, `coupleType` (wedding-only: `bride_groom` | `bride_bride` | `groom_groom`; derived from per-partner role markers in onboarding)

### Plan-level pass columns (top-level on `seating_plans` row, not in `data`)

`tier` (string: `free` | `event_pass` | `signature_pass` | `pro_pass`), `event_pass_expires_at` (ISO timestamp), `event_pass_purchased_at` (ISO timestamp).

These are set by the web's `/api/passes` redemption endpoint when a user applies a pass to a plan. iOS reads them on plan load and uses them to enforce tier limits + detect expiry. **iOS never writes these columns** — Supabase PATCH semantics preserve untouched columns, so the existing values are safe across iOS saves.

### Guest

Core: `id`, `name`, `firstName`, `lastName`, `email`, `categories` (array of category-IDs), `dietary` (free text), `notes`, `rsvp` (`yes`/`no`/`pending`/`unknown`), `side` (`bride`/`groom`/`both`/`none`), `vip`, `accessibility`, `plusOne`, `party` (party ID/name string), `display`

Web-parity (preserved on iOS round-trip): `dietaryTags` (array of strings — drives per-restriction emoji on web), `highChair` (boolean), `groupIds` (array), `isBride` (boolean, cached), `isGroom` (boolean, cached), `meal` (string), `createdAt` (ISO timestamp)

### SeatTable

Core: `id`, `name`, `type` (`round`/`rect`/`head`/`sweetheart`/`oval`), `seats`, `x`, `y`, `rotation`, `assignments` (handled separately, see below), `locked`, `color`

Web-parity (preserved on iOS round-trip): `width`, `height` (rect/head/oval), `diameter` (round), `sweetShape` (`HEART`/`OVAL`/`DIAMOND` for sweetheart variants), `oneSide` (boolean for head table), `notes` (free-text per-table notes — kitchen, vendor, internal)

### SeatingRule

Core: `id`, `type`, `guests` (array of guest IDs), `tableId`, `weight`, `hard`, `enabled`

Web-parity (preserved on iOS round-trip): `categoryId`, `objectId`, `sideValue`, `desc`, `auto`, `source`, `partyId`, `groupId`

**`type` enum values (case-sensitive match):**
`must_together`, `prefer_together`, `must_not`, `must_table`, `near_table`, `near_object`, `category_together`, `vip_priority`, `side_together`, `seat_adjacent`

iOS encodes/decodes via the `RuleType` enum which has matching `rawValue` strings. Unknown types preserve the raw string via `.unknown(String)`.

### RoomObject (venue object)

Core: `id`, `type`, `name`, `x`, `y`, `width`, `height`, `rotation`

Web-parity (preserved on iOS round-trip): `color`, `category` (e.g. "entertainment"/"food"/"services"), `icon` (icon name), `isObstacle` (boolean)

When `color` is missing on read, web `VObj` derives a fallback from the `VENUE_OBJECTS` definitions table. Don't rely on this at write time — always set the canonical color on save.

### Category

`id`, `name`, `color` (hex), `isSystem` (boolean — true for predefined categories like Wedding Party / Bride / Groom), `affinityWeight` (int 0-100 — drives seating algorithm bias), `seatColor` (hex, optional)

iOS doesn't yet author categories — it preserves the raw array via `SeatingPlan.rawCategories` and writes it back unchanged on save.

### Party

`id`, `name`, **`guestIds`** (array of strings — note: NOT `members`; that field name was the cause of the 2026-05-03 incident), `priority` (int 50-100), `fallbackGroupId` (string, optional), `color` (hex)

iOS doesn't yet author parties as full objects — Guest has a `party: String?` reference. The Party array round-trips via `SeatingPlan.rawParties`.

### Group

`id`, `name`, `members` (array of strings — these can be guest IDs, or party IDs prefixed with `u`), `color`, `priority`, `fallbackGroupId`

Note: Groups use `members`, parties use `guestIds`. They are different concepts. Don't conflate.

iOS doesn't model Group at all in the domain layer — preserved via `SeatingPlan.rawGroups`.

### `assignments`

Map of `guestId → { tableId, seatIndex }`. iOS deconstructs this on read (assigning each guest to their table) and reconstructs it on save.

### Plan-level passthrough

`floorPlanImage` (base64 string), `floorPlanOpacity` (number, 0-1) — preserved on iOS via `rawFloorPlanImage` / `rawFloorPlanOpacity`.

`genResults` is intentionally not preserved — it's recomputable from "Generate Seating" and writing stale results is worse than recomputing.

---

## Procedure when changing a shared field

1. **Read this file fully** before editing.
2. **Identify whether your change affects a shared shape.** When in doubt, ask: does this end up in `seating_plans.data`? If yes → shared.
3. **Update both apps in the same PR cycle.** If you can't (the other dev needs to do it), open a tracking issue or send a Telegram heads-up with the field shape and the deadline.
4. **Add defensive logging on read** when reading enum values from the persisted blob:
   - Web: `console.warn('[seatbee] Unknown <thing> type:', value, 'context:', obj)`
   - iOS: `print("[Seatbee] ⚠️ Unknown <thing> type: \(rawValue) — preserving raw")`
5. **Never use silent `?? defaultValue` for unknown enums.** Use an explicit `.unknown(String)` case that preserves the original (see `SeatingRule.RuleType` for the canonical pattern), OR throw, OR log loudly. Never coerce silently.
6. **Verify round-trip locally.** Web edit → save → iOS read → iOS save → web read. The shape should be identical at every hop.
7. **Update this file's "Outstanding gaps" or "Resolved" section** when introducing or resolving drift.

---

## Anti-patterns

- ❌ Silent enum fallback on read (`?? .firstCase`)
- ❌ Adding a new field to one side and "we'll do iOS/web later"
- ❌ Renaming an enum case without updating both repos in lockstep
- ❌ Trusting that fields round-trip just because the build compiles
- ❌ Storing the same concept under different field names on each side (the 2026-05-03 `members` vs `guestIds` mistake)
- ❌ Letting the build pass with TODOs that say "wire up to other app later"
- ❌ Reading old data with a less-permissive shape (e.g. iOS only knows 4 of web's 10 rule types) without explicitly preserving the rest

---

## Resolved gaps

| Date | Gap | Closed by |
|---|---|---|
| 2026-05-03 | `RuleType` enum mismatch (iOS 4 camelCase vs web 10 snake_case) | iOS PR #3 (`jayne/rules-parity`) |
| 2026-05-03 | `RuleDTO` missing fields (`categoryId`, `objectId`, `sideValue`, `desc`, `auto`, `source`, `partyId`, `groupId`) | iOS PR #3 |
| 2026-05-03 | iOS `RuleType` silent `?? .seatTogether` fallback on unknown read | iOS PR #3 (replaced with `.unknown(raw)` preservation) |
| 2026-05-03 | `PartyDTO` field name (`members` → `guestIds`) | iOS PR #4 (`jayne/full-dto-parity`) |
| 2026-05-03 | `PartyDTO` missing fields (`priority`, `fallbackGroupId`, `color`) | iOS PR #4 |
| 2026-05-03 | `CategoryDTO` missing fields (`isSystem`, `affinityWeight`, `seatColor`) | iOS PR #4 |
| 2026-05-03 | `GuestDTO` missing fields (`dietaryTags`, `highChair`, `groupIds`, `isBride`, `isGroom`, `meal`, `createdAt`) | iOS PR #4 |
| 2026-05-03 | `TableDTO` missing fields (`width`, `height`, `diameter`, `sweetShape`, `oneSide`) | iOS PR #4 |
| 2026-05-03 | `ObjectDTO` missing fields (`color`, `category`, `icon`, `isObstacle`) | iOS PR #4 |
| 2026-05-03 | `PlanDataDTO` missing `groups`, `floorPlanImage`, `floorPlanOpacity` | iOS PR #4 |
| 2026-05-03 | iOS `toPlanData` hardcoded `categories: nil`, `parties: nil` (wiped arrays on every save) | iOS PR #4 (now writes from raw passthrough fields) |
| 2026-05-03 | Web rule evaluator silent on unknown types | Web direct-to-main commit `1423fdd` (now `console.warn`s) |
| 2026-05-03 | Venue objects render as black rectangles when `color` field is missing | Web direct-to-main commit `968a70d` (`VObj` falls back to `VENUE_OBJECTS` defaults) |
| 2026-05-03 | Web rendering crashed on missing `parties[].guestIds`, `guests[].dietaryTags`, `guests[].groupIds` | Web direct-to-main commits `9fd3ac4`, `4cbbdb8`, `7c46fa0`, `bc1893b` (defensive normalizers + UnitCard local guard) |
| 2026-05-04 | Web auto-sync overwrote iOS-canonical rule types with legacy `seatTogether` strings (state hydrated from old DB rows pre-iOS-migration; auto-sync wrote them back, fighting iOS) | Web direct-to-main commits `4328234` + `8ffa905` (rule-type translator at all 4 web load paths — initial localStorage hydrate, `loadPlanDirect`, polling reload, AND cloud-boot path that runs on hard-refresh) + iOS PR #5 (legacy→canonical mapping in `RuleType.parse`) |
| 2026-05-04 | iOS canvas rendered every table as a 70×70 hardcoded circle regardless of `type` — rect/head/sweetheart all looked round | iOS PR (`jayne/ios-table-shape-parity`) — `CanvasTableView` switches on `type`, consumes `width`/`height`/`diameter`, renders sweetheart heart/oval/diamond variants, applies `rotation`, fills with `table.color`, lays out seats per shape (round=circular, rect/head=two-side or `oneSide`, sweetheart=2 at bottom) |
| 2026-05-04 | iOS-created tables saved with `nil` dim fields — web rendered them at fallback geometry, not the user's intended size | iOS PR — `AddTableSheet` populates dims via new `TableDefaults` helper mirroring web's `TABLE_SIZES` (5ft round=75px, 6×2.5ft rect, 18×2.5ft head with `oneSide=true`, 4×3ft heart sweetheart). `TableDrawerView.changeTableType()` backfills missing dim fields without overwriting |
| 2026-05-04 | iOS table edit drawer only had a seat stepper + type dropdown; missing web's shape picker, seating layout, size sliders, Make Square, rotation, sweetheart variant picker | iOS PR (`jayne/ios-table-edit-drawer-parity`) — new "Layout" tab in `TableDrawerView` with SHAPE buttons (Round/Rect/Head/Sweet), SWEETHEART STYLE (Heart/Oval/Rect, lowercase to match web's `SWEET_SHAPES`), SEATING LAYOUT (One Side/Two Sides), SIZE sliders (round=diameter 60-200, rect/head/sweet=W 60-2000 + H 30-150) with feet display, Make Square button (rect), and ROTATION slider 0-360 + ±15° wrap-mod-360 buttons. `changeTableType` rewritten to mirror web's onClick handlers (preserves dims across conversions, defaults `head.oneSide=true`). Seat bounds aligned with web (max 12 round / 200 rect+head / 2 sweet) and rect/head auto-expand width on seats++ to keep ≥1.5 ft per person per side |
| 2026-05-04 | iOS seat list collapsed all web-assigned guests at a table onto seat 0 — only the first guest at each table was visible in the iOS drawer | iOS PR (`jayne/ios-assignment-seat-collision`) — `SeatingPlanDTO.toDomain()` no longer falls back to `seatIndex ?? 0`. Web persists `assignments` as flat strings (`{guestId: "tableId"}`, no seat position — see AssignmentDTO/PR #10) which decode to `seatIndex == nil`. Fix splits the unpack into two passes per table: honour explicit `seatIndex` values first, then fill the remaining nil-seatIndex guests into the next free seat in `data.guests` order so iOS list order mirrors web's |
| 2026-05-04 | iOS canvas rendered venue object icons as their literal symbol name (e.g., the word `"star"` instead of the star glyph) | iOS PR (`jayne/ios-venue-object-icons`) — `CanvasObjectView` swapped `iconLabel: UILabel` for `iconView: UIImageView` and now renders the icon via `UIImage(systemName: def.icon)` with template tint. Icon is sourced from the canonical `venueObjectTypes` table (consistent with the per-instance `object.icon` field which is preserved on round-trip but not yet authored on iOS) |
| 2026-05-04 | iOS guest cards showed a generic 🍽 emoji on every guest with `dietary != nil`, regardless of actual dietary content; web shows per-tag emojis from `dietaryTags[]` only | iOS PR (`jayne/ios-guest-card-parity`) — `GuestsView.guestRow` now renders per-tag emojis from `dietaryTags[]` (canonical 8-tag map mirroring web's `DIETARY_TAGS`); falls back to a single 🍽 only when `dietary` free-text is non-empty AND no tags. No emoji at all when neither is set |
| 2026-05-04 | iOS guest list showed raw category IDs (`y0b4xyih6`) for web-authored guests; iOS treated `guest.categories` as opaque strings instead of looking up the canonical name from `rawCategories` | iOS PR — new `categoryName(forId:)` helper deserializes `rawCategories` (`[[String: AnyCodable]]`) and looks up `name` by `id`. Falls back to the raw string when no entry matches |
| 2026-05-04 | iOS guest detail sheet missing `meal`, `dietaryTags`, `isChild`, `highChair` editing — and the `isChild` field wasn't even on the iOS Guest model so it was lost on save | iOS PR — added `isChild: Bool?` to `Guest` struct + `GuestDTO` + `toDomain` + `toPlanData`. Detail sheet now has: MEAL text input, DIETARY & ALLERGIES chip multi-picker (8 canonical tags with emoji+label) + free-text "Other restriction" field, Child / High Chair / VIP / +1 toggles. Categories picker now reads canonical `rawCategories` instead of deriving from existing guest strings |
| 2026-05-04 | iOS guest list missing visual badges for VIP, child, high chair (web shows `VIP` pill, 🧒 emoji, 🪑 emoji on the row) | iOS PR — `GuestsView.guestRow` renders gold "VIP" pill when `vip==true`, 🧒 when `isChild==true`, 🪑 when `highChair==true` |
| 2026-05-04 | iOS CSV import only recognized name/email/side/dietary/rsvp/categories columns; missed meal, party, vip, child, highChair, and didn't infer structured `dietaryTags` from the dietary text | iOS PR — `CSVImportSheet.parseCSVText` adds column matchers for `meal`, `party`, `vip`, `child`, `highChair`, `notes` (mirroring web's `FIELD_SYNONYMS`). Adds `inferDietaryTags(from:)` helper using web's case-insensitive keyword matching (vegan/vegetarian/halal/kosher/gluten/dairy/nut/shellfish) so CSV rows produce structured tags |
| 2026-05-04 | iOS Rules screen was a flat list with only 3 creatable rule types (must_together / must_not / must_table); 7 of the 10 canonical types were read-only on iOS even though the model supported them | iOS PRs `jayne/ios-rules-sections` (display) and `jayne/ios-rules-create-forms` (write) — Rules screen now renders 6 collapsible sections matching web's Rules tab (Seat Together / Keep Apart / Assign to Table / Near Venue / Near Table / Category Rules) plus a Parties section above. Per-section "+" opens a type-specific create form. New iOS-creatable types: `near_table`, `near_object`, `category_together`, `prefer_together`. Each form mirrors web's `createX` field set byte-for-byte (verification table in PR description). Auto-types (`vip_priority`, `side_together`) and `seat_adjacent` (created at onboarding) are intentionally hidden, matching web's Rules tab |
| 2026-05-04 | iOS-created Seat Together rules were invisible on web (web's Seat Together section iterates `state.groups[]`, not rules of type `prefer_together`) | iOS PR — `AddRuleSheet` Seat Together flow now also writes a `rawGroups` entry with the new `groupId` referenced by the rule. Mirrors web's `createSeatTogetherGroup` so iOS-created rules appear in web's Seat Together section |
| 2026-05-04 | iOS had no Parties UI — `rawParties` was preserved on round-trip but never displayed or authored | iOS PR — new Parties section at the top of Rules screen iterates `plan.rawParties` and renders `partyCard` per entry (member names, lock toggle that flips linked rule between `must_together` ↔ `prefer_together` and `hard` true ↔ false matching web's `UnitCard`, delete that removes party + linked rules + clears `guest.party`). New `AddPartySheet` mirrors web's `createParty`: writes `{id, name, guestIds, priority, color}` to `rawParties` + creates a hard `must_together` rule with `partyId` back-ref + sets `guest.party = partyId` for each member |
| 2026-05-04 | iOS dropped web's `sideA` / `sideB` fields on Keep Apart round-trip (iOS RuleDTO didn't model them, so they decoded to nothing and were missing on save). Also UX: rule create forms put the entity picker (table / venue object) below a long guest list, so users had to scroll past dozens of guests to pick a table | iOS PR (`jayne/ios-rules-form-ux`) — added `sideA: [String]?` and `sideB: [String]?` to `SeatingRule` + `RuleDTO` + `toDomain` + `toPlanData`. Keep Apart form redesigned with two stacked side-pickers (Side A / Side B), each with its own search + checkboxes; selecting a guest in one side auto-removes from the other; save writes `sideA`, `sideB`, AND a flat `guests = sideA + sideB` (matching web's `createKeepApartRule`). Form ordering: entity picker now ABOVE guest picker for Assign to Table / Near Table / Near Venue (matching the user's mental model of "pick the venue thing, then who goes with it") |
| 2026-05-05 | iOS Share tab had aspirational stub UI (Viewer / Commenter / Editor segmented control, "Anyone with the link" Copy button, "Require sign-in" toggle, placeholder collaborators with "Invite someone" rows that did nothing) — none of which exist on web. Web only supports email-invite collaboration via `/api/collab` (single Editor role, sign-in always required) | iOS PR (`jayne/ios-share-collab-parity`) — stripped the stubs and replaced with a real Collaborators card that mirrors web's CollaboratorsModal. On Share tab open, GETs `/api/collab?action=list&planId=<id>` and renders: owner row with OWNER badge, each accepted collaborator (with avatar + email), each pending invitation (envelope icon + "Pending"). Owner sees "+ Invite by email" button → SwiftUI alert with email TextField → POSTs `/api/collab?action=invite` (web sends Resend-powered invite email with /join?token=... link). Owner can also tap minus-circle on a collab to remove (`DELETE ?action=remove`) or x-circle on a pending invite to revoke (`DELETE ?action=revoke`). When the user is a collaborator (not owner), shows "Shared by <owner>" banner under the plan preview matching web's collab banner. Removed: the role segmented control, the "Anyone with the link" copy button, the require-sign-in toggle, and the "Invite people" placeholder. New `collabAPIBaseURL` in AppConfig (www subdomain) |
| 2026-05-05 | iOS Share tab had no Guest QR feature, while web has a full GuestQRPanel that mints a `linkToken` via `/api/guest` and renders a scannable code at `seatbee.app/g/<token>` (used by guests to pull up their table assignment). iOS also had no CSV exports — web has Guest CSV + Tables CSV in its Export panel | iOS PR (`jayne/ios-share-qr-csv`) — added `rawGuestQR: AnyCodable?` passthrough to `SeatingPlan` + `guestQR` to `PlanDataDTO` so the web's `qrStyle` / `icebreakers` / etc. survive iOS round-trip. New expandable `Guest QR Code` section in `ShareView` between the social row and Export. Header has chevron + toggle; toggle calls `/api/guest` (`save-config` action, Bearer auth via `AuthService.accessToken`) which mints/returns a token, persisted back into `rawGuestQR`. When expanded with a token, renders the QR via `CIFilter.qrCodeGenerator` (correctionLevel "H" — matches web's `qr-code-styling` config), shows the URL, and provides Share + Save buttons (writes to Photos via `UIImageWriteToSavedPhotosAlbum`). "Customize design on web" link opens Safari for advanced styling. CSV exports in `PDFExportService`: `shareGuestListCSV` (Name/Email/Side/Table/Seat/RSVP/Meal/Dietary/Categories/VIP/Child/HighChair/Notes) and `shareTablesCSV` (Table/Type/Capacity/Seated/Locked/Guests/Meal breakdown/Dietary needs/High chairs); RFC4180-compliant escaping. Two new export cards in ShareView |
| 2026-05-05 | iOS floor plan upload only accepted Photos library images; web's `<input accept="image/*,.pdf">` accepts both PDFs and any image source via the system file picker. Couldn't ingest a venue's PDF floor plan or an image stored in iCloud Drive / Files | iOS PR (`jayne/ios-floor-plan-pdf`) — RoomSetupSheet's FLOOR PLAN section now has two upload buttons side-by-side: Photos (existing PhotosPicker) and Files / PDF (new `fileImporter` with `allowedContentTypes: [.pdf, .image]`). PDFs render page 1 via `PDFKit.PDFDocument` at 2× scale into a UIImage, then flow into the same `analyzeFloorPlan` path as Photos picks. Matches web's page-1-only PDF behavior. Inline error message surfaces on import failure |
| 2026-05-05 | (1) Editor canvas was hardcoded 2000×2000 — Convention preset (4500×3000px room) extended past the canvas surface, tables in the right half rendered off-canvas; minimumZoomScale 0.3 also couldn't fit big rooms on a 400pt screen. (2) Trace canvas was too zoomed in / unusable because GeometryReader returned wrong size during sheet animation. (3) Metric/imperial toggle didn't reflow displayed values. (4) Quick Presets forced imperial on tap. (5) Table detail sheet showed raw category IDs (`a5gb6pp2n`) instead of names. (6) No way to edit a venue object's size, name, or rotation; preset sizes diverged from web. (7) No viewport persistence — leaving the editor lost zoom + scroll position | iOS PR (`jayne/ios-venue-setup-v3.5`, folded into PR #28) — (1) `CanvasViewController.canvasSize` now grows to `max(2000, room + 800)`; minZoom recomputed on layout to guarantee fit; auto-fits on first appearance. (2) `TraceShapeSheet` switched to `.aspectRatio(roomW/roomH)` container, no more GR sizing surprises. (3) Toggle `.onChange` converts displayed numbers (1m = 3.28084ft). (4) Quick Preset apply now respects current unit (converts ft preset → metric inline) and never flips the toggle; subtitle shows in current unit. (5) `EditorView.filledSeatRow` now resolves category id → name via `categoryName(forId:)` lookup against `rawCategories` (same helper as GuestsView). (6) New `EditVenueObjectSheet` mirrors web's Edit Venue Object modal — Name, Width/Height in current unit, Rotation slider with -45/-15/+15/+45/Reset 0°, Quick Size grid using per-type `sizes` array (Dance Floor 4 sizes, Bar 3 sizes) or fallback `{Small=min, Medium=default, Large=max}`. `VenueObjectDef` extended with `minW/maxW/minH/maxH/sizes/isObstacle`; existing 10 entries updated to web's exact values; `checkin` renamed to `registration` matching web. (7) Viewport persistence in `UserDefaults` keyed by `seatbee.canvasViewport.<planId>` — saves on zoom/scroll end, restores on first layout per plan |
| 2026-05-05 | iOS had no interactive room-shape editor; users were stuck with whatever the preset generated. Web's Trace Shape canvas lets you tap to add corners, drag to fine-tune, see live edge lengths in feet | iOS PR (`jayne/ios-venue-setup-v3`) — new `TraceShapeSheet` (in `RoomSetupSheet.swift`) opened from a new "Edit Shape" button in Room Setup. Pure-SwiftUI canvas with: (1) tap a wall (>24pt from any corner) to insert a numbered corner handle, (2) drag corners to reposition (clamped to room bounds), (3) long-press a corner → confirm-delete alert (min 3 corners), (4) live edge labels showing length in ft / m, (5) Flip H / Flip V / Reset toolbar. Coordinate transforms preserve aspect ratio with 30pt margin. On Apply, parent's `selectedShape` flips to "custom" and `workingPoints` overrides the preset-regen on save. Arc / curve editing + Set-Dimensions slider remain V4. |
| 2026-05-05 | iOS RoomSetupSheet only had 4 shape buttons (Rect/L/T/U), no quick presets, no Flip H/V, and rendered nothing for web-authored zones — so users couldn't see them or know they existed | iOS PR (`jayne/ios-venue-setup-v2`) — added L-Reversed / Oval / Circle / Custom shape buttons (8 total in 4×2 grid). Added Quick Presets row matching web's row (Small 50×35ft, Medium 80×60ft, Large 110×80ft, Ballroom 150×100ft, Grand 200×150ft, Convention 300×200ft) — one-tap fills width/height inputs in imperial. Added Flip H / Flip V toggle buttons that persist `plan.roomFlipH`/`roomFlipV` (canvas already reads these in `roomBezierPath()`). Added read-only LABELED AREAS section that lists each `roomZone` with label + dimensions so iOS users can see web-authored zones (full editor deferred to V4) |
| 2026-05-04 | **CRITICAL DATA-LOSS BUG** — `SeatingPlan.toPlanData()` hardcoded `roomShape: nil, measurementUnit: nil, customRoomPoints: nil, roomFlipH: nil, roomFlipV: nil, roomZones: nil, hasSweetheartTable: nil` on every iOS save. Any web-authored venue setup (traced shape, dimensions, zones, flip, custom polygon points) was wiped the first time iOS saved the plan. Also: iOS canvas drew nothing for the room outline, and the existing RoomSetupSheet UI had shape/metric controls that never persisted | iOS PR (`jayne/ios-venue-setup-v1`) — added typed `RoomPoint` (with optional `RoomArc`) and `RoomZone` Codable structs to `Models/SeatingPlan.swift`. Added domain fields `roomShape`, `measurementUnit`, `customRoomPoints`, `roomFlipH`, `roomFlipV`, `roomZones`, `hasSweetheartTable` to `SeatingPlan` (default-nil). EventDataDTO `customRoomPoints`/`roomZones` switched from `AnyCodable?` to typed arrays. `toDomain` now populates these fields; `toPlanData` writes them back instead of nil. Canvas now renders the room outline as a `CAShapeLayer` (Swift port of web's `roomPath()` — supports M/L/A/Z + flipH/V), the floor plan image as a backdrop UIImageView, and zones as dashed-stroke rectangles. RoomSetupSheet now actually persists shape, dimensions (with ft/m → px conversion via web's `RoomScale` factors), measurementUnit, and the floor plan image |

---

## Outstanding gaps (UX-only — data integrity is now closed)

These are paper cuts in iOS UX that don't risk data loss. Listed in priority order.

| Priority | Gap | Notes |
|---|---|---|
| MEDIUM | iOS Party model authoring (full Party object editing with priority/color/etc.) | Round-trip preserved via `rawParties`. iOS currently treats parties as `guest.party: String?` only — can read/preserve full objects, not author them. |
| MEDIUM | `Guest.accessibility` type mismatch (web boolean vs iOS String?) | Both sides round-trip independently, but the type semantics differ. Decide which wins (probably web boolean since it's older). |
| LOW | RoomObject icon/category/isObstacle UI on iOS | Round-trip preserved. iOS doesn't yet display the icon catalog or surface obstacle warnings. |
| LOW | `SeatTable.seatingLayout` field not on iOS | Web supports `seatingLayout: 'all' \| 'banquet'` for rect tables to drive 4-side or banquet seat layouts. iOS DTO/model doesn't have the field, so it's dropped on iOS save → web, and the iOS edit drawer can't surface "All Sides" / "Banquet" buttons. Adding requires `Models/SeatingPlan.swift` change (high-risk file — coordinate with Shayan). |
| LOW | `genResults` preservation | Intentional skip. Recomputable. |
| LOW | Round-table seat placement: Half / Quarter on web, not on iOS | Web's edit-table panel offers "All Around / Half / Quarter" placement for round tables (controls how seats distribute around the perimeter). iOS only supports "All Around" (default) for round tables — no half/quarter UI. Round-trip preserves the web setting (it's stored on the table object), but iOS-edited round tables always reset to all-around. Defer until users ask. |
| MEDIUM | Onboarding: Corporate event flow not on iOS | Web onboarding (App.jsx OnboardingWizard) supports `corporate` event type with subtype picker (gala / networking / conference / 7 more), single vs multi-company mode, seating strategy (by_company vs mix_companies), sponsor/VIP company selection, and a Step 7 "corporate review" of detected companies/departments/VIPs from the CSV. iOS onboarding currently supports `wedding` and `celebration` only. To add: branch step 1 by event type, add corporate-specific fields, port the auto-tag-from-CSV logic for VIPs and company groupings. |
| MEDIUM | Onboarding: Floor plan upload not in iOS onboarding | Web onboarding has a Step 4 (room setup with floor plan upload) and Step 5 (3-phase trace → scale → label of room polygon). iOS has the equivalent UI in `RoomSetupSheet` (accessible from canvas after plan creation), but it's not wired into the onboarding flow as an inline step. Users currently default to a generic rectangular room and customise after creation. To add: surface RoomSetupSheet as an optional Step 3 of onboarding. |
| MEDIUM | Onboarding: Crowdsourcing room-details form | Web onboarding's Step 4 has an optional collapsed form to capture venue room name, capacity, and feature flags (dance floor, bar, pillars, outdoor, high ceilings, sound system, etc.) used to grow the venue-database inventory. iOS doesn't ask any of this. **Important for Jayne's longer-term goal of building a venue floor-plan inventory.** Add as a Phase 2 onboarding feature once iOS has Place ID storage. |
| MEDIUM | Onboarding: Venue Place ID / full Google Places object | Web stores a full Place object (`venue: {id, name, address, location:{lat,lng}, ...}`) and uses the Place ID for floor-plan crowdsourcing lookups. iOS captures venue NAME only via `SBVenueSearch` because the Google Places API key field in `Config/Environment.swift` is empty. To match: Shayan to populate the API key (or coordinate a separate API key for iOS), wire `VenueSearchService` results into onboarding, and store the full Place object instead of just the name. |
| LOW | Onboarding: CSV column mapping UI | Web onboarding has a column-mapping editor that auto-detects CSV headers (Name / Email / Side / Dietary / Party / Meal / etc.) and lets the user reassign columns. iOS pastes plain-text and uses AI parsing instead. Acceptable mobile-friendly trade-off; defer column-mapping UI to a future "Power Import" feature. |
| LOW | Onboarding: Measurement unit toggle on web Step 4 vs iOS Step 1 | iOS now exposes feet/meters in Step 1 (after this PR). Web exposes it in Step 4 (room setup). No data conflict — both write the same `measurementUnit` string. |

---

## PR review checklist

Apply this before approving any PR that touches a shared shape:

- [ ] Did the author update both repos, OR explicitly note the follow-up?
- [ ] Are enum values exactly matching (case-sensitive)?
- [ ] No silent `?? defaultValue` fallbacks for enum reads?
- [ ] Round-trip tested locally (or explicitly waived in the PR description)?
- [ ] `Resolved` / `Outstanding` tables in this file updated?
- [ ] Any new fields documented in both DTOs?

---

## When in doubt

When the shape on web and iOS could plausibly be either thing, **prefer the web app's vocabulary**. It is older, has more usage, and is the source of all production data. If iOS has a name that's "nicer" but conflicts, rename iOS to match.

If you genuinely can't tell which way to go, ping Jayne. Don't guess on a round-trip path.
