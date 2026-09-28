---
name: pr-resolver
description: Use when the user gives a PR and asks to "resolve the PR comments", "watch this PR", "handle the review", "/pr-resolver <pr>", or wants review feedback fixed until merge. Starts a 10-minute loop on that PR that fixes blocker/major/minor findings (commit via commit-message-convention-archi, push, reply, resolve), replies to invalid comments explaining why, reports CI failures and conflicts, and when the PR is merged moves its SLS card(s) to QA in YouTrack and stops the loop.
---

# PR resolver

Watches one pull request until it is merged. Every 10 minutes it reads the review feedback,
fixes real problems on the PR branch, pushes, and answers the reviewer. When the PR is merged it
moves the SLS card to **QA** and stops.

Starting this skill on a PR **is** the user's approval to commit, push to that PR's branch, reply
to its comments and resolve fixed threads, for as long as the loop runs. Nothing else goes out
without asking.

## Hard rules

- **No AI trace anywhere**: commits, PR replies, PR comments and YouTrack. No `Co-Authored-By`,
  no "Generated with", no mention of Claude or AI. Replies read as if the user wrote them.
- Commit with `commit-message-convention-archi` (Skill tool): Conventional Commits, atomic,
  core and test changes in separate commits.
- Never force-push, never rebase or reset the PR branch, never touch `staging` or `main`.
- Only the PR's own repo folder. Never edit `~/Documents/Workspace/sls/staging/`.
- Unit tests only. Never run docker, the stack, E2E or database clients.
- Replies and reports in plain, short English.

## Arguments

- `/pr-resolver <pr-url | owner/repo#n | n>`: start (or restart) the loop on that PR.
- `/pr-resolver tick <pr-url>`: one pass. The loop sends this; the user doesn't need to.
- `/pr-resolver stop <pr-url>`: stop the loop without touching YouTrack.

`S=~/.claude/skills/archi-skills/pr-resolver/scripts/pr-state.sh`: prints the PR state as JSON
(`$S <repo-dir> <pr-number>`). Read its header for the fields.

## State file

One per PR, inside the repo's git dir so it is never committed:
`STATE=$(git -C <repo-dir> rev-parse --absolute-git-dir)/pr-resolver/<number>.json`

```json
{
  "pr_url": "", "repo_dir": "", "head": "", "tickets": ["SLS-801"], "cron_id": "",
  "started_at": "", "fix_rounds": 0,
  "handled": ["<thread_id or comment/review url>", "..."],
  "declined": ["<one line per point already answered as invalid>"],
  "waiting_user": ["<one line per point waiting on the user>"],
  "reported": {"ci": "<failing names last reported>", "conflict": false}
}
```

## Start

1. **Find the PR.** `gh pr view <pr> --json number,url,state,headRefName,author,title` (for a
   bare number, use the repo of the current folder). If it is already merged, go straight to
   "Merged" below. If it is closed, say so and stop.
2. **Is it the user's PR?** If `author` is not `gh api user --jq .login`, ask before going on:
   this skill pushes to the branch.
3. **Find the local checkout.** Look for a folder `~/Documents/Workspace/sls/*/<repo>` (not
   `staging/`) whose `git branch --show-current` is the PR's head branch. None, or more than
   one → ask the user which folder to use. Don't create worktrees.
4. **Tickets.** Every `SLS-<n>` in the head branch name and the PR title, uppercase, no
   duplicates. None found → ask which card to move on merge (or "none").
5. Write the state file (keep `handled`/`declined` from an existing one on a restart).
6. **Start the loop**: `CronCreate` with `cron: "7-59/10 * * * *"`, `recurring: true`,
   `prompt: "/pr-resolver tick <pr-url>"`. Save the id as `cron_id`. On a restart, `CronList`
   first and delete an older job for the same PR so there is only one.
7. Run one pass now (below).
8. Tell the user, in one short block: PR, folder, tickets, "checking every 10 minutes". Also
   say that the loop lives only in this session (closing it stops the loop; run
   `/pr-resolver <pr>` again to pick up where it left off) and ends by itself after 7 days.

## A pass (`tick`)

Read the state file first; if it is missing, do "Start" instead.

1. `$S <repo-dir> <number> > "$(dirname "$STATE")/<number>.pr.json"` and read it.
2. **Merged** (`state == MERGED`) → "Merged" below, then stop.
   **Closed** without merge → `CronDelete`, delete the state file, tell the user, stop.
3. **Collect new feedback**, skipping anything in `handled`:
   - `threads` (unresolved review threads). Skip one whose `last_author` is `me`: it waits for
     the reviewer. A thread that was handled but has a newer reply from the reviewer counts as
     new again (compare `count` with what you saw).
   - `reviews` and `comments` (summary reviews, mostly from review bots). A bot re-posts a full
     review after every push: only read the **newest** one per author, mark older ones handled
     without acting on them. Skip ones with no findings (usage-limit notices, plain approvals).
   - Split each summary into its separate points.
4. **Judge each point.** Use the prefix when there is one (`blocker:`, `major:`, `minor:`,
   `nit:`); otherwise decide yourself from the text and the code:
   - **blocker / major / minor**: a real bug, a security problem, a broken or missing case, or a
     clear request to change the code. → fix it.
   - **nit**: style, naming preference, "consider", praise, discussion that asks for nothing.
     → ignore. No reply.
   - **invalid**: it claims a problem that isn't one (wrong about the code, already handled,
     already fixed, or outside this PR's scope). Check the code before deciding. → reply with
     why and leave it open. Skip it if the same point is already in `declined` (bots repeat
     themselves).
   - **needs the user**: the fix would change what users or hotels see beyond the ticket, money
     or points, personal data, existing data or a migration, the API contract, or needs a
     business choice. → don't fix; add to `waiting_user` and tell the user once. Act on their
     answer in a later pass.
5. **Fix** (only when there is something to fix):
   - `git status --porcelain` must be empty. If the user has uncommitted work there, don't touch
     it: tell the user once and skip fixing this pass.
   - `git fetch origin && git pull --ff-only origin <head>`. If it can't fast-forward, tell the
     user and skip fixing.
   - Make the smallest change that fixes each point, following the repo's conventions and its
     `CLAUDE.md`. Add or update unit tests where the point is a bug.
   - Check: api repo (Go) `gofmt -l`, `go vet` and `go test` on the changed packages; web repo
     `npm run lint` and `npx tsc --noEmit` (and `npm test` if the repo has it). If a check
     fails and you can't fix it, restore your own changes, don't push, and report the point
     to the user.
   - Commit with `commit-message-convention-archi`, then `git push origin HEAD:<head>`.
   - `fix_rounds += 1`. At 5 rounds, stop fixing and ask the user whether to continue: the
     reviewer and the fixes may be going in circles.
6. **Reply** (after the push, so the commit is on GitHub):
   - Fixed thread: reply in the thread, then resolve it. Text:
     `Fixed in <short-sha>: <what changed, one line>.`
     ```bash
     gh api graphql -f id="<thread_id>" -f body="<text>" -f query='mutation($id:ID!,$body:String!){
       addPullRequestReviewThreadReply(input:{pullRequestReviewThreadId:$id,body:$body}){comment{url}}}'
     gh api graphql -f id="<thread_id>" -f query='mutation($id:ID!){
       resolveReviewThread(input:{threadId:$id}){thread{isResolved}}}'
     ```
   - Invalid thread: reply `Not changing this: <why, one or two lines>.` and leave it open.
   - Points from a summary comment: one PR comment (`gh pr comment <n> --body-file ...`) that
     lists each point you acted on: `Fixed in <sha>: ...` or `Not changing: ...`. Leave nits
     out.
7. **CI and conflicts: report only.** If `checks.failing` differs from `reported.ci`, tell the
   user which checks fail. If `mergeable == CONFLICTING` and it wasn't reported yet, tell the
   user. Don't fix either.
8. Add everything you looked at to `handled` (and `declined`), save the state file.
9. **Report.** Nothing new → one line: `PR #<n>: no new feedback (<CI summary>).` Otherwise a
   short list: fixed (with sha), declined (with why), ignored nits (count), waiting on you, CI.

## Merged

1. For each ticket: `get_issue`, then move it to **QA** with `update_issue` (`State: QA`) only
   if its state is `PR Review` or `In Progress`. Already `QA`, `Done` or cancelled → leave it
   and say so. No YouTrack comment.
2. `CronDelete` the loop (`cron_id`; if missing, find it with `CronList`), delete the state
   file.
3. Final report:
   ```
   PR #<n> merged: <title>
   Cards: SLS-<n> → QA (or: left in <state>)
   Fixed: <count> points in <rounds> rounds; declined: <count>; nits ignored: <count>
   Loop stopped.
   ```

## Stop

`/pr-resolver stop <pr>`: `CronDelete` the job, keep the state file (a later start resumes from
it), confirm in one line. YouTrack is not touched.
