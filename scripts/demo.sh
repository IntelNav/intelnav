#!/usr/bin/env bash
# IntelNav demo bring-up — spawns 3 localhost pipe_peers + a gateway,
# all wired together so the SPA at http://127.0.0.1:8787 shows a live
# 3-node swarm.
#
# Usage:
#
#   scripts/demo.sh            # default: Qwen2.5-0.5B (24 layers, 8/8/8 split)
#   GGUF=/path/to/model.gguf scripts/demo.sh
#   N_LAYERS=24 SPLITS=8,16 scripts/demo.sh   # explicit split points
#
# Tear down with Ctrl+C — the trap stops every child process.

set -Eeuo pipefail

# ---------------------------------------------------------------------
# Config (env-overridable)
# ---------------------------------------------------------------------
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GGUF="${GGUF:-/home/islam/IntelNav/models/qwen2.5-0.5b-instruct-q4_k_m.gguf}"
LIBLLAMA_DIR="${INTELNAV_LIBLLAMA_DIR:-/home/islam/IntelNav/llama.cpp/build/bin}"
N_LAYERS="${N_LAYERS:-24}"      # Qwen2.5-0.5B has 24 transformer blocks.
# SPLITS is the chain protocol's convention: one entry per peer,
# specifying that peer's start layer. The gateway owns the prefix
# [0..splits[0]) locally (embed + first slice + head); each peer i
# owns [splits[i]..splits[i+1]), and the tail peer owns
# [splits[N-1]..N_LAYERS). For Qwen2.5-0.5B (24 layers) the default
# 6/12/18 puts ~6 layers on each side: gateway, peer-1, peer-2, peer-3.
SPLITS="${SPLITS:-6,12,18}"
PORTS=(7717 7718 7719)
GATEWAY_PORT="${GATEWAY_PORT:-8787}"
LOG_DIR="${LOG_DIR:-$ROOT/target/demo-logs}"

# Resolve binaries — prefer the freshest build.
INTELNAV_BIN="${INTELNAV_BIN:-$ROOT/target/debug/intelnav}"
PIPE_PEER_BIN="${PIPE_PEER_BIN:-$ROOT/target/debug/examples/pipe_peer}"
CHUNK_BIN="${CHUNK_BIN:-$ROOT/target/debug/intelnav-chunk}"

# Path B (stitched-subset) is the default: each peer downloads + loads
# only its layer slice, not the full GGUF. Set STITCHED=0 to fall back
# to "every peer mmaps the full file" mode for debugging.
STITCHED="${STITCHED:-1}"
CHUNK_PORT="${CHUNK_PORT:-9099}"

# ---------------------------------------------------------------------
# Sanity checks — fail fast and tell the user what to fix.
# ---------------------------------------------------------------------
die() { echo "demo: $*" >&2; exit 1; }

[[ -f "$GGUF" ]]                || die "GGUF not found at $GGUF (override with GGUF=…)"
[[ -d "$LIBLLAMA_DIR" ]]        || die "libllama dir not found at $LIBLLAMA_DIR (override with INTELNAV_LIBLLAMA_DIR=…)"
[[ -f "$INTELNAV_BIN" ]]        || die "intelnav binary not at $INTELNAV_BIN (cargo build -p intelnav-cli)"
[[ -f "$PIPE_PEER_BIN" ]]       || die "pipe_peer not at $PIPE_PEER_BIN (cargo build -p intelnav-runtime --example pipe_peer)"
if [[ "$STITCHED" == "1" ]]; then
    [[ -f "$CHUNK_BIN" ]] || die "intelnav-chunk not at $CHUNK_BIN (cargo build -p intelnav-model-store --features serve --bin intelnav-chunk)"
fi

mkdir -p "$LOG_DIR"

# Parse SPLITS (chain protocol convention: one entry per peer = that
# peer's start layer). With SPLITS="6,12,18" and N_LAYERS=24 the
# gateway owns [0..6) locally, peer-1 owns [6..12), peer-2 [12..18),
# peer-3 [18..24).
IFS=',' read -ra split_arr <<< "$SPLITS"
peer_ranges=()
for i in "${!split_arr[@]}"; do
    start="${split_arr[$i]}"
    next_idx=$((i + 1))
    if (( next_idx < ${#split_arr[@]} )); then
        end="${split_arr[$next_idx]}"
    else
        end="$N_LAYERS"
    fi
    peer_ranges+=("$start:$end")
done

[[ "${#peer_ranges[@]}" -eq "${#PORTS[@]}" ]] \
    || die "SPLITS=$SPLITS produced ${#peer_ranges[@]} ranges but we have ${#PORTS[@]} ports"

# ---------------------------------------------------------------------
# Lifecycle: start, stream logs to disk, kill everything on exit.
# ---------------------------------------------------------------------
declare -a CHILDREN=()
declare -a CHILD_LABELS=()

cleanup() {
    echo
    echo "demo: shutting down…"
    for i in "${!CHILDREN[@]}"; do
        local pid="${CHILDREN[$i]}"
        local label="${CHILD_LABELS[$i]}"
        if kill -0 "$pid" 2>/dev/null; then
            echo "demo:   stop $label (pid $pid)"
            kill "$pid" 2>/dev/null || true
        fi
    done
    # Give them a beat to drain, then SIGKILL stragglers.
    sleep 1
    for pid in "${CHILDREN[@]}"; do
        kill -KILL "$pid" 2>/dev/null || true
    done
    wait 2>/dev/null || true
    echo "demo: done"
}
trap cleanup INT TERM EXIT

start_child() {
    local label="$1"; shift
    local out="$LOG_DIR/$label.out"
    local err="$LOG_DIR/$label.err"
    echo "demo: start $label" >&2
    "$@" >"$out" 2>"$err" &
    local pid=$!
    CHILDREN+=("$pid")
    CHILD_LABELS+=("$label")
    echo "$pid"
}

wait_for_port() {
    local port="$1"
    local label="$2"
    local deadline=$((SECONDS + 30))
    while (( SECONDS < deadline )); do
        if (echo > "/dev/tcp/127.0.0.1/$port") 2>/dev/null; then
            return 0
        fi
        sleep 0.2
    done
    die "$label did not start listening on :$port within 30s — see $LOG_DIR/$label.err"
}

# ---------------------------------------------------------------------
# Spawn the peers.
# ---------------------------------------------------------------------
echo "demo: model     = $GGUF"
echo "demo: libllama  = $LIBLLAMA_DIR"
echo "demo: peers     = ${#PORTS[@]} on ports ${PORTS[*]}"
echo "demo: gateway   = http://127.0.0.1:$GATEWAY_PORT"
echo "demo: stitched  = $STITCHED"
echo "demo: logs      = $LOG_DIR"
echo

export INTELNAV_LIBLLAMA_DIR="$LIBLLAMA_DIR"

# ---------------------------------------------------------------------
# Path B: chunk the GGUF once, host it, point each peer at the manifest
# so they download + load only their layer slice. This is the whole
# reason the project exists — a peer with 8 GiB doesn't keep 19 GiB of
# weights warm.
# ---------------------------------------------------------------------
CHUNK_DIR=""
MANIFEST_URL=""
if [[ "$STITCHED" == "1" ]]; then
    gguf_stem="$(basename "$GGUF" .gguf)"
    CHUNK_DIR="$ROOT/target/demo-chunks/$gguf_stem"
    if [[ -f "$CHUNK_DIR/manifest.json" ]]; then
        echo "demo: chunks   reusing $CHUNK_DIR (delete to re-chunk)"
    else
        echo "demo: chunks   chunking $GGUF -> $CHUNK_DIR"
        mkdir -p "$CHUNK_DIR"
        "$CHUNK_BIN" chunk "$GGUF" "$CHUNK_DIR" --overwrite >"$LOG_DIR/chunk.out" 2>"$LOG_DIR/chunk.err" \
            || die "intelnav-chunk failed — see $LOG_DIR/chunk.err"
    fi
    start_child "chunk-server" \
        "$CHUNK_BIN" serve "$CHUNK_DIR" --bind "127.0.0.1:$CHUNK_PORT" >/dev/null
    wait_for_port "$CHUNK_PORT" "chunk-server"
    MANIFEST_URL="http://127.0.0.1:$CHUNK_PORT/manifest.json"
    chunk_size="$(du -sh "$CHUNK_DIR" 2>/dev/null | cut -f1 || echo '?')"
    echo "demo:   chunk-server ready · $MANIFEST_URL · $chunk_size on disk"
    echo
fi

# Each peer owns one layer slice and binds its own port. In stitched
# mode (the default) it fetches its bundles from the chunk-server and
# only mmaps its own slice — Path B end-to-end.
PEER_ADDRS=()
for i in "${!PORTS[@]}"; do
    port="${PORTS[$i]}"
    range="${peer_ranges[$i]}"
    start="${range%:*}"
    end="${range#*:}"
    label="peer-$((i+1))"
    if [[ "$STITCHED" == "1" ]]; then
        peer_cache="$LOG_DIR/$label-cache"
        mkdir -p "$peer_cache"
        start_child "$label" \
            "$PIPE_PEER_BIN" \
            --manifest "$MANIFEST_URL" \
            --chunk-cache "$peer_cache" \
            --start "$start" \
            --end "$end" \
            --bind "127.0.0.1:$port" \
            --device cpu >/dev/null
    else
        start_child "$label" \
            "$PIPE_PEER_BIN" \
            --gguf "$GGUF" \
            --start "$start" \
            --end "$end" \
            --bind "127.0.0.1:$port" \
            --device cpu >/dev/null
    fi
    PEER_ADDRS+=("127.0.0.1:$port")
    wait_for_port "$port" "$label"
    if [[ "$STITCHED" == "1" ]]; then
        slice_size="$(du -sh "$LOG_DIR/$label-cache" 2>/dev/null | cut -f1 || echo '?')"
        echo "demo:   $label ready · layers [$start..$end) · 127.0.0.1:$port · stitched · slice $slice_size"
    else
        echo "demo:   $label ready · layers [$start..$end) · 127.0.0.1:$port · full-gguf"
    fi
done
echo

# ---------------------------------------------------------------------
# Spawn the gateway with the three peers pre-registered as static
# directory entries so the SPA at /v1/swarm/topology shows them.
# ---------------------------------------------------------------------
PEERS_CSV="$(IFS=,; echo "${PEER_ADDRS[*]}")"
SPLITS_CSV="$SPLITS"

# Export env vars Config picks up — registers the 3 peers in the
# gateway's static directory so they show up in /v1/swarm/topology
# and tells the gateway to drive the chain itself for chat
# completions (vs proxying to upstream).
export INTELNAV_PEERS="$PEERS_CSV"
export INTELNAV_SPLITS="$SPLITS_CSV"
export INTELNAV_GATEWAY_MODEL="$GGUF"

start_child "gateway" \
    "$INTELNAV_BIN" gateway \
    --bind "127.0.0.1:$GATEWAY_PORT" \
    --no-mdns >/dev/null
wait_for_port "$GATEWAY_PORT" "gateway"
echo "demo:   gateway ready · http://127.0.0.1:$GATEWAY_PORT"
echo

# Drop a hint for the operator.
cat <<EOF
demo: setup live ─ open http://127.0.0.1:$GATEWAY_PORT in a browser.
demo: tail logs   tail -F $LOG_DIR/{peer-1,peer-2,peer-3,gateway}.{out,err}
demo: stop        Ctrl+C
EOF

# Hold the script so the trap fires on Ctrl+C; surface child crashes.
while true; do
    for i in "${!CHILDREN[@]}"; do
        if ! kill -0 "${CHILDREN[$i]}" 2>/dev/null; then
            echo "demo: ${CHILD_LABELS[$i]} (pid ${CHILDREN[$i]}) exited unexpectedly" >&2
            echo "demo: tail of $LOG_DIR/${CHILD_LABELS[$i]}.err:" >&2
            tail -n 20 "$LOG_DIR/${CHILD_LABELS[$i]}.err" >&2 || true
            exit 1
        fi
    done
    sleep 1
done
