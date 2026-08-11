---
name: implementation-loop
description: Execute the PRD milestone by milestone in a build-test-review loop. Use after /create-a-prd. Tracks progress in docs/PRD.md checkboxes and commits per milestone.
---

# Implementation Loop

Deliver `docs/PRD.md` one milestone at a time. Each loop iteration is:
implement → verify → review → commit → report → next.

## Preconditions

- `docs/PRD.md` must exist with a milestone list. If not, stop and point the user
  to `/create-a-prd`.

## Loop (per milestone)

1. **Pick** the first incomplete milestone. Announce it and the FR-IDs it covers.
2. **Plan** the file-level changes briefly (a few bullets, not a ceremony).
3. **Implement** on the designated feature branch. Follow existing code style.
4. **Verify** using the milestone's stated verification method:
   - Run `swift build` / `swift test` for any target the local toolchain can build.
   - For targets the environment cannot build (e.g. iOS/macOS app targets on
     Linux), verify what is verifiable (shared-package tests, `swiftc -parse`
     syntax checks) and record exactly what remains to be verified on real
     hardware in `docs/VERIFY.md`. Never claim device-only behavior is tested.
5. **Review** the diff yourself for correctness and simplification before
   committing; fix what you find.
6. **Commit** with a message naming the milestone and FR-IDs. Push to the
   designated branch.
7. **Report** in one short paragraph: what was delivered, verification results
   (including failures — verbatim), and what's next. Update the milestone
   checkbox in `docs/PRD.md`.
8. Continue to the next milestone. Stop only when all milestones are done, the
   user interrupts, or a blocker needs a user decision — state the blocker and
   the options if so.

## Rules

- Never mark a milestone complete with failing tests or unbuilt code; a milestone
  blocked by environment limits is marked "implemented, pending device
  verification" in docs/VERIFY.md instead.
- Scope creep goes to a "Deferred" list in the PRD, not into the current milestone.
- If a PRD requirement turns out to be wrong or infeasible mid-loop, stop and ask
  the user rather than silently deviating.
