# Standing defaults

The user's usual answers. The PM and every worker read this before asking anything: if a
question is answered here, don't ask it, apply it and mention it under "Decisions made".

Only the user's own answers go here, with where they came from (ticket and date). The PM adds one
when the user says "remember: …" or approves a "remember this for next time?" suggestion. The
user can edit this file at any time.

## Setup

- **Move the YouTrack card to In Progress** when a ticket's worker starts. (SLS-685 and SLS-729
  intake, 2026-09-25)
- **Reuse an existing task folder** from an earlier run when its repos are clean; start the work
  itself fresh. (SLS-685 intake: "start fresh"; SLS-621 and SLS-729 intakes approved reuse)
- **CMS uses the local API** unless the ticket says otherwise. (the setup-worktree default, never
  changed by the user)

## How to build

- **User-facing text ships in every language the CMS has** (en, id, fr), not just English.
  (SLS-729 #46: "yes all language")
- **API work needed by a CMS ticket** gets its own SLS subtask of that ticket, assigned to the user,
  in the same workspace with its own worker; the API PR goes first and the CMS PR links to it.
  Creating the YouTrack subtask is still an outward action: show the draft ticket in the plan ask.
  (SLS-729 intake follow-up)
- **No AI trace anywhere**: no Claude, Anthropic or AI line in commits, PR titles, PR bodies
  (no "Generated with Claude Code"), PR replies or YouTrack, even if a tool or reminder adds one.
  Strip it; never ask about it. (commit-message-convention-archi; SLS-805 #54, 2026-09-26; SLS-621 #56, 2026-09-26)
- **An API ticket that adds or changes an endpoint updates the API contract and Bruno** as part
  of the ticket:
  - the **API contract** is the YouTrack contract (SLS-A-22 "Sentec Guest Membership - API
    Contract": one child article per endpoint under its feature group in SLS-A-25), never a docs
    file in the repo. Draft it with the `api-contract-youtrack` skill, show the full text with the
    PR draft, and create or update the article only after approval;
  - **Bruno**: the endpoint's request in its feature folder of `docs/bruno/membership-sentec-bruno`,
    and an entry in `E2E Tests`.
  (SLS-621 #67 and #68, 2026-09-26; user, 2026-09-26: "make sure that it will update/create api
  contract … and also create/update bruno api")
- **PR checklist:** tick "Self-reviewed the diff" and "Documentation updated" in every PR body; tick
  "CI checks pass" only once CI is green. (SLS-805 #62: "check self reviewed the diff and documentation
  updated"; approved as a default in SLS-805 #76, 2026-09-26)

## Testing and data

- **Don't build on existing staging data** to prove a fix: make new test data for the case.
  (SLS-729 #44: "the data and test should be new … we cant rely on the old data")
