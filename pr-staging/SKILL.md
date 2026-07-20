---
name: pr-staging
description: Use when the user asks to "create a PR", "push PR to staging", "buat pull request", "buat PR ke staging", or wants to open a pull request from the current branch. Builds a PR to the `staging` branch that follows the team's Pull Request Standards (conventional title, structured description, task link, checklist) and pushes only after explicit confirmation.
---

# PR to staging

Builds and opens a pull request from the current branch into `staging`, formatted to the
team's Pull Request Standards. Never pushes or opens the PR without an explicit go-ahead
from the user on the drafted title/description.

Base branch is always `staging` (per CLAUDE.md: feature/hotfix branches → staging; only
`release/*` → main). If the current branch is `main`, `staging`, or `dev`, stop and tell the
user — this skill only runs from a feature/fix branch.

## Step 1 — Verify local `staging` matches `origin/staging`

```bash
git fetch origin staging
git show-ref --verify --quiet refs/heads/staging && echo "has-local-staging" || echo "no-local-staging"
```

If a local `staging` branch exists, it must be bit-for-bit in sync with `origin/staging`
before you touch anything else:

```bash
git rev-parse staging
git rev-parse origin/staging
```

- If the two hashes match, continue to Step 2.
- If they **differ**, STOP here. Show the user the divergence:
  ```bash
  git log staging..origin/staging --oneline   # commits local staging is missing
  git log origin/staging..staging --oneline   # commits local staging has that origin doesn't
  ```
  Tell the user local `staging` has drifted from `origin/staging` and **they must resolve it
  themselves** (they've indicated this is usually a rebase) — do not run `git rebase`,
  `git merge`, `git reset`, or any other fix on their `staging` branch on their behalf. This
  is their call because it touches a shared branch and the resolution (rebase vs merge vs
  discard local commits) depends on context you don't have. Wait for them to confirm it's
  resolved, then re-verify the hashes match before moving on.

If there's no local `staging` branch at all, there's nothing to reconcile — proceed straight
to Step 2 (the rest of this skill diffs against `origin/staging` directly, never the local
branch).

## Step 2 — Gather branch + diff context

```bash
git branch --show-current
git fetch origin staging
git log origin/staging..HEAD --oneline
git diff origin/staging...HEAD --stat
git diff origin/staging...HEAD
```

Read the commit log and full diff yourself — don't just skim the stat — so the description
you draft in Step 5 is grounded in what actually changed, not guessed from the branch name.

## Step 3 — Resolve the task ticket

Task tracker is YouTrack at `https://sentinel.youtrack.cloud/`.

1. Extract a ticket ID from the branch name with a pattern like `[A-Z]{2,}-\d+` (e.g.
   `feature/SLS-349-enhance-upload-id-card-api` → `SLS-349`).
2. If found, build the link as `https://sentinel.youtrack.cloud/issue/SLS-349` and show it
   to the user for confirmation — don't assume it's correct silently, branch names can be
   stale or wrong.
3. If no ID is found in the branch name, ask the user for the ticket ID or full URL. Do not
   proceed to open the PR without a task link — it's mandatory per the standard.

## Step 4 — Check PR size against the 400-line cap

Compute changed lines excluding generated files, lockfiles, and config:

```bash
git diff origin/staging...HEAD --shortstat -- . \
  ':(exclude)go.sum' \
  ':(exclude)config.json' ':(exclude)config.json.example' \
  ':(exclude)*.pb.go'
```

Also exclude any file whose content starts with a `// Code generated ... DO NOT EDIT` header.

- If the result is **≤ 400 lines**: proceed normally.
- If **> 400 lines**, check whether the whole diff qualifies for an exemption:
  - **Rename-only**: every changed file is a rename with no logic changes (`git diff
    origin/staging...HEAD --diff-filter=R` covers all changes, or the non-renamed diff is trivial).
  - **Test-only**: every changed file matches `*_test.go`.
  - **Migration**: changes are confined to a migrations/backfill directory.
  - **Initial scaffolding**: this is the first commit of a brand-new feature/module (e.g. a
    fresh `features/[name]/` with no prior history).
  - If it fits one of these, note the exemption in the PR description and continue.
  - If it does **not** fit an exemption, tell the user the PR exceeds the cap, recommend
    splitting it into smaller PRs with a dependency chain, and ask how they want to proceed.
    Don't silently create an oversized PR — surface the trade-off and let them decide.
  - If the user chooses to override the cap and proceed as one PR anyway, don't just note
    "user approved" — add a `## Note on PR size` section to the description (after `## Task
    link`, before `## How to test`) that argues the *coupling*, not just the ticket boundary.
    Ground it in specifics from the diff: name the fields/functions/tables that are shared
    or interdependent across the files that pushed the diff over the cap, and state what
    would break or half-work if split (e.g. "endpoint X reads field Y, which only this PR
    adds — splitting ships a consumer with no producer or vice versa"). A justification that
    only says "it's one ticket" or "it's a cohesive feature" isn't enough — a reviewer should
    be able to tell from the note specifically why sequencing two PRs would leave the system
    in a broken or bug-reintroducing intermediate state.

## Step 5 — Draft the PR

**Title** — `type(scope): short description`, same convention as commit messages. Infer
`type` (feat/fix/refactor/etc.) from the dominant commit type in the branch's log, and
`scope` from the primary feature directory touched (e.g. `id_card_upload`, `hotel_search`).
If commits mix multiple types with no clear majority, ask the user which type/scope to use
rather than guessing.

**Description** — use this exact structure:

```markdown
## What changed
- ...

## Why
...

## Task link
https://sentinel.youtrack.cloud/issue/SLS-XXX

## How to test
1. ...

## Screenshots/recordings
N/A (backend API change — no UI)   <!-- only include real screenshots if the change affects something visual -->

## Checklist
- [ ] Self-reviewed the diff
- [x] Linked task management ticket
- [ ] Tests added/updated
- [ ] No console.log or debug code left
- [ ] CI checks pass
- [ ] Documentation updated (if applicable)
```

Fill in each section from the real diff/commits — "What changed" is a bullet summary of the
actual code changes, "Why" is the business/technical motivation (infer from commits/ticket,
ask the user if it's not evident), "How to test" is concrete steps (endpoint to hit, request
body, expected response, or `go test ./...` for logic-only changes).

Verify checklist items instead of assuming them, then check the box only if verified:

- **Tests added/updated**: check if the diff touches any `*_test.go` file.
  ```bash
  git diff origin/staging...HEAD --name-only | grep '_test\.go$'
  ```
- **No console.log or debug code left**: grep the diff for debug leftovers (Go has no
  `console.log`, so check the Go equivalents plus stray debug helpers):
  ```bash
  git diff origin/staging...HEAD | grep -nE '^\+.*(fmt\.Print(ln|f)?\(|spew\.Dump\(|debugger|TODO: remove)'
  ```
  If this finds unexplained debug statements, flag them to the user instead of silently
  checking the box — they may need removing before the PR is ready.
- **CI checks pass**: only checkable after pushing (Step 7). Leave unchecked in the draft;
  update after `gh pr checks` reports green.
- **Self-reviewed the diff** and **Documentation updated (if applicable)**: these require a
  human judgment call — leave unchecked in the draft and ask the user to confirm them when
  reviewing the draft in Step 6.

## Step 6 — Confirm before touching anything remote

Show the user:
- The full drafted title + description
- The size-check result (and exemption reasoning if applicable)
- Any debug-code or missing-ticket-link warnings

Then explicitly ask for confirmation before running any of the commands in Step 7. Pushing a
branch and opening a PR are visible, hard-to-undo actions — never do them without an
explicit go-ahead on the drafted content, even if the user asked for this skill to run.

## Step 7 — Push and open the PR (only after confirmation)

```bash
git push -u origin <current-branch>
gh pr create --base staging --title "<title>" --body-file <tmpfile-with-description>
```

Write the description to a file in the scratchpad directory first and pass it via
`--body-file` — multi-line bodies with markdown are error-prone to pass inline.

After creation:
```bash
gh pr checks <pr-number-or-url>
```
Report the PR URL back to the user, and update the "CI checks pass" checkbox status based on
the actual check results (edit the PR body via `gh pr edit` if it flips after initially
opening, e.g. once CI finishes).
