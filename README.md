# Agentic Container Config

For a more in-depth look at how this setup works, check out my blog:

https://harryday.dev/blog/posts/forbidden-fruit-autonomous-agents

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
  local -x AGENTIC_GH_TOKEN
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
  local -x AGENTIC_GH_TOKEN
  AGENTIC_GH_TOKEN="$(agentic-token)" || return
  if [ $# -eq 0 ]; then
    devcontainer exec --workspace-folder "$AGENTIC_WS" --config "$AGENTIC_CFG" zsh
  else
    devcontainer exec --workspace-folder "$AGENTIC_WS" --config "$AGENTIC_CFG" "$@"
  fi
}

```

Assumes that the PAT to connect to GitHub is stored in keychain at `agentic-gh-token`

## Networking

The container egresses through a loopback-only Squid proxy that allowlists by
hostname. Two layers:

- **Kernel** (`agentic-netsetup.sh`) — `OUTPUT` policy `DROP`. Only the `proxy`
  uid may reach ports 80/443 or resolve DNS. Nothing the agent runs has a route
  to the internet, so unsetting `HTTPS_PROXY` removes its network access rather
  than bypassing the policy.
- **Proxy** (`squid.conf`) — the domain allowlist, plus an access log at
  `/var/log/squid/access.log` recording every request the agent made.

Allowlisting by hostname rather than by resolved IP is what makes package
managers work: `proxy.golang.org` and friends sit behind rotating CDN
addresses, so the old approach of pinning `dig` output at container start went
stale and broke `go mod download`.

**To allow a new host**, add it to `acl allowed_domains` in
`.devcontainer/squid.conf` and rebuild. A leading dot covers subdomains.

The Go module cache lives in the `agentic-go-mod` Docker volume — isolated from
the host cache and persistent across rebuilds. To reset it:

```
agentic-down && docker volume rm agentic-go-mod
```
