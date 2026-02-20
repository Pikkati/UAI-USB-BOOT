#!/usr/bin/env bash
set -euo pipefail

git fetch --prune origin
merged=$(git branch -r --merged origin/main \
  | grep -vE 'origin/(main|HEAD|gh-pages)' \
  | sed 's#origin/##')

if [ -n "$merged" ]; then
  for br in $merged; do
    echo "Deleting remote branch: $br"
    gh api --method DELETE "/repos/${GITHUB_REPOSITORY}/git/refs/heads/$br" || true
  done
else
  echo "No merged branches to delete."
fi

git remote prune origin
for lb in $(git branch --merged main | egrep -v "\*|main"); do
  git branch -d "$lb" || true
done
