#!/bin/sh
# A minimal end to end demo of the engine, without a Te distribution.
#
# It makes a tiny repository, lets an "agent" change a line in a worktree, and
# publishes two rounds with the stand-in for latexmk. The second round shows
# the change on the page, with the source it comes from.
#
# Run it from the root of the project, after `moon build --target native`:
#
#     sh examples/demo.sh

set -eu

HERE=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BIN="$HERE/_build/native/debug/build/cmd/main/main.exe"

if [ ! -x "$BIN" ]; then
  echo "build the tool first: moon build --target native" >&2
  exit 1
fi

# The stand-in for latexmk typesets the document without a Te distribution.
export PATH="$HERE/examples/fake-latexmk:$PATH"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK" "$WORK-tasks"' EXIT

cd "$WORK"
git init -q
git config user.email demo@example.com
git config user.name Demo
printf '\\section{Hello}\nThe quick brown fox.\n' > main.tex
git add .
git commit -qm "the initial document"

echo "== round 1: nothing has changed =="
"$BIN" publish --repo "$WORK" --task demo --round 1

echo
echo "== the agent changes a line in the worktree =="
printf '\\section{Hello}\nThe quick red fox.\n' > "$WORK-tasks/demo/main.tex"

echo
echo "== round 2: the change appears on the page =="
"$BIN" publish --repo "$WORK" --task demo --round 2
