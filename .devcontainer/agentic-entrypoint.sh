#!/bin/bash
# Container entrypoint. Runs as root on every container start — including
# `docker start` and an interrupted `devcontainer up`, neither of which replay
# lifecycle hooks — so the sandbox cannot be skipped.
#
# Fails closed: if the sandbox cannot be established the container does not
# start, rather than coming up with unrestricted network access.
set -euo pipefail

if ! /usr/local/bin/agentic-netsetup.sh; then
    echo "FATAL: network sandbox setup failed; refusing to start the container" >&2
    exit 1
fi

exec "$@"
