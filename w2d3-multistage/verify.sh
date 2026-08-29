#!/usr/bin/env bash

set -euo pipefail

NAIVE_IMAGE="registry:naive"
MULTISTAGE_IMAGE="registry:multistage"
CONTAINER_NAME="registry-multistage-verifier"
TARGET_MB=300
MIN_SAVINGS_PCT=20
TEMP_DIR=""

cleanup() {
    docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
    if [[ -n "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
    fi
}

fail() {
    local reason="$1"
    cleanup
    trap - EXIT INT TERM
    echo "GREEN CHECK: FAIL ($reason)"
    exit 1
}

unexpected_failure() {
    local status=$?
    if (( status != 0 )); then
        fail "unexpected verifier error"
    fi
}

trap unexpected_failure EXIT
trap 'fail "verifier interrupted"' INT TERM

if ! docker image inspect "$NAIVE_IMAGE" >/dev/null 2>&1; then
    fail "missing Docker image: $NAIVE_IMAGE"
fi

if ! docker image inspect "$MULTISTAGE_IMAGE" >/dev/null 2>&1; then
    fail "missing Docker image: $MULTISTAGE_IMAGE"
fi

naive_bytes=$(docker image inspect "$NAIVE_IMAGE" --format '{{.Size}}')
multistage_bytes=$(docker image inspect "$MULTISTAGE_IMAGE" --format '{{.Size}}')

if [[ ! "$naive_bytes" =~ ^[0-9]+$ || ! "$multistage_bytes" =~ ^[0-9]+$ ]]; then
    fail "could not read Docker image sizes"
fi

naive_mb=$(python3 -c 'import sys; print(f"{int(sys.argv[1]) / 1_000_000:.1f}")' "$naive_bytes")
multistage_mb=$(python3 -c 'import sys; print(f"{int(sys.argv[1]) / 1_000_000:.1f}")' "$multistage_bytes")
savings_mb=$(python3 -c 'import sys; print(f"{(int(sys.argv[1]) - int(sys.argv[2])) / 1_000_000:.1f}")' "$naive_bytes" "$multistage_bytes")
savings_pct=$(python3 -c 'import sys; n=int(sys.argv[1]); m=int(sys.argv[2]); print(f"{((n - m) / n * 100) if n else 0:.1f}")' "$naive_bytes" "$multistage_bytes")

echo "naive image:      ${naive_mb} MB"
echo "multi-stage image: ${multistage_mb} MB"
echo "saved:            ${savings_mb} MB (${savings_pct}%)"

if (( multistage_bytes > TARGET_MB * 1000000 )); then
    fail "registry:multistage exceeds ${TARGET_MB} MB"
fi

if (( (naive_bytes - multistage_bytes) * 100 < MIN_SAVINGS_PCT * naive_bytes )); then
    fail "registry:multistage saves less than ${MIN_SAVINGS_PCT}%"
fi

docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true

HOST_PORT=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()')
TEMP_DIR=$(mktemp -d)

if ! docker run -d \
    --name "$CONTAINER_NAME" \
    -p "127.0.0.1:${HOST_PORT}:8000" \
    "$MULTISTAGE_IMAGE" >/dev/null; then
    fail "could not start registry:multistage"
fi

ready=false
for _ in $(seq 1 60); do
    status=$(curl -sS -o "$TEMP_DIR/health.json" -w '%{http_code}' \
        "http://127.0.0.1:${HOST_PORT}/health" 2>/dev/null || true)
    if [[ "$status" == "200" ]]; then
        ready=true
        break
    fi
    sleep 1
done

if [[ "$ready" != "true" ]]; then
    fail "service did not become ready"
fi

health_status=$(curl -sS -o "$TEMP_DIR/health.json" -w '%{http_code}' \
    "http://127.0.0.1:${HOST_PORT}/health" || true)
if [[ "$health_status" != "200" ]]; then
    fail "/health did not return HTTP 200"
fi
if ! python3 -c 'import json,sys; data=json.load(open(sys.argv[1])); raise SystemExit(0 if data.get("status") == "ok" else 1)' \
    "$TEMP_DIR/health.json"; then
    fail "/health status was not ok"
fi

registry_status=$(curl -sS -o "$TEMP_DIR/registry.json" -w '%{http_code}' \
    "http://127.0.0.1:${HOST_PORT}/registry" || true)
if [[ "$registry_status" != "200" ]]; then
    fail "/registry did not return HTTP 200"
fi
if ! python3 -c 'import json,sys; data=json.load(open(sys.argv[1])); expected={"Qwen2.5-0.5B-Instruct", "Qwen2.5-1.5B-Instruct", "Qwen2.5-3B-Instruct"}; models=data.get("models"); raise SystemExit(0 if isinstance(models, list) and len(models) == 3 and set(models) == expected else 1)' \
    "$TEMP_DIR/registry.json"; then
    fail "/registry did not return the three expected models"
fi

model_status=$(curl -sS -o "$TEMP_DIR/model.json" -w '%{http_code}' \
    "http://127.0.0.1:${HOST_PORT}/registry/Qwen2.5-1.5B-Instruct" || true)
if [[ "$model_status" != "200" ]]; then
    fail "model lookup did not return HTTP 200"
fi
if ! python3 -c 'import json,sys; data=json.load(open(sys.argv[1])); expected={"repo_id":"Qwen/Qwen2.5-1.5B-Instruct", "tier":"tier-0", "status":"approved"}; raise SystemExit(0 if data == expected else 1)' \
    "$TEMP_DIR/model.json"; then
    fail "model lookup returned unexpected data"
fi

missing_status=$(curl -sS -o /dev/null -w '%{http_code}' \
    "http://127.0.0.1:${HOST_PORT}/registry/nonexistent" || true)
if [[ "$missing_status" != "404" ]]; then
    fail "unknown model lookup did not return HTTP 404"
fi

cleanup
trap - EXIT INT TERM
echo "GREEN CHECK: PASS"
