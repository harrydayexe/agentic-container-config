# Agentic Container Config

Add this to `.zshrc` for ease of use:

```
# Agentic Workflow
export DOCKER_CLI_HINTS=false

AGENTIC_WS=~/Developer/agentic/workspace
AGENTIC_CFG=~/Developer/agentic/config/.devcontainer/devcontainer.json

agentic-token() {
  security find-generic-password -a "$USER" -s agentic-gh-token -w 2>/dev/null \
    || { print -u2 "agentic: token not in keychain"; return 1; }
}

agentic-up() {
  AGENTIC_GH_TOKEN="$(agentic-token)" || return
  devcontainer up \
    --workspace-folder "$AGENTIC_WS" \
    --config "$AGENTIC_CFG" \
    "$@" \
    || { print -u2 "agentic: setup failed — container NOT firewalled"; return 1; }
}

agentic-down() {
  local ids
  ids=$(docker ps -aq --filter label=devcontainer.local_folder="$AGENTIC_WS")
  if [ -z "$ids" ]; then
    print "agentic: nothing running"
    return 0
  fi
  docker rm -f ${=ids}
}

agentic() {
  AGENTIC_GH_TOKEN="$(agentic-token)" || return
  if [ $# -eq 0 ]; then
    devcontainer exec --workspace-folder "$AGENTIC_WS" --config "$AGENTIC_CFG" zsh
  else
    devcontainer exec --workspace-folder "$AGENTIC_WS" --config "$AGENTIC_CFG" "$@"
  fi
}
```

Assumes that the PAT to connect to GitHub is stored in keychain at `agentic-gh-token`
