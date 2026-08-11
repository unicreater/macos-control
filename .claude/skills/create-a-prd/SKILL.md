---
name: create-a-prd
description: Write a full Product Requirements Document from the decisions captured by /grill-me. Produces docs/PRD.md with milestones sized for the implementation loop.
---

# Create a PRD

Turn the locked scope in `docs/decisions.md` (plus conversation context) into a
complete, implementation-ready PRD at `docs/PRD.md`.

## Preconditions

- `docs/decisions.md` must exist. If it doesn't, stop and tell the user to run
  `/grill-me` first. Do not invent decisions.

## PRD structure (all sections required)

1. **Overview** — one paragraph: what the product is, for whom, and why.
2. **Goals / Non-goals** — bulleted; non-goals come straight from decisions.md.
3. **Personas & core user journeys** — numbered end-to-end flows (first-run pairing,
   daily use, failure/reconnect).
4. **Feature requirements** — grouped by area. Each requirement gets an ID (`FR-1`,
   `FR-2`, …), a priority (P0 = v1 blocker, P1 = v1 nice-to-have, P2 = later), and
   acceptance criteria phrased as observable behavior.
5. **System architecture** — targets/modules, data models, protocol/message schema,
   persistence, and the permission/entitlement plan. Include a diagram in Mermaid.
6. **Platform constraints** — OS minimums, sandbox/entitlement consequences,
   distribution channel.
7. **Milestones** — an ordered list sized for `/implementation-loop`: each milestone
   is independently buildable/testable, lists the FR-IDs it delivers, and names its
   verification method (unit tests, manual steps on device, etc.).
8. **Risks & open questions** — anything decisions.md left open, with owners.

## Rules

- Every P0 requirement must trace back to a decision or an explicit user request;
  cite the decision in the requirement.
- Acceptance criteria must be checkable without interpretation ("tile shows a green
  dot within 1s of app launch", not "status updates quickly").
- Keep the PRD self-contained — a reader must not need the chat transcript.
- Commit `docs/PRD.md`, then present the milestone list to the user for sign-off and
  point them at `/implementation-loop` as the next step.
