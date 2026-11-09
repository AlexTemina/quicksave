#!/bin/sh
# Launch Claude Code for Quicksave with a clean profile: no global CLAUDE.md, user skills, plugins or old memory.
set -eu
REPO="$(cd "$(dirname "$0")/.." && pwd)"
export CLAUDE_CONFIG_DIR="$HOME/.claude-quicksave"
slug=$(printf '%s' "$REPO" | sed 's#[/.]#-#g')
mem="$CLAUDE_CONFIG_DIR/projects/$slug/memory"
mkdir -p "$(dirname "$mem")"
if [ ! -L "$mem" ]; then
  [ -e "$mem" ] && { echo "$mem exists and is not a symlink, move it first" >&2; exit 1; }
  ln -s "$REPO/memory" "$mem"
fi
cd "$REPO"
# The repo sits under $HOME, so ~/.claude/CLAUDE.md loads as an ancestor file, and the org syncs its plugins into every profile.
settings=$(cat <<EOF
{
  "claudeMdExcludes": ["$HOME/.claude/CLAUDE.md"],
  "enabledPlugins": {
    "alan-skills@synced": false,
    "alan-spain@synced": false,
    "alan-growth-product@synced": false
  }
}
EOF
)
exec claude --settings "$settings" "$@"
