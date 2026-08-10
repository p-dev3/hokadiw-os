#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

readonly REPO="https://github.com/p-dev3/hokadiw-os.git"

pkg install -y git

git init 2>/dev/null || true
git branch -M main

if git remote get-url origin >/dev/null 2>&1; then
    git remote set-url origin "$REPO"
else
    git remote add origin "$REPO"
fi

if ! git config user.name >/dev/null; then
    git config user.name "HOKADIW Builder"
fi
if ! git config user.email >/dev/null; then
    git config user.email "hokadiw@users.noreply.github.com"
fi

git add .
if ! git diff --cached --quiet; then
    git commit -m "Bootstrap HOKADIW Terminal distribution v0.1.1"
fi
git push -u origin main
