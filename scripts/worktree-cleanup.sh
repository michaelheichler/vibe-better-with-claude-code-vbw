#!/bin/bash
set -u

if [ "${1:-}" = "" ] || [ "${2:-}" = "" ]; then
  exit 0
fi

PHASE="$1"
PLAN="$2"

PLANNING_DIR="${VBW_PLANNING_DIR:-.vbw-planning}"
WORKTREES_PARENT=".vbw-worktrees"
WORKTREE_DIR="${WORKTREES_PARENT}/${PHASE}-${PLAN}"
BRANCH="vbw/${PHASE}-${PLAN}"
AGENT_WORKTREES_DIR="$PLANNING_DIR/.agent-worktrees"

git worktree unlock "$WORKTREE_DIR" 2>/dev/null || true

git worktree remove "$WORKTREE_DIR" --force 2>/dev/null || true

rm -rf "$WORKTREE_DIR" 2>/dev/null || true

git worktree prune 2>/dev/null || true

GIT_DIR="$(git rev-parse --git-dir 2>/dev/null)" || true
if [ -n "${GIT_DIR:-}" ] && [ -d "$GIT_DIR/worktrees" ]; then
  WORKTREE_ABS="$(cd "$(dirname "$WORKTREE_DIR")" 2>/dev/null && pwd)/$(basename "$WORKTREE_DIR")" 2>/dev/null || true
  if [ -n "${WORKTREE_ABS:-}" ]; then
    for admin_dir in "$GIT_DIR/worktrees"/*/; do
      [ -d "$admin_dir" ] || continue
      gitdir_file="${admin_dir}gitdir"
      [ -f "$gitdir_file" ] || continue
      recorded="$(cat "$gitdir_file" 2>/dev/null)" || continue
      recorded_wt="${recorded%/.git}"
      recorded_wt_abs="$(cd "$recorded_wt" 2>/dev/null && pwd)" 2>/dev/null || recorded_wt_abs=""
      if [ "$recorded_wt_abs" = "$WORKTREE_ABS" ] || [ "$recorded_wt" = "$WORKTREE_DIR" ]; then
        rm -rf "$admin_dir" 2>/dev/null || true
      fi
    done
  fi
fi

for entry in "$WORKTREES_PARENT"/.*; do
  case "$(basename "$entry")" in .|..) continue ;; esac
  rm -rf "$entry" 2>/dev/null || true
done
rmdir "$WORKTREES_PARENT" 2>/dev/null || true

git branch -d "$BRANCH" 2>/dev/null || true

if [ -d "$AGENT_WORKTREES_DIR" ]; then
  for f in "$AGENT_WORKTREES_DIR"/*"${PHASE}-${PLAN}"*.json; do
    [ -f "$f" ] && rm -f "$f" 2>/dev/null || true
  done
fi

exit 0
