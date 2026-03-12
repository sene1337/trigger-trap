#!/usr/bin/env bash
# pre-ask-gate.sh — Investigate-first gate before sending a question to Brad.
# Requires BOTH a recall/LCM evidence indicator AND a local evidence line/path.
# On pass: writes .gate/ask-allowed.json using the runtime token schema and exits 0.
# On fail: prints reason(s) and exits 1.
#
# Usage:
#   pre-ask-gate.sh [OPTIONS] <topic>
#
# Options:
#   --lcm   <text>       Recall/LCM evidence snippet (required)
#   --local <path|line>  Local file path or evidence line (required)
#   -h, --help           Show this help
#
# Example:
#   pre-ask-gate.sh --lcm "memory/2026-02-14.md: kazuo target = 2100" \
#                   --local "docs/investments/kazuo.md" \
#                   "kazuo target number"

set -euo pipefail

# ── Paths ─────────────────────────────────────────────────────────────────────
WORKSPACE="${WORKSPACE:-/Users/senemaro/.openclaw/workspace}"
GATE_DIR="${WORKSPACE}/.gate"
GATE_FILE="${GATE_DIR}/ask-allowed.json"
LOG_FILE="${WORKSPACE}/logs/ask-guard.log"
TTL="${ASK_GATE_TOKEN_TTL_SECONDS:-600}"

# ── Helpers ───────────────────────────────────────────────────────────────────
log_event() {
  local decision="$1" reason="$2"
  local ts
  ts="$(date '+%Y-%m-%dT%H:%M:%S%z')"
  mkdir -p "$(dirname "${LOG_FILE}")"
  echo "${ts} | pre-ask-gate | ${decision} | ${reason}" >> "${LOG_FILE}"
}

usage() {
  sed -n '/^# Usage:/,/^$/p' "$0" | sed 's/^# \{0,2\}//'
  exit 0
}

die() {
  echo "GATE_FAIL: $*" >&2
  log_event "BLOCK" "$*"
  exit 1
}

# ── Argument parsing ──────────────────────────────────────────────────────────
TOPIC=""
LCM_EVIDENCE=""
LOCAL_EVIDENCE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage ;;
    --lcm)
      [[ $# -ge 2 ]] || die "--lcm requires an argument"
      LCM_EVIDENCE="$2"; shift 2 ;;
    --local)
      [[ $# -ge 2 ]] || die "--local requires an argument"
      LOCAL_EVIDENCE="$2"; shift 2 ;;
    -*)
      die "Unknown option: $1" ;;
    *)
      [[ -z "${TOPIC}" ]] || die "Unexpected extra argument: $1"
      TOPIC="$1"; shift ;;
  esac
done

[[ -n "${TOPIC}" ]] || { echo "ERROR: <topic> is required." >&2; usage; }

# ── Evidence gate ─────────────────────────────────────────────────────────────
FAILURES=()

if [[ -z "${LCM_EVIDENCE}" ]]; then
  FAILURES+=("missing --lcm recall/LCM evidence (investigate memory/LCM first)")
fi

if [[ -z "${LOCAL_EVIDENCE}" ]]; then
  FAILURES+=("missing --local evidence line or path (check local files first)")
fi

if [[ ${#FAILURES[@]} -gt 0 ]]; then
  for f in "${FAILURES[@]}"; do
    echo "GATE_FAIL: ${f}" >&2
  done
  reason="$(IFS='; '; echo "${FAILURES[*]}")"
  log_event "BLOCK" "topic='${TOPIC}' | ${reason}"
  exit 1
fi

# ── Both checks passed — write gate artifact ──────────────────────────────────
mkdir -p "${GATE_DIR}"

NOW=$(date +%s)
EXPIRES=$(( NOW + TTL ))
EXPIRES_ISO=$(date -r "${EXPIRES}" '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null \
              || date -d "@${EXPIRES}" '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null \
              || echo "${EXPIRES}")

cat > "${GATE_FILE}" <<EOF
{
  "version": 1,
  "topic": $(printf '%s' "${TOPIC}" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))'),
  "createdAtEpoch": ${NOW},
  "expiresAtEpoch": ${EXPIRES},
  "expiresAtIso": "${EXPIRES_ISO}",
  "lcmEvidence": $(printf '%s' "${LCM_EVIDENCE}" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))'),
  "localEvidence": $(printf '%s' "${LOCAL_EVIDENCE}" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')
}
EOF

log_event "ALLOW" "topic='${TOPIC}' | lcm='${LCM_EVIDENCE}' | local='${LOCAL_EVIDENCE}' | expires=${EXPIRES_ISO}"

echo "GATE_PASS: ask allowed for '${TOPIC}' (valid ${TTL}s / until ${EXPIRES_ISO})"
echo "  lcm:   ${LCM_EVIDENCE}"
echo "  local: ${LOCAL_EVIDENCE}"
