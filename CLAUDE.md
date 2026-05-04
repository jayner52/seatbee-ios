# Seatbee iOS — Collaboration Rules

This is a two-developer codebase. **Jayne** (`jayner52` on GitHub) and **Shayan** (`shayancelso` on GitHub) edit it in tandem, both using Claude Code. These rules exist so we never end up with divergent build paths, lost work, or painful merge conflicts.

**Both Claudes (Jayne's and Shayan's) must follow these rules. They override default behavior.**

---

## The non-negotiable rules

1. **Never commit directly to `main`.** Always work on a branch named `jayne/<task>` or `shayan/<task>`.
2. **Always `git pull origin main` before starting any work.** Get current first.
3. **Every change reaches `main` via a Pull Request.** No exceptions, even for one-line fixes.
4. **Coordinate before touching shared/risky files** (see "High-risk files" below). A 5-second Telegram heads-up beats a 30-minute merge conflict.
5. **Never commit secrets.** `seatbee/Config/Secrets.swift` is gitignored for a reason. Don't commit API keys, tokens, or anything that ends in `.env`.
6. **Cross-app parity:** Before changing any shared data shape (anything that persists to Supabase `seating_plans.data` — rules, guests, tables, room objects, categories, parties, plan-level fields), **read [`PARITY.md`](./PARITY.md) first.** Drift between iOS and the web app silently corrupts plan data on round-trip. The same `PARITY.md` lives in the web repo (`jayner52/Seated`) so both Claudes work from the same playbook.

---

## Daily workflow

**Starting a work session:**

```bash
cd ~/Desktop/seatbee-ios   # or wherever Shayan keeps his clone
git checkout main
git pull origin main
git checkout -b jayne/short-description-of-task   # or shayan/...
```

**While working:**

- Make small, focused commits. One logical change per commit.
- Commit messages should describe the *what* and *why*, not just "wip" or "updates".
- Run the build (⌘B in Xcode) before committing — don't push code that doesn't compile.

**Finishing a work session:**

```bash
git push -u origin jayne/short-description-of-task
gh pr create --fill   # opens a PR for the other person to review/merge
```

Then notify the other person via Telegram so they know to review.

---

## Branch naming

- `jayne/<task>` — Jayne's branches
- `shayan/<task>` — Shayan's branches
- Use kebab-case: `jayne/fix-day-of-search`, `shayan/add-rsvp-screen`
- One task per branch. Don't pile unrelated changes onto one branch.

---

## High-risk files (coordinate before editing)

These files cause painful merge conflicts when both people touch them simultaneously. **Send a Telegram heads-up before editing:**

- `seatbee.xcodeproj/project.pbxproj` — touched any time you ADD, RENAME, or DELETE a file
- `seatbee/App/AppRouter.swift` — navigation
- `seatbee/App/AppState.swift` — global state
- `seatbee/Config/Environment.swift` — config (rarely edited; if you are, double-check why)
- Any shared model in `seatbee/Models/`

**The rule:** if you're going to add a new Swift file, rename one, or delete one — **announce it first**, do it fast, push immediately. Don't sit on file structure changes for hours.

---

## File adds & renames (the #1 conflict source)

1. Telegram: "adding `Features/Settings/SettingsView.swift` in the next 10 min"
2. Pull, branch, add the file in Xcode, commit, push, open PR
3. Get the PR merged ASAP — same day if possible
4. Both people pull `main` immediately after merge

If you're in the middle of a long-running branch and need to add a file, consider whether it can wait until your branch merges.

---

## Communication norms

- **Telegram is the coordination channel.** Quick heads-ups about what you're working on.
- **PRs are where decisions get documented.** Use the PR description to explain *why*, not just *what*.
- **GitHub mobile notifications on for both people** — instant ping when the other pushes or opens a PR.

---

## Things that are NOT automated (and why)

We deliberately do not auto-push, auto-pull-merge, or auto-commit. Sync points are intentional. Two machines running automated push/pull would create the exact divergence we're trying to avoid.

What IS automated:
- **Xcode auto-fetch** — silently checks GitHub for updates, doesn't change your code
- **GitHub notifications** — pings when partner pushes
- **Pre-commit hook** — blocks accidental commits to `main` and accidental commits of `Secrets.swift`

---

## Conflict resolution

If `git pull` reports a conflict:

1. **Don't panic, don't force anything.**
2. Open the conflicted file in Xcode — conflicts are marked with `<<<<<<<`, `=======`, `>>>>>>>`.
3. Choose which version to keep (yours, theirs, or a combination).
4. Save, `git add <file>`, `git commit`.
5. If unsure, **stop and ask the other person before resolving** — they may know context you don't.

For `project.pbxproj` conflicts specifically: **always ask the other person first.** Resolving these wrong can break the entire Xcode project.

---

## Rules for Claude assistants

When either Claude (Jayne's or Shayan's) is helping work on this repo:

1. **Read this file first** before suggesting any git operation.
2. **Verify the current branch** with `git branch --show-current` before recommending commits or pushes.
3. **Refuse to commit to `main`** unless the user explicitly overrides ("yes I really mean main"). If they're on `main`, suggest creating a branch first.
4. **Always suggest `git pull origin main` at the start of a work session.**
5. **When the user asks to add a new Swift file, rename one, or delete one** — remind them to coordinate with the other developer via Telegram first (because of `project.pbxproj` conflict risk).
6. **Never commit `Secrets.swift`.** Refuse if asked.
7. **Use `gh pr create` for PRs**, not raw web flows.
8. **When recommending a branch name**, use the convention above (`jayne/...` or `shayan/...` — match the user's GitHub identity).

---

## Architecture quick reference

This codebase shares a Supabase backend with the Seatbee web app (project URL: `puckyaxybgxipoqdrekt.supabase.co`). The pattern follows the Seeya architecture:

- One Supabase project, two clients (web + iOS)
- Native Swift, Supabase Swift SDK direct (no middle layer for CRUD)
- DTOs in `seatbee/Models/DTOs/` handle snake_case ↔ camelCase mapping
- AI calls go to web endpoints at `https://seatbee.app/api/ai`
- Stripe purchases are NOT in iOS (Apple's 30% rule on in-app digital goods) — defer upgrades to web

For new features, follow the existing folder convention: one folder per feature under `seatbee/Features/`, shared components in `seatbee/DesignSystem/Components/` with the `SB` prefix.
