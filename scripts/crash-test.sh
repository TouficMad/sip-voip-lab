#!/usr/bin/env bash
# Chaos test: kill asterisk-1 (no warning) in the middle of a load test.
#
# Expected result: calls that were already connected on asterisk-1 are lost
# (a crashed media server takes its calls with it), while every new call is
# failed over to asterisk-2 by Kamailio. Compare with rolling-restart.sh.
set -uo pipefail
cd "$(dirname "$0")/.."

docker compose run --rm -e RATE=20 -e CALLS=600 sipp > crash-test.log 2>&1 &
load=$!
sleep 10
docker compose kill asterisk-1
echo "== asterisk-1 killed"
wait "$load"
grep -E '^(created|LOAD)' crash-test.log

echo "== Failovers recorded by Kamailio (new calls moved to asterisk-2):"
curl -s localhost:9090/metrics | grep '^kamailio_sip_failover_total' || echo "(none)"

echo "== Bringing asterisk-1 back"
docker compose up -d --wait asterisk-1
