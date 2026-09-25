---
name: setup-worktree
description: Use when the user says "setup new worktree", "setup worktree", "new task folder", "remove worktree", "delete task folder", or wants to work on an SLS task in its own folder so other agents can keep working elsewhere. Copies ~/Documents/Workspace/sls/staging/ (sentec-loyalty-system-api + sentec-loyalty-system-web, secrets included) into ~/Documents/Workspace/sls/<task>/, branches each repo from its YouTrack ticket, and later removes the folder safely.
---

# Setup worktree (SLS task folders)

One folder per task, so several agents can work at the same time without touching each
other's files. Each task folder is a full copy of `staging/`, including secrets,
`vendor/` and `node_modules/`, so it runs right away.

```
~/Documents/Workspace/sls/
├── staging/                          ← always on the staging branch; the user edits secrets here only
│   ├── Makefile
│   ├── sentec-loyalty-system-api/
│   └── sentec-loyalty-system-web/
└── sls-785-sls-797/                  ← task folder = copy of staging/
    ├── Makefile                      ← make up / api / web / down / logs / status / sync-secrets
    ├── local.mk                      ← only when the CMS should use the staging API
    ├── sentec-loyalty-system-api/    ← feature/SLS-785-...
    └── sentec-loyalty-system-web/    ← feature/SLS-797-...
```

Scripts live next to this file in `scripts/`. `SKILL=~/.claude/skills/setup-worktree` below.

## Setup new worktree

### 1. Check staging/ exists

If `~/Documents/Workspace/sls/staging` does not exist, tell the user it is a one-time
bootstrap (fresh clones + secrets copied from `~/Documents/Workspace/sentec-loyalty-system-api`
and `-web` + `go mod vendor` + `npm ci`), ask for a go-ahead, then run
`$SKILL/scripts/bootstrap.sh`. It never overwrites an existing `staging/`.

### 2. Work out the tickets

From the request, find which ticket belongs to which repo:
- API only: `api SLS-785`
- CMS only: `web SLS-797` (or "cms")
- Both, different tickets: `api SLS-785 web SLS-797`
- Both, same ticket: `SLS-785 for both`

If it is not clear which repo a ticket is for, ask. Do not guess.

Also note whether the user said the CMS should use the **staging** API. Default is local.

### 3. Build the names

For each ticket, read it from YouTrack (`mcp__youtrack__get_issue`) for its summary and type.

- **Branch:** `<prefix>/SLS-<n>-<slug>`
  - prefix: `fix` when the ticket type is Bug, otherwise `feature`
  - slug: kebab-case from the summary, lowercase ASCII, 3–6 meaningful words, at most ~40 chars
  - example: `feature/SLS-797-mobile-app-branding-cms`
- **Task folder:** lowercase ticket numbers, API ticket first:
  - two tickets → `sls-785-sls-797`
  - one ticket (one repo, or the same for both) → `sls-785`

### 4. Create it

```bash
$SKILL/scripts/new-task.sh <task-folder> [--api <branch>] [--web <branch>] [--web-api staging]
```

- Pass only the repos that belong to the task. The other repo is still copied but stays on
  `staging`. That is intended: the folder must be complete so it can run.
- The script pulls `origin/staging` into `staging/` first (fast-forward only, re-vendors /
  `npm ci` there if dependency files changed), then does `cp -a staging/ <task>/`, and then branches.
- It stops if `staging/` is dirty, not on `staging`, or the task folder already exists.
  Report the error to the user; do not "fix" `staging/` yourself.

### 5. Report and switch

Tell the user:
- the folder path and the branch of each repo
- which API the CMS uses
- how to run it: `cd <folder> && make up` (or `make api`, `make web`, `make web API=staging`)

Then do all work for this task **inside that folder** (absolute paths under
`~/Documents/Workspace/sls/<task>/`). Never edit files in `staging/` or in another task folder.

## Rules while working in a task folder

- **Never run the stack yourself.** `make up`, `make api`, `make web`, `docker compose up`,
  `go run`, `npm run dev` all use shared ports (8081, 5173) and the shared staging database.
  Only one session can test at a time. When something needs a local check, ask the user to
  run it and tell them the exact command. Unit tests (`go test ./...`, `npm test`) are fine.
- **Never commit on `staging`.** A repo not in the task stays on `staging`; do not change it.
  If the task turns out to need that repo, create its branch first (same naming rule) and tell the user.
- **Secrets / ignored files** (`config.json`, `scripts/config.json`, `local.secrets.bru`, web `.env`)
  are edited by the user in `staging/` only. If a task folder needs the new values, ask the user
  to run `make sync-secrets` (old files are kept as `*.~N~`). Do not edit secrets in a task folder
  unless the user asks.
- PRs go to `staging` using the `pr-staging` skill, run from inside the repo in the task folder.

## Remove worktree

When the user asks to remove or clean up a task folder:

1. Run the report (deletes nothing):
   ```bash
   $SKILL/scripts/remove-task.sh <task-folder>
   ```
   It blocks when a repo has uncommitted changes, has commits not on GitHub (a squash-merged PR
   whose HEAD matches counts as safe), or the folder's API / CMS is still running.
2. Show the user the report. If blocked, stop and explain what would be lost. Never work
   around a block (no stash, reset, or force delete) unless the user tells you exactly that.
3. If safe, ask for an explicit yes, then run it again with `--yes`.

`staging/` can never be removed by this script.

## Other commands

- List task folders: `ls ~/Documents/Workspace/sls/`, and `make -C <folder> status` for branches and port owners.
- Refresh `staging/` without making a task: `git -C ~/Documents/Workspace/sls/staging/<repo> pull --ff-only origin staging`.
