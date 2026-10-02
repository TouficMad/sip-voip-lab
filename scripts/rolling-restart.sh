#!/usr/bin/env bash
# Zero-downtime maintenance: restart the Asterisk servers one at a time.
#
# "core stop gracefully" makes Asterisk refuse new calls (Kamailio retries them
# on the other server) and exit once its active calls have ended. Kubernetes
# does the same through the pod's preStop hook.
set -euo pipefail
cd "$(dirname "$0")/.."

# Kamailio's view of a server: FLAGS starting with "A" means active
kamailio_state() {
  docker compose exec -T kamailio kamcmd -s unixs:/run/kamailio/kamailio_ctl dispatcher.list |
    awk -v uri="sip:$1:5060" '$1 == "URI:" { found = ($2 == uri) } found && $1 == "FLAGS:" { print $2; exit }'
}

for server in asterisk-1 asterisk-2; do
  echo "== $server: stop taking new calls, wait for active calls to end"
  started=$(date +%s)
  # returns once Asterisk has exited (or the connection drops)
  docker compose exec -T "$server" asterisk -rx "core stop gracefully" > /dev/null 2>&1 || true
  while [ "$(docker compose ps -q --status running "$server")" != "" ]; do sleep 1; done
  echo "   stopped after $(( $(date +%s) - started ))s"

  echo "== $server: starting again"
  docker compose up -d --wait "$server"
  until kamailio_state "$server" | grep -q '^A'; do sleep 2; done
  echo "   Kamailio sees $server as active again"
done
echo "Rolling restart done"
