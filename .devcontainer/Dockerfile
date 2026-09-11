FROM mcr.microsoft.com/devcontainers/base:ubuntu

RUN apt-get update && apt-get install -y --no-install-recommends \
      iptables ipset dnsutils jq ripgrep vim \
    && rm -rf /var/lib/apt/lists/*

# Organization-style policy the agent cannot override from repo files
RUN mkdir -p /etc/claude-code
COPY managed-settings.json /etc/claude-code/managed-settings.json

# Egress firewall, runnable by the non-root user at container start
COPY agentic-firewall.sh /usr/local/bin/agentic-firewall.sh
RUN chmod +x /usr/local/bin/agentic-firewall.sh \
 && echo "vscode ALL=(root) NOPASSWD: /usr/local/bin/agentic-firewall.sh" \
      > /etc/sudoers.d/agentic-firewall
