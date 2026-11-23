#!/usr/bin/env bash
# =============================================================================
# Git playground: reproduces every demo in docs/github-handbook.md, safely.
#
#   bash scripts/git-playground.sh            # run all scenarios
#   bash scripts/git-playground.sh 2          # run setup + scenario 2 only
#
# No GitHub, no internet, nothing in this project is touched. It builds a
# throwaway folder (/tmp/git-playground) with:
#   github.git  → a "bare" repository that plays the role of GitHub
#   you/        → your laptop's clone
#   alice/      → a teammate's laptop clone
# Commit hashes will differ from the docs (they include time); everything else matches.
# =============================================================================
set -uo pipefail

ROOT="${TMPDIR:-/tmp}/git-playground"
ONLY="${1:-all}"

# Ignore your personal Git config so the output is predictable
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_EDITOR=true          # never open an editor (accept default messages)

h()   { printf '\n\033[1;36m=================== %s ===================\033[0m\n' "$*"; }
say() { printf '\033[0;35m# %s\033[0m\n' "$*"; }
# run <dir> <command...>: print "dir $ command" like a prompt, then run it there
run() { local d="$1"; shift; printf '\033[0;33m%s $ %s\033[0m\n' "$d" "$*"; (cd "$ROOT/$d" && eval "$@"); }
want() { [ "$ONLY" = all ] || [ "$ONLY" = "$1" ]; }

new_clone() {   # new_clone <name> <Display Name>
  git clone -q "$ROOT/github.git" "$ROOT/$1"
  git -C "$ROOT/$1" config user.name "$2"
  git -C "$ROOT/$1" config user.email "$1@example.com"
  git -C "$ROOT/$1" config advice.detachedHead false
}

# ----------------------------------------------------------------------- setup
h "SETUP: a fake GitHub + two laptops"
rm -rf "$ROOT"; mkdir -p "$ROOT"
git init -q --bare -b main "$ROOT/github.git"
new_clone you "You" 2>/dev/null
printf 'Task API\n' > "$ROOT/you/README.md"
printf 'version=1\ncolor=blue\n' > "$ROOT/you/app.txt"
run you 'git add -A && git commit -q -m "Initial commit" && git push -q origin main && git log --oneline'
new_clone alice "Alice"
say "alice cloned the same repo:"
run alice 'git log --oneline'

# ------------------------------------------------------- 1. status/add/commit
if want 1; then
h "1. The basic cycle: edit → status → diff → add → commit → push"
printf 'version=1\ncolor=blue\nsize=large\n' > "$ROOT/you/app.txt"
run you 'git status --short'
run you 'git diff'
run you 'git add app.txt && git status --short'
run you 'git commit -q -m "Add size setting" && git log --oneline'
run you 'git status -sb'
run you 'git push -q origin main && git status -sb'
run alice 'git pull -q --ff-only && git log --oneline'
fi

# ------------------------------------------------------------- 2. fetch vs pull
if want 2; then
h "2. FETCH vs PULL"
say "alice changes the color and pushes"
run alice "sed -i 's/color=blue/color=green/' app.txt && git commit -q -am 'Change color to green' && git push -q origin main"
say "back on YOUR laptop. Git has NOT asked GitHub anything yet:"
run you 'git status -sb'
run you 'cat app.txt'
say "--- git fetch: download news, change NOTHING in your files ---"
run you 'git fetch origin'
run you 'git status -sb'
run you 'git log --oneline --graph --all'
run you 'cat app.txt'
run you 'git diff main origin/main'
say "--- git pull: fetch + update your branch and files ---"
run you 'git pull --ff-only'
run you 'git status -sb'
run you 'cat app.txt'
fi

# ----------------------------------------------- 3. diverged: push is rejected
if want 3; then
h "3. Both pushed? Push rejected → pull --ff-only fails → pull --rebase"
run alice "git pull -q --ff-only; echo 'Docs for the API' > DOCS.md && git add DOCS.md && git commit -q -m 'Add docs' && git push -q origin main"
run you "echo 'MIT' > LICENSE && git add LICENSE && git commit -q -m 'Add license'"
run you 'git push origin main 2>&1'
run you 'git pull --ff-only 2>&1'
run you 'git log --oneline --graph --all'
run you 'git pull --rebase 2>&1'
run you 'git log --oneline --graph --all'
run you 'git push -q origin main && git status -sb'
fi

# ------------------------------------------------------------ 4. merge conflict
if want 4; then
h "4. Merge conflict: both changed the SAME line"
run alice "git pull -q --ff-only; sed -i 's/^version=1/version=2/' app.txt && git commit -q -am 'Bump to version 2' && git push -q origin main"
say "you did NOT pull alice's change; you edit the same line on your old copy"
run you   "sed -i 's/^version=1/version=1.5/' app.txt && git commit -q -am 'Bump to version 1.5'"
run you 'git pull --rebase 2>&1'
run you 'git status --short'
run you 'cat app.txt'
say "resolve: decide the right content, remove the markers, then add + continue"
printf 'version=2\ncolor=green\nsize=large\n' > "$ROOT/you/app.txt"
run you 'cat app.txt'
run you 'git add app.txt && git rebase --continue 2>&1'
run you 'git log --oneline -3'
fi

# ----------------------------------------- 5. branches and the 3 merge styles
if want 5; then
h "5. Feature branch + merge commit vs squash vs rebase"
run you 'git switch -q main && git reset -q --hard origin/main'
run you "git switch -c feature/search && echo 'search=on' >> app.txt && git commit -q -am 'WIP search' && echo 'search_limit=50' >> app.txt && git commit -q -am 'fix typo' && git log --oneline -3"
say "(a) MERGE COMMIT: keeps every commit + adds a merge commit"
run you 'git switch -q main && git switch -q -c try-merge && git merge -q --no-ff -m "Merge feature/search" feature/search && git log --oneline --graph -5'
say "(b) SQUASH: all branch commits become ONE new commit (what we use on GitHub)"
run you 'git switch -q main && git switch -q -c try-squash && git merge -q --squash feature/search && git commit -q -m "Add search (#5)" && git log --oneline --graph -4'
say "(c) REBASE: replay each commit on top, no merge commit"
run you 'git switch -q main && git switch -q -c try-rebase && git rebase -q feature/search && git log --oneline --graph -4'
run you 'git switch -q main'
fi

# ----------------------------------------------------------------- 6. undoing
if want 6; then
h "6. Undo: restore vs reset vs revert"
run you "git switch -q main && git reset -q --hard origin/main"
say "(a) throw away an UNCOMMITTED change to a file"
run you "echo 'oops' >> app.txt && git status --short && git restore app.txt && git status --short && echo '(clean)'"
say "(b) undo a LOCAL commit that was NOT pushed: reset"
run you "echo 'temp' > temp.txt && git add temp.txt && git commit -q -m 'Bad local commit' && git log --oneline -2"
run you 'git reset --soft HEAD~1 && git log --oneline -1 && git status --short'
run you 'git reset -q --hard HEAD && rm -f temp.txt && git status --short && echo "(clean)"'
say "(c) undo a commit that WAS pushed: revert (adds an opposite commit; history stays honest)"
run you "echo 'debug=true' >> app.txt && git commit -q -am 'Enable debug' && git push -q origin main && git log --oneline -2"
run you 'git revert --no-edit HEAD 2>&1 | tail -1 && git log --oneline -3 && git push -q origin main'
run you 'cat app.txt'
fi

# -------------------------------------------------------------------- 7. stash
if want 7; then
h "7. Stash: park unfinished work, switch tasks, come back"
run you "git switch -q main && git pull -q --ff-only; echo 'half-done=yes' >> app.txt && git status --short"
run you 'git stash push -m "half-done feature" && git status --short && echo "(clean: work is parked)"'
run you 'git stash list'
run you 'git stash pop -q && git status --short'
run you 'git restore app.txt'
fi

# ------------------------------------------------------------ 8. tags/releases
if want 8; then
h "8. Tags: mark a release (DevOps uses them for versioned images)"
run you 'git tag -a v1.0.0 -m "First release" && git push -q origin v1.0.0 && git tag -n'
run alice 'git fetch -q --tags && git tag -n && git show --no-patch --format="%h %s" v1.0.0'
fi

# ------------------------------------------------------- 9. investigate history
if want 9; then
h "9. Who changed what, and when?"
run you 'git log --oneline -- app.txt'
run you 'git blame app.txt'
run you 'git show --stat --format="%h %an: %s" HEAD~1'
fi

h "DONE. Playground left in $ROOT; explore it, or delete it with: rm -rf $ROOT"
