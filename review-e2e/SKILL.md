---
name: review-e2e
description: Use when the user says "review e2e", "jalankan e2e", "cek e2e", "run e2e test", or asks to review/check E2E test results for this project. Runs `make bruno-e2e` (the Bruno collection under docs/bruno/membership-sentec-bruno/E2E Tests), triages any failures based on whether Claude made recent related code changes, and flags missing test coverage for newly built features.
---

# Review E2E

Runs the project's Bruno E2E collection and triages the result. Never silently "fix" a
failure by guessing — the branch point below (recent-work vs. no-recent-work) decides
whether the test or the app code is wrong, and that call is often ambiguous enough to need
the user.

## Step 1 — Run the suite

```bash
make bruno-e2e
```

This runs `bru run "E2E Tests" -r --env-file environments/local.secrets.bru` against
`docs/bruno/membership-sentec-bruno/E2E Tests`. If it fails immediately because
`environments/local.secrets.bru` is missing, tell the user to copy
`environments/local.secrets.bru.example` and fill in real values — don't create that file
with guessed/fake secrets yourself.

Read the full output, not just the pass/fail summary line — capture which named requests
failed and the actual assertion diffs (expected vs. actual) for each.

## Step 2 — All green

If every test passes, report that and stop. No further action needed.

## Step 3 — Triage failures

For each failing test, first work out whether you (in this session, or per recent git
history/diff) have just been working on the feature/endpoint that test exercises:

```bash
git status
git diff
git log --oneline -10
```

Cross-reference the failing `.bru` request's endpoint/feature area (e.g. its folder, the
handler/usecase it hits) against files you've recently edited or that show as
modified/staged.

### Case A — You just worked on that feature

If the failure is in an area you (this session) just implemented or changed, the most
likely explanation is that the API's behavior intentionally changed and the E2E
test's request/assertions are now stale. **Fix the E2E test** (the `.bru` file's body,
params, or `tests`/`assert` block under `docs/bruno/membership-sentec-bruno/E2E Tests/`) to
match the new, intended behavior — then re-run `make bruno-e2e` to confirm it's green.

Do not silently patch the application code back to the old behavior just to make an old
assertion pass — the code change was deliberate. If while updating the test you find the
actual behavior looks like a genuine regression (not the change you intended), stop and
tell the user instead of guessing.

### Case B — You did not just work on that area

If the failing test covers code you haven't touched (no recent related diff/history), do
**not** guess whether the test or the application is wrong. Stop and ask the user directly,
showing them the expected-vs-actual diff, with a question along these lines:

> This E2E test (`<test name>`) is failing and I haven't touched `<area>` recently. Should I
> update the test's expectations, or is this a real regression in the app code that needs a
> fix?

Wait for their answer before editing either the test or the application code.

## Step 4 — Check for missing coverage on new features

Independent of whether Step 3 found failures: if you have recently implemented a new
feature/endpoint/case in this session (or per recent git history) and there is **no**
corresponding request in `docs/bruno/membership-sentec-bruno/E2E Tests/`, do not add one
silently. Ask the user whether they want that case added to the E2E group, e.g.:

> I don't see an E2E case for the `<feature>` you just added. Want me to add one to
> `E2E Tests`?

Only create the new `.bru` file after they confirm. When you do add it, follow the existing
naming convention in that folder — a leading number matching call order in the flow, with
`-A`/`-B`/`-C` suffixes for variant/edge-case requests on the same step (e.g. `27 Stay -
Submit Pre-Checkin.bru`, `27-A Stay - Submit Pre-Checkin Vehicle Data Incomplete.bru`).
