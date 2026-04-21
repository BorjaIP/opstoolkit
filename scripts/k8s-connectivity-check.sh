#!/usr/bin/env bash
set -euo pipefail

##########################
# Defaults
##########################
TIMEOUT=5
KUBECTL_CONTEXT=""

##########################
# Colors
##########################
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

##########################
# Usage
##########################
usage() {
  echo ""
  echo "Usage: $(basename "$0") -n <namespace> -p <pod> -H <host> -P <port> [options]"
  echo ""
  echo "Required:"
  echo "  -n  Pod namespace"
  echo "  -p  Pod name (or pod/<name>)"
  echo "  -H  Target host / URL"
  echo "  -P  Target port"
  echo ""
  echo "Optional:"
  echo "  -c  kubectl context (default: current context)"
  echo "  -t  Timeout in seconds  (default: $TIMEOUT)"
  echo "  -h  Show this help"
  echo ""
  echo "Examples:"
  echo "  $(basename "$0") -n data-ai-agents-staging -p data-ai-mcp-data-fever-9cb54c984-cfvw4 -H lr57239.eu-west-1.snowflakecomputing.com -P 443"
  echo "  $(basename "$0") -n production -p my-pod-abc123 -H my-db.internal -P 5432 -c my-k8s-context"
  echo ""
  exit 1
}

##########################
# Args
##########################
while getopts "n:p:H:P:c:t:h" opt; do
  case $opt in
    n) NAMESPACE="$OPTARG" ;;
    p) POD="$OPTARG" ;;
    H) HOST="$OPTARG" ;;
    P) PORT="$OPTARG" ;;
    c) KUBECTL_CONTEXT="$OPTARG" ;;
    t) TIMEOUT="$OPTARG" ;;
    h) usage ;;
    *) usage ;;
  esac
done

##########################
# Validate required
##########################
if [[ -z "${NAMESPACE:-}" ]] || [[ -z "${POD:-}" ]] || [[ -z "${HOST:-}" ]] || [[ -z "${PORT:-}" ]]; then
  echo -e "${RED}Error: -n, -p, -H and -P are all required.${RESET}"
  usage
fi

POD="${POD#pod/}"

# Build kubectl command array with optional context
KC=(kubectl)
[[ -n "$KUBECTL_CONTEXT" ]] && KC=(kubectl --context "$KUBECTL_CONTEXT")

##########################
# Counters
##########################
PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

result_pass() { echo -e "  ${GREEN}✔ PASS${RESET}  $1"; ((PASS_COUNT++)) || true; }
result_fail() { echo -e "  ${RED}✘ FAIL${RESET}  $1"; ((FAIL_COUNT++)) || true; }
result_skip() { echo -e "  ${YELLOW}⊘ SKIP${RESET}  ${1} not found in pod"; ((SKIP_COUNT++)) || true; }

# Run a command inside the pod, capture stdout+stderr and exit code.
# Never aborts the outer script.
pod_run() {
  set +e
  OUTPUT=$("${KC[@]}" exec "pod/$POD" -n "$NAMESPACE" --request-timeout="${TIMEOUT}s" -- "$@" 2>&1)
  RC=$?
  set -e
}

##########################
# Header
##########################
echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${BOLD}  K8s Connectivity Check${RESET}"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "  Pod       : ${CYAN}$POD${RESET}"
echo -e "  Namespace : ${CYAN}$NAMESPACE${RESET}"
echo -e "  Target    : ${CYAN}$HOST:$PORT${RESET}"
echo -e "  Timeout   : ${CYAN}${TIMEOUT}s${RESET}"
echo -e "  Context   : ${CYAN}${KUBECTL_CONTEXT:-$("${KC[@]}" config current-context 2>/dev/null || echo 'default')}${RESET}"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo ""

##########################
# [0] Verify pod exists
##########################
echo -e "${BOLD}[0] Verifying pod...${RESET}"
if ! "${KC[@]}" get pod "$POD" -n "$NAMESPACE" --request-timeout="${TIMEOUT}s" >/dev/null 2>&1; then
  echo -e "  ${RED}✘ Pod '$POD' not found in namespace '$NAMESPACE'. Aborting.${RESET}"
  exit 1
fi
echo -e "  ${GREEN}✔ Pod found${RESET}"
echo ""

##########################
# [probe] Batch binary detection — ONE kubectl exec for all tools
# Also detects whether `timeout` itself is available inside the pod.
##########################
echo -e "${BOLD}Probing available binaries (single exec)...${RESET}"
set +e
PROBE=$("${KC[@]}" exec "pod/$POD" -n "$NAMESPACE" --request-timeout="${TIMEOUT}s" -- bash -c '
  for b in bash curl wget nc nmap openssl telnet python3 timeout; do
    if command -v "$b" >/dev/null 2>&1; then
      echo "${b}:1"
    else
      echo "${b}:0"
    fi
  done
' 2>&1)
PROBE_RC=$?
set -e

# Store probe results as plain variables BIN_curl, BIN_wget, etc.
# Only processes lines matching exactly "<name>:<0|1>" to ignore kubectl warnings.
_set_bin_vars() {
  local name avail
  while IFS=: read -r name avail; do
    [[ "$name" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] && [[ "$avail" =~ ^[01]$ ]] || continue
    printf -v "BIN_${name}" '%s' "$avail"
  done <<< "$1"
}

if [[ $PROBE_RC -eq 0 ]]; then
  _set_bin_vars "$PROBE"
  for b in bash curl wget nc nmap openssl telnet python3 timeout; do
    _var="BIN_${b}"
    if [[ "${!_var:-0}" == "1" ]]; then
      echo -e "  ${GREEN}✔${RESET} $b"
    else
      echo -e "  ${YELLOW}–${RESET} $b (not found)"
    fi
  done
else
  echo -e "  ${YELLOW}⚠ Could not probe binaries (bash not in pod?). Will attempt each method anyway.${RESET}"
  for b in bash curl wget nc nmap openssl telnet python3 timeout; do
    eval "BIN_${b}=1"
  done
fi

# Helper: wrap command with `timeout` if the binary exists in the pod
has_bin()     { local var="BIN_${1}"; [[ "${!var:-0}" == "1" ]]; }
has_timeout() { has_bin timeout; }

# Build timeout prefix: "timeout <N>" if available, otherwise empty
T_PREFIX=""
has_timeout && T_PREFIX="timeout $TIMEOUT"

echo ""

##########################
# [1] curl
##########################
echo -e "${BOLD}[1] curl${RESET}"
if has_bin curl; then
  pod_run bash -c "$T_PREFIX curl \
    --silent \
    --connect-timeout $TIMEOUT \
    --max-time $TIMEOUT \
    -o /dev/null \
    'https://$HOST:$PORT' 2>&1; echo \"exit:\$?\""

  # Extract the real curl exit code from the echoed line
  CURL_RC=$(echo "$OUTPUT" | grep '^exit:' | cut -d: -f2 || echo "1")
  case "$CURL_RC" in
    0|22)   result_pass "curl: HTTP response received (exit $CURL_RC)" ;;
    35|60)  result_pass "curl: TCP/TLS reached — SSL error acceptable (exit $CURL_RC)" ;;
    6)      result_fail "curl: DNS resolution failed (exit 6)" ;;
    7)      result_fail "curl: connection refused (exit 7)" ;;
    28|124) result_fail "curl: timed out after ${TIMEOUT}s" ;;
    *)      result_fail "curl: failed (exit $CURL_RC)" ;;
  esac
else
  result_skip curl
fi
echo ""

##########################
# [2] wget
##########################
echo -e "${BOLD}[2] wget${RESET}"
if has_bin wget; then
  pod_run bash -c "$T_PREFIX wget \
    --quiet \
    --timeout=$TIMEOUT \
    --tries=1 \
    -O /dev/null \
    'https://$HOST:$PORT' 2>&1; echo \"exit:\$?\""

  WGET_RC=$(echo "$OUTPUT" | grep '^exit:' | cut -d: -f2 || echo "1")
  case "$WGET_RC" in
    0)   result_pass "wget: connected successfully" ;;
    5)   result_pass "wget: TCP reached — SSL error acceptable (exit 5)" ;;
    4)   result_fail "wget: network failure (exit 4)" ;;
    124) result_fail "wget: timed out after ${TIMEOUT}s" ;;
    *)   result_fail "wget: failed (exit $WGET_RC)" ;;
  esac
else
  result_skip wget
fi
echo ""

##########################
# [3] nc (netcat)
##########################
echo -e "${BOLD}[3] nc (netcat)${RESET}"
if has_bin nc; then
  pod_run nc -z -w "$TIMEOUT" "$HOST" "$PORT"
  if [[ $RC -eq 0 ]]; then
    result_pass "nc: port $PORT is open"
  else
    result_fail "nc: port $PORT unreachable (exit $RC)"
  fi
else
  result_skip nc
fi
echo ""

##########################
# [4] bash /dev/tcp
##########################
echo -e "${BOLD}[4] bash /dev/tcp${RESET}"
if has_bin bash; then
  # Use `timeout` inside the pod if available to avoid indefinite hang
  pod_run bash -c "$T_PREFIX bash -c \
    '(echo > /dev/tcp/$HOST/$PORT) 2>/dev/null && echo ok || echo fail'"
  if echo "$OUTPUT" | grep -q "^ok"; then
    result_pass "bash /dev/tcp: TCP connection opened"
  else
    result_fail "bash /dev/tcp: failed — $OUTPUT"
  fi
else
  result_skip bash
fi
echo ""

##########################
# [5] openssl s_client
# Wrapped with `timeout` to prevent the blocking read-loop
##########################
echo -e "${BOLD}[5] openssl s_client${RESET}"
if has_bin openssl; then
  # `timeout` hard-kills openssl after N seconds even if it hangs waiting for stdin
  OSSL_CMD="echo Q | openssl s_client -connect $HOST:$PORT -verify_quiet 2>&1"
  if has_timeout; then
    pod_run bash -c "timeout $TIMEOUT bash -c '$OSSL_CMD'"
  else
    pod_run bash -c "$OSSL_CMD"
  fi

  if echo "$OUTPUT" | grep -qE "^CONNECTED|Verify return code"; then
    result_pass "openssl: TLS handshake reached"
  elif echo "$OUTPUT" | grep -q "^connect:errno"; then
    result_fail "openssl: connection refused/timeout"
  else
    result_fail "openssl: failed — $(echo "$OUTPUT" | head -2)"
  fi
else
  result_skip openssl
fi
echo ""

##########################
# [6] telnet
##########################
echo -e "${BOLD}[6] telnet${RESET}"
if has_bin telnet; then
  if has_timeout; then
    pod_run bash -c "echo '' | timeout $TIMEOUT telnet $HOST $PORT 2>&1 || true"
  else
    pod_run bash -c "echo '' | telnet $HOST $PORT 2>&1 || true"
  fi

  if echo "$OUTPUT" | grep -qE "Connected|Escape character"; then
    result_pass "telnet: connection established"
  elif echo "$OUTPUT" | grep -qE "Connection refused|Unable to connect|refused"; then
    result_fail "telnet: connection refused"
  elif echo "$OUTPUT" | grep -qE "timed out|Timeout"; then
    result_fail "telnet: timed out"
  else
    result_fail "telnet: unknown result — $(echo "$OUTPUT" | head -1)"
  fi
else
  result_skip telnet
fi
echo ""

##########################
# [7] nmap
##########################
echo -e "${BOLD}[7] nmap${RESET}"
if has_bin nmap; then
  pod_run nmap -p "$PORT" --open -T4 --host-timeout "${TIMEOUT}s" "$HOST"
  if echo "$OUTPUT" | grep -q "open"; then
    result_pass "nmap: port $PORT/tcp open"
  else
    result_fail "nmap: port $PORT not open — $(echo "$OUTPUT" | tail -3)"
  fi
else
  result_skip nmap
fi
echo ""

##########################
# [8] python3 socket
##########################
echo -e "${BOLD}[8] python3 socket${RESET}"
if has_bin python3; then
  pod_run python3 -c "
import socket, sys
try:
    s = socket.create_connection(('$HOST', $PORT), timeout=$TIMEOUT)
    print('ok')
    s.close()
except Exception as e:
    print('err:' + str(e), file=sys.stderr)
    sys.exit(1)
"
  if [[ $RC -eq 0 ]]; then
    result_pass "python3 socket.create_connection: OK"
  else
    result_fail "python3 socket: $OUTPUT"
  fi
else
  result_skip python3
fi
echo ""

##########################
# [9] python3 urllib (HTTPS, skips cert validation)
##########################
echo -e "${BOLD}[9] python3 urllib (HTTPS)${RESET}"
if has_bin python3; then
  pod_run python3 -c "
import urllib.request, ssl, sys
ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE
try:
    r = urllib.request.urlopen('https://$HOST:$PORT', context=ctx, timeout=$TIMEOUT)
    print('HTTP ' + str(r.status))
except urllib.error.HTTPError as e:
    print('HTTP ' + str(e.code) + ' (TCP OK)')
except urllib.error.URLError as e:
    r = str(e.reason)
    if any(x in r for x in ['SSL', 'CERTIFICATE', 'handshake', 'EOF']):
        print('SSL/TLS error (TCP OK)')
    else:
        print('err:' + r, file=sys.stderr)
        sys.exit(1)
except Exception as e:
    print('err:' + str(e), file=sys.stderr)
    sys.exit(1)
"
  if [[ $RC -eq 0 ]]; then
    result_pass "python3 urllib: $OUTPUT"
  else
    result_fail "python3 urllib: $OUTPUT"
  fi
else
  result_skip "python3 (urllib)"
fi
echo ""

##########################
# Summary
##########################
TOTAL=$((PASS_COUNT + FAIL_COUNT + SKIP_COUNT))
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${BOLD}  Summary: $HOST:$PORT${RESET}"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "  Total    : $TOTAL"
echo -e "  ${GREEN}Passed${RESET}   : $PASS_COUNT"
echo -e "  ${RED}Failed${RESET}   : $FAIL_COUNT"
echo -e "  ${YELLOW}Skipped${RESET}  : $SKIP_COUNT (not in pod)"
echo ""
if [[ $PASS_COUNT -gt 0 ]]; then
  echo -e "  ${GREEN}${BOLD}✔ Connectivity confirmed via $PASS_COUNT method(s)${RESET}"
elif [[ $FAIL_COUNT -gt 0 ]]; then
  echo -e "  ${RED}${BOLD}✘ No method could reach $HOST:$PORT${RESET}"
else
  echo -e "  ${YELLOW}${BOLD}⊘ All methods skipped — no tools found in pod${RESET}"
fi
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo ""

[[ $FAIL_COUNT -gt 0 && $PASS_COUNT -eq 0 ]] && exit 1
exit 0
