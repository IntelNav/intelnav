#!/bin/sh
# shellcheck shell=dash
#
# install-libllama.sh — fetch a prebuilt libllama tarball into the
# canonical cache path, where IntelNav's auto-discovery finds it.
#
#   bash scripts/install-libllama.sh
#
# Detects OS + arch + GPU vendor, picks the matching tarball from the
# latest `IntelNav/llama.cpp@intelnav-v*` release, unpacks it under
# `~/.cache/intelnav/libllama/<sha>/`, and points the canonical
# `~/.cache/intelnav/libllama/bin` symlink at the new install. Both
# `intelnav` and `intelnav-node` auto-discover that path on startup,
# so once this script finishes there's nothing else to set.
#
# Idempotent: safe to re-run. The previous tarball isn't deleted —
# you can roll back by `ln -sf .../libllama-*-<old_sha>/bin bin` if
# the new release misbehaves.
#
# Options:
#   --backend <cpu|vulkan|rocm|cuda|metal>
#       Pick the libllama variant. Default: auto-detect GPU vendor,
#       fall back to cpu. Pass --backend cpu to opt out of GPU.
#   --tag <intelnav-vN.N.N>
#       Pin a release tag. Default: latest.
#   --prefix <dir>
#       Where libllama lives. Default: $HOME/.cache/intelnav/libllama.

set -eu

CACHE_DIR="${HOME}/.cache/intelnav/libllama"
BACKEND=""
TAG="latest"
LLAMA_REPO="IntelNav/llama.cpp"

while [ $# -gt 0 ]; do
    case "$1" in
        --backend)  BACKEND="$2"; shift 2 ;;
        --tag)      TAG="$2";     shift 2 ;;
        --prefix)   CACHE_DIR="$2"; shift 2 ;;
        -h|--help)
            sed -n '2,28p' "$0" | sed 's/^# \{0,1\}//'
            exit 0 ;;
        *) echo "install-libllama: unknown arg: $1" >&2; exit 2 ;;
    esac
done

require() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "install-libllama: missing required tool: $1" >&2
        exit 1
    fi
}
require curl
require tar

# ---- platform detection -------------------------------------------------

OS="$(uname -s)"
ARCH="$(uname -m)"
case "$OS" in
    Linux)  OS_ID="linux" ;;
    Darwin) OS_ID="macos" ;;
    *) echo "install-libllama: unsupported OS: $OS" >&2; exit 1 ;;
esac
case "$ARCH" in
    x86_64|amd64) ARCH_ID="x64" ;;
    aarch64|arm64) ARCH_ID="arm64" ;;
    *) echo "install-libllama: unsupported arch: $ARCH" >&2; exit 1 ;;
esac

# ---- backend auto-detect ------------------------------------------------

detect_backend() {
    case "$OS_ID-$ARCH_ID" in
        macos-arm64) echo "metal"; return ;;
    esac
    if command -v rocminfo >/dev/null 2>&1 && rocminfo 2>/dev/null | grep -q '^  Name:.*gfx'; then
        echo "rocm"; return
    fi
    if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi >/dev/null 2>&1; then
        echo "cuda"; return
    fi
    if command -v vulkaninfo >/dev/null 2>&1 && vulkaninfo --summary >/dev/null 2>&1; then
        echo "vulkan"; return
    fi
    echo "cpu"
}

if [ -z "$BACKEND" ]; then
    BACKEND="$(detect_backend)"
    echo "install-libllama: detected backend: $BACKEND"
fi

case "$OS_ID-$ARCH_ID-$BACKEND" in
    linux-x64-cpu|linux-x64-vulkan|linux-x64-rocm|linux-x64-cuda) ;;
    macos-arm64-metal) ;;
    *) echo "install-libllama: no tarball published for $OS_ID-$ARCH_ID-$BACKEND" >&2
       echo "  available: linux-x64-{cpu,vulkan,rocm,cuda}, macos-arm64-metal" >&2
       exit 1 ;;
esac

# ---- pick release tag --------------------------------------------------

API="https://api.github.com/repos/${LLAMA_REPO}/releases"
if [ "$TAG" = "latest" ]; then
    # The repo cuts non-tagged releases too (`bootstrap`); we want the
    # latest `intelnav-v*` tag specifically.
    TAG="$(curl -fsSL "$API" \
        | grep -oE '"tag_name": *"intelnav-v[^"]*"' \
        | head -1 \
        | sed -E 's/.*"(intelnav-v[^"]*)".*/\1/')"
    if [ -z "$TAG" ]; then
        echo "install-libllama: couldn't resolve latest intelnav-v* tag" >&2
        exit 1
    fi
fi
echo "install-libllama: tag: $TAG"

PATTERN="libllama-${OS_ID}-${ARCH_ID}-${BACKEND}-"
ASSET_NAME="$(curl -fsSL "${API}/tags/${TAG}" \
    | grep -oE "\"name\": *\"${PATTERN}[a-f0-9]+\\.tar\\.gz\"" \
    | head -1 \
    | sed -E 's/.*"([^"]+)".*/\1/')"
if [ -z "$ASSET_NAME" ]; then
    echo "install-libllama: no asset matching $PATTERN in $TAG" >&2
    exit 1
fi

URL="https://github.com/${LLAMA_REPO}/releases/download/${TAG}/${ASSET_NAME}"
echo "install-libllama: asset: $ASSET_NAME"

# ---- download + extract ------------------------------------------------

mkdir -p "$CACHE_DIR"
cd "$CACHE_DIR"

# Skip the download if we already have this exact asset on disk.
if [ -f "$ASSET_NAME" ]; then
    echo "install-libllama: $ASSET_NAME already cached, skipping download"
else
    curl -fsSL --progress-bar -o "${ASSET_NAME}.partial" "$URL"
    mv "${ASSET_NAME}.partial" "$ASSET_NAME"
fi

EXTRACT_DIR="${ASSET_NAME%.tar.gz}"
if [ ! -d "$EXTRACT_DIR" ]; then
    tar -xzf "$ASSET_NAME"
fi
if [ ! -f "$EXTRACT_DIR/bin/libllama.so" ] && [ ! -f "$EXTRACT_DIR/bin/libllama.dylib" ]; then
    echo "install-libllama: extracted dir doesn't contain libllama.so / .dylib" >&2
    exit 1
fi

# ---- swap the canonical bin symlink -----------------------------------

rm -f bin
ln -s "${EXTRACT_DIR}/bin" bin

cat <<EOF

✓ libllama installed
    backend:    $BACKEND
    tag:        $TAG
    cache:      $CACHE_DIR/$EXTRACT_DIR/bin
    discovered: $CACHE_DIR/bin (symlink, picked up automatically)

intelnav and intelnav-node will find it on next launch.
Run \`intelnav doctor\` to verify.
EOF
