#!/usr/bin/env bash
# Print a PR's review state as JSON, for the pr-resolver skill.
#
# Usage: pr-state.sh <repo-dir> <pr-number>
#
# Output:
#   { number, url, state, merged_at, base, head, author, me, reviewDecision, mergeable,
#     checks: {pass, fail, pending, failing: [names]},
#     threads:  [ {thread_id, path, line, outdated, url, author, body, severity,
#                  last_author, last_body, count} ],        # unresolved review threads
#     reviews:  [ {url, author, state, body, severity} ],     # review summaries with text
#     comments: [ {url, author, body, severity} ] }           # PR conversation comments
#
# severity comes from a text prefix (blocker | major | minor | nit), else "unmarked".
# `me` is the gh login running this; comments by `me` are left out of reviews/comments.
set -euo pipefail

[[ $# -eq 2 ]] || { echo "usage: pr-state.sh <repo-dir> <pr-number>" >&2; exit 1; }
cd "$1"
PR="$2"

nwo="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"
me="$(gh api user --jq .login)"

gh api graphql -F owner="${nwo%/*}" -F name="${nwo#*/}" -F pr="$PR" -f query='
query($owner:String!,$name:String!,$pr:Int!){
  repository(owner:$owner,name:$name){
    pullRequest(number:$pr){
      number url state mergedAt baseRefName headRefName reviewDecision mergeable
      author{login}
      commits(last:1){ nodes{ commit{ statusCheckRollup{ contexts(first:100){ nodes{
        __typename
        ... on CheckRun{ name conclusion status }
        ... on StatusContext{ context state }
      }}}}}}
      reviewThreads(first:100){ nodes{
        id isResolved isOutdated path line
        first: comments(first:1){ totalCount nodes{ author{login} body url } }
        last:  comments(last:1){ nodes{ author{login} body } }
      }}
      reviews(last:50){ nodes{ author{login} state body url } }
      comments(last:50){ nodes{ author{login} body url } }
    }
  }
}' | jq --arg me "$me" '
  def sev: (ascii_downcase | capture("^[^a-z]*(?<s>blocker|major|minor|nit)\\b").s) // "unmarked";
  def st: (.conclusion // .state);
  .data.repository.pullRequest as $p
  | ($p.commits.nodes[0].commit.statusCheckRollup.contexts.nodes // []) as $c
  | {
      number: $p.number, url: $p.url, state: $p.state, merged_at: $p.mergedAt,
      base: $p.baseRefName, head: $p.headRefName, author: $p.author.login, me: $me,
      reviewDecision: $p.reviewDecision, mergeable: $p.mergeable,
      checks: {
        pass:    [$c[] | select(st as $x | $x=="SUCCESS" or $x=="NEUTRAL" or $x=="SKIPPED")] | length,
        fail:    [$c[] | select(st as $x | $x=="FAILURE" or $x=="ERROR" or $x=="TIMED_OUT" or $x=="CANCELLED" or $x=="ACTION_REQUIRED")] | length,
        pending: [$c[] | select(st as $x | $x==null or $x=="PENDING" or $x=="EXPECTED" or $x=="IN_PROGRESS" or $x=="QUEUED")] | length,
        failing: [$c[] | select(st as $x | $x=="FAILURE" or $x=="ERROR" or $x=="TIMED_OUT" or $x=="CANCELLED" or $x=="ACTION_REQUIRED") | (.name // .context)]
      },
      threads: [ $p.reviewThreads.nodes[] | select(.isResolved | not)
                 | .first.nodes[0] as $f | .last.nodes[0] as $l
                 | {thread_id: .id, path, line, outdated: .isOutdated, url: $f.url,
                    author: $f.author.login, body: $f.body, severity: ($f.body | sev),
                    last_author: $l.author.login, last_body: $l.body, count: .first.totalCount} ],
      reviews:  [ $p.reviews.nodes[] | select((.body // "") != "" and .author.login != $me)
                  | {url, author: .author.login, state, body, severity: (.body | sev)} ],
      comments: [ $p.comments.nodes[] | select(.author.login != $me)
                  | {url, author: .author.login, body, severity: (.body | sev)} ]
    }'
