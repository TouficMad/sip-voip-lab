#!/bin/sh
# Load test through Kamailio. Exits non-zero if any call fails.
#   TARGET  host:port of Kamailio        (default kamailio:5060)
#   RATE    new calls per second          (default 10)
#   CALLS   total calls                   (default 300)
#   LIMIT   max simultaneous calls        (default 300)
set -u
TARGET=${TARGET:-kamailio:5060}
RATE=${RATE:-10}
CALLS=${CALLS:-300}
LIMIT=${LIMIT:-300}

echo "SIPp: $CALLS calls at $RATE cps (max $LIMIT concurrent) -> $TARGET"
sipp "$TARGET" -sf /sipp/uac.xml -inf /sipp/numbers.csv \
  -r "$RATE" -m "$CALLS" -l "$LIMIT" -nostdin \
  -trace_stat -stf /tmp/stats.csv -fd 5 \
  -trace_err -error_file /tmp/errors.log > /dev/null 2>&1
rc=$?

# print the totals from the last line of the statistics file
awk -F';' 'NR == 1 { for (i = 1; i <= NF; i++) col[$i] = i }
  END {
    printf "created=%s successful=%s failed=%s\n",
      $col["TotalCallCreated"], $col["SuccessfulCall(C)"], $col["FailedCall(C)"]
  }' /tmp/stats.csv

if [ "$rc" -ne 0 ]; then
  echo "LOAD TEST FAILED (sipp exit code $rc)"
  [ -f /tmp/errors.log ] && head -50 /tmp/errors.log
  exit 1
fi
echo "LOAD TEST PASSED"
