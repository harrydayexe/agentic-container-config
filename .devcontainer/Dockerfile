FROM mcr.microsoft.com/devcontainers/base:ubuntu

RUN apt-get update && apt-get install -y --no-install-recommends \
      iptables squid dnsutils jq ripgrep vim just \
    && rm -rf /var/lib/apt/lists/*

# Organization-style policy the agent cannot override from repo files
RUN mkdir -p /etc/claude-code
COPY managed-settings.json /etc/claude-code/managed-settings.json

# Egress allowlist. Root-owned and read-only to the agent: the sandbox is only
# as good as this file, so `vscode` must not be able to edit it.
COPY --chown=root:root --chmod=444 squid.conf /etc/squid/squid.conf

# Network sandbox setup, runnable by the non-root user at container start.
# The script is root-owned and not writable by `vscode`, so the sudoers entry
# only ever runs this exact content.
COPY --chown=root:root --chmod=555 agentic-netsetup.sh /usr/local/bin/agentic-netsetup.sh
COPY --chown=root:root --chmod=555 agentic-entrypoint.sh /usr/local/bin/agentic-entrypoint.sh
RUN echo "vscode ALL=(root) NOPASSWD: /usr/local/bin/agentic-netsetup.sh" \
      > /etc/sudoers.d/agentic-netsetup \
 && chmod 440 /etc/sudoers.d/agentic-netsetup

# The sandbox runs from the entrypoint, not from devcontainer lifecycle hooks:
# hooks are skipped by `docker start` and by an interrupted `devcontainer up`,
# which would leave the container running with unrestricted network access.
# Requires "overrideCommand": false in devcontainer.json to survive.
ENTRYPOINT ["/usr/local/bin/agentic-entrypoint.sh"]
CMD ["sleep", "infinity"]
