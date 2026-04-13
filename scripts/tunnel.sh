#!/usr/bin/env bash
set -euo pipefail

##########################
# Defaults
##########################
LOCAL_PORT="${LOCAL_PORT:-5442}"
SRC_PORT="${SRC_PORT:-5432}"
DEST_PORT="${DEST_PORT:-5432}"
SOCAT_BIN="$HOME/.local/bin/socat"

##########################
# Usage
##########################
usage() {
  echo ""
  echo "Usage: $(basename "$0") -n <namespace> -p <pod> -H <db-host> [options]"
  echo ""
  echo "Required:"
  echo "  -n  Pod namespace"
  echo "  -p  Pod name"
  echo "  -H  Database host (final destination)"
  echo ""
  echo "Optional:"
  echo "  -l  Local port exposed on your machine      (default: $LOCAL_PORT)"
  echo "  -s  Port socat listens on inside the Pod    (default: $SRC_PORT)"
  echo "  -d  Destination port on the DB host         (default: $DEST_PORT)"
  echo ""
  echo "Example:"
  echo "  $(basename "$0") -n production -p my-pod-abc123 -H my-db.internal"
  echo "  $(basename "$0") -n production -p my-pod-abc123 -H my-db.internal -l 5442 -s 5432 -d 5432"
  echo ""
  exit 1
}

##########################
# Args
##########################
while getopts "n:p:H:l:s:d:h" opt; do
  case $opt in
    n) NAMESPACE="$OPTARG" ;;
    p) POD="$OPTARG" ;;
    H) DB_HOST="$OPTARG" ;;
    l) LOCAL_PORT="$OPTARG" ;;
    s) SRC_PORT="$OPTARG" ;;
    d) DEST_PORT="$OPTARG" ;;
    h) usage ;;
    *) usage ;;
  esac
done

##########################
# Validate required
##########################
if [[ -z "${NAMESPACE:-}" ]] || [[ -z "${POD:-}" ]] || [[ -z "${DB_HOST:-}" ]]; then
  usage
fi

##########################
# Download socat
##########################
if [[ ! -f "$SOCAT_BIN" ]]; then
  echo "◆ Downloading static socat binary for Linux..."
  mkdir -p "$HOME/.local/bin"
  curl -L https://github.com/andrew-d/static-binaries/raw/master/binaries/linux/x86_64/socat \
    -o "$SOCAT_BIN"
  chmod +x "$SOCAT_BIN"
  echo "✔ socat downloaded to $SOCAT_BIN"
else
  echo "✔ socat already exists at $SOCAT_BIN, skipping download"
fi

##########################
# Copy socat into the Pod
##########################
echo "◆ Copying socat to pod $POD ($NAMESPACE)..."
kubectl cp "$SOCAT_BIN" "$NAMESPACE/$POD:/tmp/socat"
kubectl exec "$POD" -n "$NAMESPACE" -- chmod +x /tmp/socat
echo "✔ socat copied to /tmp/socat inside the pod"

##########################
# Launch socat relay + port-forward
##########################
echo "◆ Starting relay in Pod"
echo "◆ Tunnel ready: localhost:$LOCAL_PORT → pod:$SRC_PORT → $DB_HOST:$DEST_PORT"
echo "  Connect with: psql -h localhost -p $LOCAL_PORT -U <user> <dbname>"
echo "  Press Ctrl+C to close"

kubectl exec "$POD" -n "$NAMESPACE" -- /tmp/socat \
  "TCP-LISTEN:$SRC_PORT,fork" \
  "TCP:$DB_HOST:$DEST_PORT" &

kubectl port-forward "pod/$POD" "$LOCAL_PORT:$SRC_PORT" -n "$NAMESPACE"
