#!/usr/bin/env bash
#
# local-swarm.sh — spin up a real multi-peer IntelNav chain on one
# machine. Three intelnav-node daemons each host a contiguous layer
# range of Qwen 2.5 · 0.5B (24 blocks split 0..6 / 6..12 / 12..18 /
# 18..24). The client (intelnav) drives a chain through them as
# layers 0..6 + head; the three daemons cover 6..24.
#
# This isn't a mock — every wire is the real protocol. The daemons
# really run forward_server, the client really uses ChainDriver to
# assemble the chain over TCP. The only sandbox is "all on one box";
# in production the same code runs across many machines.
#
# Usage:
#     bash scripts/local-swarm.sh setup     # one-off: prepare slices
#     bash scripts/local-swarm.sh start     # spawn the 3 daemons
#     bash scripts/local-swarm.sh chat      # open the TUI, chain wired
#     bash scripts/local-swarm.sh ask "..."   # one-shot prompt through the chain
#     bash scripts/local-swarm.sh stop      # kill all daemons
#     bash scripts/local-swarm.sh status    # ports + pids
#
# Requirements:
#     - intelnav and intelnav-node on PATH
#     - libllama auto-discovered (~/.cache/intelnav/libllama/bin)
#     - Qwen 2.5 · 0.5B in your local cache (run intelnav once and
#       hit /models → Enter on the row; the GGUF lands in
#       ~/.local/share/intelnav/models)
#
# Layout under /tmp/intelnav-swarm:
#     peer-a/   {config, data, log}        port 7717   layers 6..12
#     peer-b/   {config, data, log}        port 7718   layers 12..18
#     peer-c/   {config, data, log}        port 7719   layers 18..24

set -euo pipefail

ROOT=/tmp/intelnav-swarm
GGUF_NAME="qwen2.5-0.5b-instruct-q4_k_m.gguf"
USER_GGUF="${HOME}/.local/share/intelnav/models/${GGUF_NAME}"
USER_TOK="${HOME}/.local/share/intelnav/models/qwen2.5-0.5b-instruct-q4_k_m.tokenizer.json"

# Model CID. The chat client sends the GGUF file stem as the wire
# `model_cid` in SessionInit (see chain_driver.rs); the daemon's
# forward_server matches against the cid recorded in kept_ranges.json.
# For this sandbox we use the file stem on both sides, so .shards/<cid>/
# = .shards/<filename without .gguf>/.
MODEL_CID="qwen2.5-0.5b-instruct-q4_k_m"

# Three peers, three middle/tail slices. Port range 17717+ chosen
# to avoid collisions with the user's main daemon (which usually
# binds 7717 / 8765 / 4001).
PEER_PORTS=(17717 17718 17719)
PEER_NAMES=(peer-a peer-b peer-c)
PEER_RANGES=("6 12" "12 18" "18 24")
LIBP2P_PORTS=(14101 14102 14103)
CHUNKS_PORTS=(18101 18102 18103)

err()  { printf "\033[31m%s\033[0m\n" "$*" >&2; }
say()  { printf "\033[36m%s\033[0m\n" "$*"; }
ok()   { printf "\033[32m%s\033[0m\n" "$*"; }

require() {
    if ! command -v "$1" >/dev/null 2>&1; then
        err "missing: $1 (install or symlink target/release into PATH)"; exit 1
    fi
}

# ----------------------------------------------------------------------
# setup — prepare the four peer dirs.
# ----------------------------------------------------------------------
cmd_setup() {
    require intelnav
    require intelnav-node

    if [ ! -f "$USER_GGUF" ]; then
        err "missing $USER_GGUF"
        err "run \`intelnav\`, /models → highlight Qwen 0.5B → Enter, then re-run setup."
        exit 1
    fi

    say "→ wiping any prior swarm state at $ROOT"
    rm -rf "$ROOT"
    mkdir -p "$ROOT"

    for i in "${!PEER_NAMES[@]}"; do
        local name="${PEER_NAMES[$i]}"
        local range="${PEER_RANGES[$i]}"
        local libp2p_port="${LIBP2P_PORTS[$i]}"
        local chunks_port="${CHUNKS_PORTS[$i]}"
        local forward_port="${PEER_PORTS[$i]}"

        local dir="$ROOT/$name"
        mkdir -p \
            "$dir/config/intelnav" \
            "$dir/data/intelnav/models/.shards/$MODEL_CID" \
            "$dir/log"

        # Each peer owns one slice. forward_server reads
        # kept_ranges.json on demand and lazy-loads the GGUF for
        # whichever range the chain is asking about. Since
        # gguf_path is the full GGUF, no chunking / stitching is
        # needed for this sandbox.
        cat > "$dir/data/intelnav/models/.shards/$MODEL_CID/kept_ranges.json" <<EOF
{
    "model_cid":    "$MODEL_CID",
    "display_name": "Qwen 2.5 · 0.5B · Instruct",
    "block_count":  24,
    "gguf_path":    "$USER_GGUF",
    "kept":         [[${range/ /, }]]
}
EOF

        # config.toml — hand-pinned so the auto-config in firstrun
        # doesn't drift the ports.
        cat > "$dir/config/intelnav/config.toml" <<EOF
mode           = "network"
default_model  = "qwen2.5-0.5b-instruct-q4_k_m"
default_tier   = "lan"
allow_wan      = false
quorum         = 1
device         = "auto"
relay_only     = false
libp2p_listen  = "/ip4/127.0.0.1/tcp/$libp2p_port"
chunks_addr    = "127.0.0.1:$chunks_port"
forward_addr   = "127.0.0.1:$forward_port"
bootstrap      = []
EOF
    done

    ok "✓ swarm prepared at $ROOT"
    ls -la "$ROOT"
}

# ----------------------------------------------------------------------
# start / stop / status — daemon lifecycle.
# ----------------------------------------------------------------------
peer_pid_file() { echo "$ROOT/$1/log/pid"; }
peer_log_file() { echo "$ROOT/$1/log/out.log"; }

cmd_start() {
    [ -d "$ROOT" ] || { err "no swarm — run \`local-swarm.sh setup\` first"; exit 1; }
    require intelnav-node

    for i in "${!PEER_NAMES[@]}"; do
        local name="${PEER_NAMES[$i]}"
        local dir="$ROOT/$name"
        local pidfile; pidfile="$(peer_pid_file "$name")"
        local logfile; logfile="$(peer_log_file "$name")"

        if [ -f "$pidfile" ] && kill -0 "$(cat "$pidfile")" 2>/dev/null; then
            say "→ $name already running (pid $(cat "$pidfile"))"
            continue
        fi

        XDG_CONFIG_HOME="$dir/config" \
        XDG_DATA_HOME="$dir/data" \
        INTELNAV_RELAY_ONLY=0 \
            intelnav-node > "$logfile" 2>&1 &
        echo $! > "$pidfile"
        ok "✓ started $name pid=$! port=${PEER_PORTS[$i]} layers=${PEER_RANGES[$i]}"
    done

    say "→ waiting 2 s for daemons to bind..."
    sleep 2

    for i in "${!PEER_NAMES[@]}"; do
        local port="${PEER_PORTS[$i]}"
        if (echo > /dev/tcp/127.0.0.1/$port) 2>/dev/null; then
            ok "  ✓ ${PEER_NAMES[$i]}: TCP $port reachable"
        else
            err "  ✗ ${PEER_NAMES[$i]}: TCP $port NOT reachable — see $(peer_log_file "${PEER_NAMES[$i]}")"
        fi
    done
}

cmd_stop() {
    [ -d "$ROOT" ] || { say "no swarm to stop"; exit 0; }
    for name in "${PEER_NAMES[@]}"; do
        local pidfile; pidfile="$(peer_pid_file "$name")"
        if [ -f "$pidfile" ]; then
            local pid; pid="$(cat "$pidfile")"
            if kill -0 "$pid" 2>/dev/null; then
                kill -TERM "$pid"
                ok "✓ stopped $name (pid $pid)"
            fi
            rm -f "$pidfile"
        fi
    done
}

cmd_status() {
    [ -d "$ROOT" ] || { say "no swarm — run \`local-swarm.sh setup\`"; exit 0; }
    for i in "${!PEER_NAMES[@]}"; do
        local name="${PEER_NAMES[$i]}"
        local pidfile; pidfile="$(peer_pid_file "$name")"
        local pid="—"
        local state="stopped"
        if [ -f "$pidfile" ] && kill -0 "$(cat "$pidfile")" 2>/dev/null; then
            pid="$(cat "$pidfile")"; state="running"
        fi
        printf "  %-7s %-10s pid=%s  forward=127.0.0.1:%s  layers=%s\n" \
            "$name" "$state" "$pid" "${PEER_PORTS[$i]}" "${PEER_RANGES[$i]}"
    done
}

# ----------------------------------------------------------------------
# chat / ask — drive a chain through the swarm.
# ----------------------------------------------------------------------
cmd_chat() {
    require intelnav

    # The chat client also needs an isolated env (its own peer.key,
    # config) so it doesn't collide with the user's main install.
    local cdir="$ROOT/client"
    mkdir -p "$cdir/config/intelnav" "$cdir/data/intelnav/models"
    # Symlink the model into the client's models dir so it can be
    # picked as the active model.
    ln -sf "$USER_GGUF"  "$cdir/data/intelnav/models/$GGUF_NAME"
    ln -sf "$USER_TOK"   "$cdir/data/intelnav/models/qwen2.5-0.5b-instruct-q4_k_m.tokenizer.json"

    cat > "$cdir/config/intelnav/config.toml" <<EOF
mode           = "network"
default_model  = "qwen2.5-0.5b-instruct-q4_k_m"
default_tier   = "lan"
allow_wan      = true
quorum         = 1
device         = "auto"
relay_only     = true
libp2p_listen  = "/ip4/127.0.0.1/tcp/4100"
peers          = ["127.0.0.1:17717", "127.0.0.1:17718", "127.0.0.1:17719"]
splits         = [6, 12, 18]
bootstrap      = []
EOF

    say "→ chat client → 0..6 (driver) → peers @ 6..12, 12..18, 18..24"
    XDG_CONFIG_HOME="$cdir/config" \
    XDG_DATA_HOME="$cdir/data" \
    INTELNAV_RELAY_ONLY=1 \
        intelnav
}

cmd_ask() {
    require intelnav
    local cdir="$ROOT/client"
    local prompt="${1:-what is 17 squared?}"

    if [ ! -d "$cdir" ]; then
        err "no client config — run \`local-swarm.sh chat\` once to bootstrap, or just run again"
        # Build minimal client config so ask works standalone.
        mkdir -p "$cdir/config/intelnav" "$cdir/data/intelnav/models"
        ln -sf "$USER_GGUF" "$cdir/data/intelnav/models/$GGUF_NAME"
        ln -sf "$USER_TOK"  "$cdir/data/intelnav/models/qwen2.5-0.5b-instruct-q4_k_m.tokenizer.json"
        cat > "$cdir/config/intelnav/config.toml" <<EOF
mode           = "network"
default_model  = "qwen2.5-0.5b-instruct-q4_k_m"
peers          = ["127.0.0.1:17717", "127.0.0.1:17718", "127.0.0.1:17719"]
splits         = [6, 12, 18]
relay_only     = true
EOF
    fi

    say "→ asking the swarm: $prompt"
    echo "$prompt" | XDG_CONFIG_HOME="$cdir/config" \
                    XDG_DATA_HOME="$cdir/data" \
                    INTELNAV_RELAY_ONLY=1 \
                        intelnav --mode network ask --model qwen2.5-0.5b-instruct-q4_k_m
}

# ----------------------------------------------------------------------
# Entry.
# ----------------------------------------------------------------------
case "${1:-}" in
    setup)   cmd_setup ;;
    start)   cmd_start ;;
    stop)    cmd_stop ;;
    status)  cmd_status ;;
    chat)    cmd_chat ;;
    ask)     shift; cmd_ask "${1:-}" ;;
    "")      sed -n '2,28p' "$0" | sed 's/^# \{0,1\}//' ;;
    *)       err "unknown command: $1"; sed -n '2,28p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
