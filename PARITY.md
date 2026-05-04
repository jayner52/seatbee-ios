# Cross-App Parity — Seatbee Web ↔ Seatbee iOS

**Read this file before making any change to data that persists to Supabase.**

This rule applies equally to **Jayne's Claude** (working from `~/Desktop/Seating Plan App` or `~/Desktop/seatbee-ios`) and **Shayan's Claude** (working from his clones of the same two repos). Identical content lives in both repos as `PARITY.md` at the root.

---

## Why this exists

The Seatbee web app and the Seatbee iOS app share the same Supabase backend (`puckyaxybgxipoqdrekt`). The entire plan state — guests, tables, rules, room objects, parties, categories — is persisted to a JSONB `data` column on the `seating_plans` table. Both apps read and write that same shape.

When the two apps disagree on the shape — a different enum value, a missing field, a renamed property — opening a plan on one app and saving it can silently corrupt the data when the other app reads it back.

### The 2026-05-03 incident

Shayan's iOS Sprint 2 introduced a `RuleType` enum with 4 camelCase values (`seatTogether`, `keepApart`, `assignTable`, `seatNear`). The web app's rules engine has always used 10 snake_case values (`must_together`, `prefer_together`, `must_not`, `must_table`, `near_table`, `near_object`, `category_together`, `vip_priority`, `side_together`, `seat_adjacent`). Zero overlap.

iOS used a silent `?? .seatTogether` fallback on read. So when iOS opened Jayne's test plan, every rule type became `seatTogether`. On next iOS save, the JSONB blob was overwritten — every rule's `type` field in the database was now `seatTogether`. The web evaluator returned "Unknown rule" for all 55 rules.

**This is the failure mode this doc exists to prevent.**

User data in production was safe (RLS scopes iOS access to the dev's own plans), but the failure was silent — there was no error log, no warning, no PR review catch.

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
| Category | `state.categories[]` | `Models/DTOs/SeatingPlanDTO.swift` `CategoryDTO` (no domain model yet) |
| Party | `state.parties[]` (when present) | `Features/Guests/PartiesSheet.swift` (no Party model yet) |

Internal-only fields (UI state, ephemeral selection, drag offsets, panel toggles) are NOT shared. If it never round-trips to Supabase, it's safe to differ.

---

## Procedure when changing a shared field

1. **Read this file fully** before editing.
2. **Identify whether your change affects a shared shape.** When in doubt, ask: does this end up in `seating_plans.data`? If yes → shared.
3. **Update both apps in the same PR cycle.** If you can't (the other dev needs to do it), open a tracking issue or send a Telegram heads-up with the field shape and the deadline.
4. **Add defensive logging on read.** When reading enum values from the persisted blob, log unknown values to console:
   - Web: `console.warn('[seatbee] Unknown rule type:', r.type, 'rule:', r)`
   - iOS: `print("[Seatbee] Unknown rule type: \(rawType)")`
5. **Never use silent `?? defaultValue` for unknown enums.** Use an explicit `.unknown(String)` case that preserves the original, OR throw, OR log loudly. Never coerce silently.
6. **Verify round-trip locally.** Web edit → save → iOS read → iOS save → web read. The shape should be identical at every hop.
7. **Update this file's "Known parity gaps" section** when introducing or resolving drift.

---

## Anti-patterns

- ❌ Silent enum fallback on read (`?? .firstCase`)
- ❌ Adding a new field to one side and "we'll do iOS/web later"
- ❌ Renaming an enum case without updating both repos in lockstep
- ❌ Trusting that fields round-trip just because the build compiles
- ❌ Storing the same concept under different field names on each side
- ❌ Letting the build pass with TODOs that say "wire up to other app later"
- ❌ Reading old data with a less-permissive shape (e.g. iOS only knows 4 of web's 10 rule types) without explicitly preserving the rest

---

## Known parity gaps (as of 2026-05-03)

These are the gaps identified in the 2026-05-03 audit. Severity is ranked by data-corruption risk on round-trip.

### CRITICAL — data corruption on round-trip

| Gap | Web | iOS | Fix scope |
|---|---|---|---|
| `SeatingRule.type` enum mismatch | 10 snake_case values | 4 camelCase values | iOS rename + expand; web defensive log |
| Missing iOS rule fields | `categoryId`, `objectId`, `sideValue`, `desc`, `auto`, `source`, `partyId`, `groupId` | None of these exist on iOS Rule struct | iOS `Models/SeatingPlan.swift` |

Web file references: `src/App.jsx:4798` (rule evaluator entry), `src/App.jsx:5036` (default branch returning "Unknown rule").
iOS file references: `seatbee/Models/SeatingPlan.swift:107-112` (RuleType enum), `seatbee/Models/DTOs/SeatingPlanDTO.swift:209` (silent fallback).

### HIGH — UX broken or silent data loss

| Gap | Web | iOS | Fix scope |
|---|---|---|---|
| `Guest.dietaryTags: [String]` | Drives per-restriction emoji | Field missing entirely (only `dietary: String?`) | iOS Guest struct + DTO + Guests UI |
| Category model | Full `{id, name, color, isSystem, affinityWeight}` objects | Only `[String]` of IDs on guest, no Category model | iOS new model + DTO mapping + Guests UI |
| `Guest.accessibility` type | `boolean?` (web) | `String?` (iOS) | Decide canonical type — web wins by precedent |

### MEDIUM — partial features

| Gap | Web | iOS | Fix scope |
|---|---|---|---|
| Party model | Full Party object with `members`, `priority`, `fallbackGroupId`, `color` | Only `guest.party: String?` | iOS new model + UI |
| `Guest.highChair`, `Guest.groupIds` | Present | Missing on iOS | iOS Guest struct |
| Plan soft-delete `deletedAt` | Present (uses migration 028) | DTO reads but no domain model field | iOS Plan struct + DTO |

### LOW — less-frequent fields

| Gap | Web | iOS | Fix scope |
|---|---|---|---|
| `RoomObject` extras: `color`, `category`, `icon`, `isObstacle` | Present | Missing | iOS RoomObject struct |
| `SeatTable` extras: `diameter` (round), `sweetShape` (sweetheart variant), `oneSide` (head table) | Present | Missing | iOS SeatTable struct |
| Plan variants: `isVariant`, `parentEventId`, `variantNumber` | Present (migration 027) | Missing | iOS Plan struct |
| Plan `roomShape` | Present | Missing | iOS Plan struct |

### Resolved

(none yet — populate as PRs land)

---

## PR review checklist

Apply this before approving any PR that touches a shared shape:

- [ ] Did the author update both repos, OR explicitly note the follow-up?
- [ ] Are enum values exactly matching (case-sensitive)?
- [ ] No silent `?? defaultValue` fallbacks for enum reads?
- [ ] Round-trip tested locally (or explicitly waived in the PR description)?
- [ ] `Known parity gaps` table in this file updated?
- [ ] Any new fields documented in both DTOs?

---

## When in doubt

When the shape on web and iOS could plausibly be either thing, **prefer the web app's vocabulary**. It is older, has more usage, and is the source of all production data. If iOS has a name that's "nicer" but conflicts, rename iOS to match.

If you genuinely can't tell which way to go, ping Jayne. Don't guess on a round-trip path.
