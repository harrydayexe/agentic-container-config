#!/bin/bash
# Bring up the container's network sandbox: start the allowlisting proxy, then
# lock the kernel down so the proxy is the only process that can reach out.
#
# Idempotent — runs on container create and again on every start, because
# iptables rules do not survive a stop/start.
set -euo pipefail
IFS=$'\n\t'

PROXY_USER=proxy
PROXY_UID="$(id -u "$PROXY_USER")"
GO_MOD_CACHE=/home/vscode/go/pkg/mod

# ---------------------------------------------------------------------------
# 0. Named-volume ownership
# ---------------------------------------------------------------------------
# A fresh Docker volume mounts root-owned; without this `go mod download`
# cannot write to its own cache. Only touch it when the ownership is actually
# wrong — a recursive chown over a populated cache is slow, and this runs on
# every container start.
if [ -d "$GO_MOD_CACHE" ] && [ "$(stat -c '%U' "$GO_MOD_CACHE")" != "vscode" ]; then
    echo "Fixing ownership of $GO_MOD_CACHE..."
    chown -R vscode:vscode "$GO_MOD_CACHE"
fi

# ---------------------------------------------------------------------------
# 1. Proxy
# ---------------------------------------------------------------------------
install -d -o "$PROXY_USER" -g "$PROXY_USER" /var/log/squid /var/run/squid

echo "Validating squid configuration..."
squid -k parse -f /etc/squid/squid.conf

if pgrep -x squid >/dev/null 2>&1; then
    echo "Squid already running, reloading configuration..."
    squid -k reconfigure -f /etc/squid/squid.conf
else
    echo "Starting squid..."
    squid -f /etc/squid/squid.conf
fi

# Squid daemonises before the listener is necessarily up.
for _ in $(seq 1 25); do
    if ss -ltn 2>/dev/null | grep -q '127\.0\.0\.1:3128'; then
        break
    fi
    sleep 0.2
done

if ! ss -ltn 2>/dev/null | grep -q '127\.0\.0\.1:3128'; then
    echo "ERROR: squid did not start listening on 127.0.0.1:3128"
    tail -n 20 /var/log/squid/cache.log 2>/dev/null || true
    exit 1
fi

# ---------------------------------------------------------------------------
# 2. Kernel egress policy
# ---------------------------------------------------------------------------

# Preserve Docker's embedded DNS NAT rules before flushing.
DOCKER_DNS_RULES=$(iptables-save -t nat | grep "127\.0\.0\.11" || true)

iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
iptables -t mangle -F
iptables -t mangle -X

if [ -n "$DOCKER_DNS_RULES" ]; then
    echo "Restoring Docker DNS rules..."
    iptables -t nat -N DOCKER_OUTPUT 2>/dev/null || true
    iptables -t nat -N DOCKER_POSTROUTING 2>/dev/null || true
    echo "$DOCKER_DNS_RULES" | xargs -L 1 iptables -t nat
else
    echo "No Docker DNS rules to restore"
fi

# Name resolution is the proxy's job. Deny it to everyone else first, including
# over loopback — Docker's embedded resolver at 127.0.0.11 forwards upstream
# from outside this netns, so an unrestricted loopback rule would leave DNS
# open as an exfiltration channel.
iptables -A OUTPUT -p udp --dport 53 -m owner ! --uid-owner "$PROXY_UID" \
    -j REJECT --reject-with icmp-admin-prohibited
iptables -A OUTPUT -p tcp --dport 53 -m owner ! --uid-owner "$PROXY_UID" \
    -j REJECT --reject-with icmp-admin-prohibited

# Loopback, so everything can reach the proxy on 127.0.0.1:3128.
iptables -A INPUT  -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

iptables -A INPUT  -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# The proxy, and only the proxy, may talk to the outside world.
iptables -A OUTPUT -p udp --dport 53 -m owner --uid-owner "$PROXY_UID" -j ACCEPT
iptables -A OUTPUT -p tcp --dport 53 -m owner --uid-owner "$PROXY_UID" -j ACCEPT
iptables -A OUTPUT -p tcp -m multiport --dports 80,443 \
    -m owner --uid-owner "$PROXY_UID" -j ACCEPT

iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT DROP

# Explicit REJECT so blocked traffic fails fast instead of hanging.
iptables -A OUTPUT -j REJECT --reject-with icmp-admin-prohibited

# No IPv6 route is expected; make sure it cannot become one.
if command -v ip6tables >/dev/null 2>&1; then
    ip6tables -F 2>/dev/null || true
    ip6tables -P INPUT DROP 2>/dev/null || true
    ip6tables -P FORWARD DROP 2>/dev/null || true
    ip6tables -P OUTPUT DROP 2>/dev/null || true
fi

echo "Firewall configuration complete"

# ---------------------------------------------------------------------------
# 3. Verification
# ---------------------------------------------------------------------------
PROXY=http://127.0.0.1:3128

echo "Verifying sandbox..."

# Direct egress must fail even for an allowlisted host: no proxy, no network.
if sudo -u vscode curl --noproxy '*' --connect-timeout 5 -s \
        https://proxy.golang.org >/dev/null 2>&1; then
    echo "ERROR: direct egress to proxy.golang.org succeeded, firewall is not enforcing"
    exit 1
fi
echo "  ok: direct egress blocked"

# Direct DNS must fail too.
if sudo -u vscode dig +short +time=2 +tries=1 example.com 2>/dev/null | grep -qE '^[0-9]'; then
    echo "ERROR: direct DNS resolution succeeded, DNS is not restricted to the proxy"
    exit 1
fi
echo "  ok: direct DNS blocked"

# A non-allowlisted host must be refused by the proxy.
if sudo -u vscode curl --proxy "$PROXY" --connect-timeout 5 -sf \
        https://example.com >/dev/null 2>&1; then
    echo "ERROR: example.com reachable through the proxy, allowlist is not enforcing"
    exit 1
fi
echo "  ok: non-allowlisted host refused by proxy"

# Allowlisted hosts should work. These are advisory: a transient upstream
# outage must not stop the container from starting, because failing this check
# means "no network", not "no sandbox".
for url in https://proxy.golang.org/cached-only/ https://api.github.com/zen; do
    if sudo -u vscode curl --proxy "$PROXY" --connect-timeout 10 -s -o /dev/null \
            -w '%{http_code}' "$url" | grep -qE '^[23]'; then
        echo "  ok: reachable via proxy: $url"
    else
        echo "  WARNING: allowlisted URL unreachable through the proxy: $url"
    fi
done

echo "Sandbox verification passed"
