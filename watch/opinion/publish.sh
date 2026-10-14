#!/bin/sh
# Publish the Polls snapshot for the Windows build: export the API to static
# JSON, then force-push it as a single commit to the public `polls-data`
# branch (read from raw.githubusercontent.com). Skips the push when nothing
# changed. Run after the daily opinion fetch.
set -eu
DATA=${PARTAKE_DATA:-$HOME/.local/share/partake-watch}
OUT=$DATA/polls-snapshot
REPO=$DATA/polls-data.git
REMOTE=${PARTAKE_SNAPSHOT_REMOTE:-https://github.com/noamvb/ParTake.git}
BRANCH=polls-data

python3 -m watch.opinion.export --api http://127.0.0.1:8798 --out "$OUT"

[ -d "$REPO" ] || git init -q --bare "$REPO"
export GIT_DIR="$REPO" GIT_WORK_TREE="$OUT"
export GIT_AUTHOR_NAME="ParTake Deck" GIT_AUTHOR_EMAIL="partake-deck@users.noreply.github.com"
export GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME" GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"
rm -f "$REPO/index"
git add -A
tree=$(git write-tree)
remote_tree=$(git ls-remote "$REMOTE" "refs/heads/$BRANCH" | cut -f1)
if [ -n "$remote_tree" ] && git fetch -q --depth 1 "$REMOTE" "$BRANCH" 2>/dev/null \
   && [ "$(git rev-parse FETCH_HEAD^{tree})" = "$tree" ]; then
  echo "polls snapshot unchanged"
  exit 0
fi
commit=$(echo "Polls snapshot $(date -u +%Y-%m-%dT%H:%MZ)" | git commit-tree "$tree")
git push -q --force "$REMOTE" "$commit:refs/heads/$BRANCH"
echo "published polls snapshot $commit"
