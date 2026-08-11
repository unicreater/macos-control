---
name: grill-me
description: Interrogate the user about a proposed project or feature until a shared understanding is reached. Use before writing a PRD. Produces docs/decisions.md capturing every answered question and its decision.
---

# Grill Me

You are running a requirements interrogation. The goal is NOT to write code or a PRD —
it is to eliminate ambiguity by asking the user pointed questions until every
scope-defining decision is made and recorded.

## Process

1. Read any prior research, notes, or scope documents in the conversation and repo
   (`docs/`, `README.md`) to avoid re-asking what is already decided.
2. Build a question backlog covering, at minimum:
   - **Users & jobs**: who uses this, what job does it do, what does success look like?
   - **Scope tiers**: which proposed features are v1, which are later, which are never?
   - **Platforms & minimums**: OS versions, device families, distribution channel
     (App Store vs direct/notarized) and the permission/sandbox consequences.
   - **Architecture forks**: any decision with two defensible options (transport,
     persistence, pairing model, UI framework) — present the tradeoff, get a ruling.
   - **Constraints**: build/test environment limits, timeline, budget, existing code.
   - **Non-goals**: explicitly list what is out of scope so it can't creep back in.
3. Ask questions in rounds using the AskUserQuestion tool, max 4 per round, most
   scope-defining questions first. Every question must offer concrete options with
   tradeoffs, and a recommended option marked "(Recommended)" listed first.
4. After each round, restate the decisions made so far in one short paragraph, then
   continue to the next round. Stop when a new round would only produce questions
   whose answers would not change what gets built.
5. Write every decision to `docs/decisions.md` as a table: Question | Decision |
   Rationale | Date. Commit it.

## Rules

- Never answer your own questions and move on — a decision requires the user's input.
- If the user answers "you decide", record the decision as delegated and pick the
  recommended option.
- Do not start designing or coding. The output of this skill is `docs/decisions.md`
  and a closing summary of the agreed scope, nothing else.
- End by telling the user the scope is locked and the next step is `/create-a-prd`.
