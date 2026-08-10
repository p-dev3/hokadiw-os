#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

REPO_URL="https://github.com/p-dev3/hokadiw-os-toolkit.git"

if ! command -v git >/dev/null 2>&1; then
  pkg install -y git
fi

if [ ! -d .git ]; then
  git init
fi

git branch -M main

if git remote get-url origin >/dev/null 2>&1; then
  git remote set-url origin "$REPO_URL"
else
  git remote add origin "$REPO_URL"
fi

git add .
if ! git diff --cached --quiet; then
  git commit -m "Add HOKADIW Termux Edition Phase 1"
fi

git push -u origin main

echo "Pushed to $REPO_URL"
