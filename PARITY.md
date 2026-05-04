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
| Plan-level metadata | `state.event`, `state.tier`, etc. | `Models/SeatingPlan.swift` (root) |
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

`name`, `date`, `venue`, `eventType`, `roomWidth`, `roomHeight`, `roomShape`

### Guest

Core: `id`, `name`, `firstName`, `lastName`, `email`, `categories` (array of category-IDs), `dietary` (free text), `notes`, `rsvp` (`yes`/`no`/`pending`/`unknown`), `side` (`bride`/`groom`/`both`/`none`), `vip`, `accessibility`, `plusOne`, `party` (party ID/name string), `display`

Web-parity (preserved on iOS round-trip): `dietaryTags` (array of strings — drives per-restriction emoji on web), `highChair` (boolean), `groupIds` (array), `isBride` (boolean, cached), `isGroom` (boolean, cached), `meal` (string), `createdAt` (ISO timestamp)

### SeatTable

Core: `id`, `name`, `type` (`round`/`rect`/`head`/`sweetheart`), `seats`, `x`, `y`, `rotation`, `assignments` (handled separately, see below), `locked`, `color`

Web-parity (preserved on iOS round-trip): `width`, `height` (rect/head), `diameter` (round), `sweetShape` (`HEART`/`OVAL`/`DIAMOND` for sweetheart variants), `oneSide` (boolean for head table)

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

---

## Outstanding gaps (UX-only — data integrity is now closed)

These are paper cuts in iOS UX that don't risk data loss. Listed in priority order.

| Priority | Gap | Notes |
|---|---|---|
| HIGH | iOS Category UX (shows IDs not names) | Round-trip is preserved via `rawCategories`. iOS UI just needs to look up `category.name` from `rawCategories` instead of rendering the raw ID. |
| HIGH | iOS structured dietary emoji rendering (🌿 vegan, 🥜 nut allergy, etc.) | `dietaryTags` now round-trips. iOS UI currently shows generic 🍽️ chip. Needs the per-tag emoji map and chip-per-tag rendering. |
| MEDIUM | iOS Party model authoring (full Party object editing with priority/color/etc.) | Round-trip preserved via `rawParties`. iOS currently treats parties as `guest.party: String?` only — can read/preserve full objects, not author them. |
| MEDIUM | `Guest.accessibility` type mismatch (web boolean vs iOS String?) | Both sides round-trip independently, but the type semantics differ. Decide which wins (probably web boolean since it's older). |
| LOW | RoomObject icon/category/isObstacle UI on iOS | Round-trip preserved. iOS doesn't yet display the icon catalog or surface obstacle warnings. |
| LOW | `SeatTable.seatingLayout` field not on iOS | Web supports `seatingLayout: 'all' \| 'banquet'` for rect tables to drive 4-side or banquet seat layouts. iOS DTO/model doesn't have the field, so it's dropped on iOS save → web, and the iOS edit drawer can't surface "All Sides" / "Banquet" buttons. Adding requires `Models/SeatingPlan.swift` change (high-risk file — coordinate with Shayan). |
| LOW | `genResults` preservation | Intentional skip. Recomputable. |

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
