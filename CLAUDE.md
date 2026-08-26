When writing Swift: target Swift 6 idioms on macOS 15+ (current build is
   Swift 5.10). No force unwraps. Mark types Sendable where crossing actor
   boundaries. If SwiftUI is added: @Observable not ObservableObject,
   NavigationStack not NavigationView, foregroundStyle not foregroundColor.

**`ROADMAP.md` is the SINGLE SOURCE OF TRUTH for execution** — what's left, what's next, and
every phase / acceptance criterion / decision, across all workstreams. On any handoff, **read it
first and follow only it as the plan.** There are deliberately **no other `*_PLAN` or handoff
docs** — `docs/handoff.md` was consolidated into it (2026-08-07); never recreate a handoff doc.
Put new plan or status content in `ROADMAP.md`. If any doc's status conflicts with ROADMAP,
ROADMAP wins. `docs/design/v1.md` stays separate as the architecture/schema/risk reference —
it reasons, it doesn't sequence; consult it on demand, don't treat it as the plan.

**Backlog items are not blockers.** No item under a `BACKLOG` / `PARKED` status gates any other
work unless it carries a `⛔ BLOCKS:` line quoting the owner's instruction from when it was
parked. Absent that line, it is non-blocking. Do not infer blocking from urgency or dependency
order.

`DECISIONS.md` is append-only; supersede rather than rewrite.

Read order for a fresh session: this file → `ROADMAP.md`, then `docs/design/v1.md` /
`docs/release.md` on demand.