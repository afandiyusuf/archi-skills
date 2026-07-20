---
name: commit-message-convention-archi
description: Use whenever drafting or writing a git commit message, commit title, or PR title in any repository — including when the user asks to "commit", "git commit", "write a commit message", or when running `git commit -m`. Applies the Conventional Commits format (type(scope): description) and atomic-commit splitting used across all repos, so history stays readable, changelog-generatable, and semver-friendly. Always apply this automatically before finalizing a commit; don't wait for the user to ask for it by name.
---

# Commit Message Convention

All repositories use [Conventional Commits](https://www.conventionalcommits.org/) format.
This enables automated changelog generation, semantic versioning, and keeps git history
readable and searchable. Apply this format any time you are about to create a commit —
proactively, without being asked to follow "the convention" by name.

## IMPORTANT — Never leave AI attribution in commits

**Never** add any trace of Claude, Anthropic, or AI assistance to a commit. This applies to
every commit created via this convention, no exceptions:

- Do **not** add `Co-Authored-By: Claude ...` (or any AI tool) trailers.
- Do **not** add `Generated with Claude Code` or similar footers/links.
- Do **not** mention Claude, AI, or the assistant anywhere in the subject, body, or footer.
- The commit must read exactly as if the human author wrote it themselves.

If a default workflow, template, or tool tries to auto-insert an AI co-author trailer, strip
it before committing.

## Atomic Commits

Each commit must represent exactly **one** logical, self-contained change. Before running
`git commit`, inspect the staged/pending diff:

- If it spans multiple unrelated concerns (e.g. a bug fix + a refactor, or changes across
  several unrelated features/modules), **split it into multiple commits** — one per concern
  — each staged and committed separately with its own Conventional Commits message.
- A commit is atomic if it could be reverted on its own without breaking unrelated
  functionality, and if it fits under a single `type(scope)` without stretching the scope to
  cover unrelated files.
- Touching many files is fine as long as they all serve one logical change (e.g. renaming a
  function used in 20 files is still one atomic `refactor:` commit). The split trigger is
  *unrelated concerns*, not *file count*.
- When splitting, use `git add <specific files>` (never a blanket `git add -A`/`git add .`)
  to stage only the files belonging to that logical change, commit, then repeat for the next
  group.
- If it's ambiguous whether two changes are related enough to share a commit, ask the user
  rather than guessing.

### Core changes vs. test changes are always separate commits

Never mix production/implementation code with test code in the same commit, even when the
test exists solely to cover that implementation change:

- Commit the core change first (`feat:`, `fix:`, `refactor:`, etc.) with only the
  non-test files staged.
- Commit the accompanying tests separately with `test:` (e.g. `test(precheckin): add
  coverage for term-and-condition usecase`), staged on top of the core commit.
- This holds even for a tight fix+test pairing — two commits, not one — so `git bisect` and
  changelog generation can tell "behavior changed" apart from "coverage added."
- Exception: a file that is *itself* test infrastructure with no separate "core" counterpart
  (e.g. adding a new test fixture/helper with no production code change) is just a `test:`
  or `chore:` commit on its own — there's nothing to separate it from.

### When the workspace has too many changes to split confidently

If the pending diff is large, touches many unrelated-looking files, or you can't confidently
tell where one logical change ends and the next begins (so you can't determine how many
atomic commits are needed), **stop and ask the user** what they were working on before
proposing a split. Specifically ask them to describe the sequence of work (e.g. "first I did
X, then Y, then added tests for Z") so you have a concrete reference for how many commits to
make and what belongs in each. Do not guess a grouping and commit it just to make progress —
an incorrectly split history is harder to undo than pausing to ask.

## Format

```
type(scope): description
                          <-- blank line
[optional body]
                          <-- blank line
[optional footer(s)]
```

## Rules

- **Subject line**: max 72 characters, lowercase, no period at the end.
- **Body**: optional, explains *why* not *what*, wrapped at 72 characters.
- **Footer**: references task management tickets, breaking changes (e.g. `BREAKING CHANGE: ...`).

## Commit Types

| Type | When to Use | Bumps |
|---|---|---|
| `feat` | New feature or capability | MINOR |
| `fix` | Bug fix | PATCH |
| `docs` | Documentation only | — |
| `style` | Formatting, whitespace (no logic change) | — |
| `refactor` | Code restructuring (no feature/fix) | — |
| `perf` | Performance improvement | PATCH |
| `test` | Adding or updating tests | — |
| `build` | Build system or dependency changes | — |
| `ci` | CI/CD pipeline changes | — |
| `chore` | Maintenance tasks (no production code) | — |
| `revert` | Reverts a previous commit | — |

## When Types Overlap

Some changes fit more than one type. Apply these rules of thumb:

- **Performance regression fix → `fix:`, not `perf:`** — The symptom is a bug; `perf:` is
  for intentional optimisations.
  ```
  fix(api): resolve N+1 query causing slow room search response
  ```
- **Formatter or linter config change → `chore:`, not `style:`** — `style:` is for manually
  reformatting code itself. Touching `.eslintrc`, `.prettierrc`, or similar tooling is
  maintenance work.
  ```
  chore(config): enable prettier trailing-comma rule
  ```
- **Refactor that also fixes a bug → `fix:`** — The fix takes priority. Ideally split the
  refactor and the fix into separate commits (see Atomic Commits above) — this is the
  canonical case that split applies to. If they are truly inseparable, use the
  higher-impact type.
  ```
  fix(booking): correct availability overlap logic during service extract
  ```
- **Test restructuring → `refactor:`, not `test:`** — `test:` is for adding or updating test
  cases. Reorganising test helpers, extracting fixtures, or splitting test files is
  structural work.
  ```
  refactor(tests): extract shared booking fixtures into helpers module
  ```
- **Dependency update that patches a vulnerability → `fix:` with scope `deps`** — A security
  patch is a bug fix, not routine maintenance.
  ```
  fix(deps): update lodash to patch prototype pollution vulnerability
  ```

## Scope

The scope identifies the module or area affected. Use lowercase, kebab-case, and infer it
from the primary directory/module touched by the change (e.g. a Go feature package, a
frontend component folder).

```
feat(api): add booking availability endpoint
fix(auth): handle expired refresh tokens
docs(readme): update local setup instructions
refactor(booking-service): extract validation logic
ci(github-actions): add staging deploy workflow
```

Common scopes: `api`, `auth`, `booking`, `ui`, `db`, `lambda`, `s3`, `config`, `deps`. When a
repo has its own established scope names (e.g. a feature directory name), prefer those over
these generic examples.

## GPG signing timeout

If `git commit` fails with a GPG signing error (e.g. `gpg failed to sign the data` /
`gpg: signing failed: Timeout`), do **not** retry the same command in a loop — pinentry needs
an interactive unlock (passphrase/biometric) that a background shell command cannot satisfy.

Instead:

1. Stage exactly the files for that logical commit (per Atomic Commits above) — do this part
   yourself so the user doesn't have to re-derive the grouping.
2. Stop and tell the user the commit message you determined (subject + body + footer, fully
   written out, ready to paste), and ask them to run the commit themselves once they've
   unlocked their GPG session (e.g. via a manual `git commit -S` prompt or `gpgconf
   --reload gpg-agent` after entering their passphrase interactively).
3. Do not fall back to `--no-gpg-sign` or otherwise bypass signing to work around this —
   that changes the repo's commit signing guarantees and is not yours to decide.
4. If there are multiple planned commits (core + test), only hand off the first one this way;
   after the user confirms their GPG session is unlocked, continue with the remaining commits
   normally.

## Applying this when drafting a commit

1. Review the full diff of pending changes and group changed hunks/files by logical concern
   (see Atomic Commits above), keeping test files in their own group separate from the core
   change(s) they cover. If you can't confidently form these groups because the diff is too
   large or tangled, ask the user for a reference first (see "too many changes to split
   confidently" above) instead of guessing.
2. For each group, determine the `type` from what that group's diff actually does — not from
   how the user phrased the request. Test-only groups always use `test:`.
3. Pick a `scope` from the primary module/feature/directory touched by that group.
4. Write the subject in lowercase, imperative mood, ≤ 72 characters, no trailing period.
5. Only add a body when the *why* isn't obvious from the subject line and diff alone.
6. Add a footer only when there's a ticket reference or a breaking change to call out.
7. Stage only that group's files and commit before moving to the next group. Order core
   commits before their corresponding test commits.
