#!/bin/sh
# shellcheck shell=dash
#
# IntelNav installer.
#
#   curl -fsSL https://intelnav.net/install.sh | sh
#
# Detects OS + arch, picks the right intelnav tarball from
# github.com/IntelNav/intelnav/releases, picks the right libllama
# tarball from github.com/IntelNav/llama.cpp/releases, unpacks both
# into `$HOME/.local/intelnav/` + `$HOME/.cache/intelnav/libllama/`,
# adds the binary to PATH, and runs `intelnav doctor`.
#
# Scope: "it works offline-afterwards." No systemd service setup, no
# dotfile sync, no auto-update. Re-run the script to upgrade.
#
# Options:
#   --backend <cpu|vulkan|rocm|cuda|metal>
#       Pick the libllama variant. Default: auto-detect GPU vendor,
#       fall back to cpu. Pass --backend cpu to opt out of GPU.
#   --prefix <dir>
#       Where binaries + libllama go. Default: $HOME/.local/intelnav.
#   --only-libllama
#       Skip the intelnav binary download; only fetch libllama into
#       the cache. Useful if you built intelnav from source with
#       cargo and just need the runtime library.
#   --no-rc
#       Don't edit ~/.bashrc / ~/.zshrc. You'll handle PATH yourself.
#   --no-doctor
#       Skip the post-install doctor run. CI/automation friendly.
#   --intelnav-tag <tag>   / --libllama-tag <tag>
#       Override the release tags (default: latest).

set -eu

# ---------- defaults ------------------------------------------------
PREFIX="${HOME}/.local/intelnav"
LIBLLAMA_CACHE="${HOME}/.cache/intelnav/libllama"
BACKEND=""
EDIT_RC=1
RUN_DOCTOR=1
ONLY_LIBLLAMA=0
INTELNAV_TAG="latest"
LIBLLAMA_TAG="latest"

INTELNAV_REPO="IntelNav/intelnav"
LLAMA_REPO="IntelNav/llama.cpp"

# ---------- tiny printing helpers ----------------------------------
msg()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[32m✓\033[0m   %s\n'  "$*"; }
warn() { printf '\033[33m!\033[0m   %s\n'  "$*"; }
die()  { printf '\033[31m✗\033[0m   %s\n'  "$*" 1>&2; exit 1; }

# ---------- flags ---------------------------------------------------
while [ $# -gt 0 ]; do
    case "$1" in
        --backend)       BACKEND="$2";         shift 2 ;;
        --prefix)        PREFIX="$2";          shift 2 ;;
        --intelnav-tag)  INTELNAV_TAG="$2";    shift 2 ;;
        --libllama-tag)  LIBLLAMA_TAG="$2";    shift 2 ;;
        --no-rc)         EDIT_RC=0;            shift   ;;
        --no-doctor)     RUN_DOCTOR=0;         shift   ;;
        --only-libllama) ONLY_LIBLLAMA=1;      shift   ;;
        -h|--help)
            sed -n '2,42p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) die "unknown option: $1" ;;
    esac
done

# ---------- dependency check ---------------------------------------
need() { command -v "$1" >/dev/null 2>&1 || die "missing dependency: $1"; }
if command -v curl >/dev/null 2>&1; then
    FETCH="curl -fsSL"
elif command -v wget >/dev/null 2>&1; then
    FETCH="wget -qO-"
else
    die "need either curl or wget in PATH"
fi
need tar
need uname

# ---------- OS × arch detection ------------------------------------
OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
ARCH="$(uname -m)"
case "$OS/$ARCH" in
    linux/x86_64)      OS_ARCH="linux-x64"    ;;
    darwin/arm64)      OS_ARCH="macos-arm64"  ;;
    darwin/x86_64)     die "Intel Macs are not yet supported — build from source for now" ;;
    # Windows users run install.ps1, not this script.
    *)                 die "unsupported platform: $OS/$ARCH" ;;
esac
msg "platform: $OS_ARCH"

# ---------- GPU / backend auto-detect ------------------------------
detect_backend() {
    if [ "$OS" = "darwin" ]; then
        echo "metal"; return
    fi
    if command -v nvidia-smi >/dev/null 2>&1 \
       && nvidia-smi >/dev/null 2>&1; then
        echo "cuda"; return
    fi
    if [ -d /sys/class/drm ]; then
        for card in /sys/class/drm/card*/device/vendor; do
            [ -f "$card" ] || continue
            v=$(cat "$card" 2>/dev/null || true)
            case "$v" in
                0x1002) echo "rocm";   return ;;
                0x10de) echo "cuda";   return ;;
            esac
        done
    fi
    if command -v vulkaninfo >/dev/null 2>&1; then
        echo "vulkan"; return
    fi
    echo "cpu"
}

if [ -z "$BACKEND" ]; then
    BACKEND=$(detect_backend)
    ok "auto-detected backend: $BACKEND"
else
    ok "using backend: $BACKEND (from --backend)"
fi

# Only publish certain (os-arch × backend) combos for now.
case "$OS_ARCH/$BACKEND" in
    linux-x64/cpu|linux-x64/vulkan|linux-x64/rocm|linux-x64/cuda) ;;
    macos-arm64/metal|macos-arm64/cpu) ;;
    *)  warn "no published libllama tarball for $OS_ARCH/$BACKEND; falling back to cpu"
        BACKEND="cpu" ;;
esac

# ---------- resolve release asset URLs -----------------------------
#
# Pack tarballs carry a short SHA in their name, so we can't guess
# the exact URL. Query the GitHub Releases API and match a pattern.
gh_asset_url() {
    repo="$1"; tag="$2"; pattern="$3"
    if [ "$tag" = "latest" ]; then
        api="https://api.github.com/repos/${repo}/releases/latest"
    else
        api="https://api.github.com/repos/${repo}/releases/tags/${tag}"
    fi
    # Tiny JSON parser: find "browser_download_url" lines matching pattern.
    # We avoid jq so the installer has no extra deps.
    json=$($FETCH "$api" || die "could not fetch release info from $api")
    echo "$json" \
        | tr ',{' '\n\n' \
        | grep 'browser_download_url' \
        | grep -F "$pattern" \
        | sed -E 's/.*"browser_download_url"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/' \
        | head -1
}

if [ "$ONLY_LIBLLAMA" = 0 ]; then
    msg "resolving intelnav-cli tarball ($INTELNAV_TAG, $OS_ARCH)"
    INTELNAV_URL=$(gh_asset_url "$INTELNAV_REPO" "$INTELNAV_TAG" "intelnav-${OS_ARCH}-")
    [ -n "$INTELNAV_URL" ] || die "no intelnav-cli asset for $OS_ARCH on tag $INTELNAV_TAG"
    ok "$INTELNAV_URL"
fi

msg "resolving libllama tarball ($LIBLLAMA_TAG, $OS_ARCH, $BACKEND)"
LIBLLAMA_URL=$(gh_asset_url "$LLAMA_REPO" "$LIBLLAMA_TAG" "libllama-${OS_ARCH}-${BACKEND}-")
[ -n "$LIBLLAMA_URL" ] || die "no libllama asset for $OS_ARCH/$BACKEND on tag $LIBLLAMA_TAG"
ok "$LIBLLAMA_URL"

# ---------- download + unpack --------------------------------------
#
# Paths: `$PREFIX/bin/intelnav` + `$LIBLLAMA_CACHE/bin/libllama.so`.
# Staging into tmp first so a failed download doesn't partially
# overwrite an existing install.
STAGE=$(mktemp -d) || die "mktemp failed"
trap 'rm -rf "$STAGE"' EXIT

if [ "$ONLY_LIBLLAMA" = 0 ]; then
    msg "downloading intelnav-cli"
    $FETCH "$INTELNAV_URL" > "$STAGE/intelnav.tar.gz" \
        || die "download failed"
fi
msg "downloading libllama"
$FETCH "$LIBLLAMA_URL" > "$STAGE/libllama.tar.gz" \
    || die "download failed"

mkdir -p "$LIBLLAMA_CACHE"
# `--strip-components=1` drops the top-level `intelnav-<os>-<sha>`
# / `libllama-<os>-<backend>-<sha>` directory name so the resulting
# layout stays stable across upgrades.
if [ "$ONLY_LIBLLAMA" = 0 ]; then
    mkdir -p "$PREFIX"
    tar xzf "$STAGE/intelnav.tar.gz" -C "$PREFIX" --strip-components=1
    ok "unpacked to $PREFIX"
fi
tar xzf "$STAGE/libllama.tar.gz" -C "$LIBLLAMA_CACHE" --strip-components=1
ok "libllama at $LIBLLAMA_CACHE/bin"

# ---------- rc-file wiring -----------------------------------------
RCLINE="# intelnav (installed by install.sh)"
PATH_LINE="export PATH=\"$PREFIX/bin:\$PATH\""
LIBLLAMA_LINE="export INTELNAV_LIBLLAMA_DIR=\"$LIBLLAMA_CACHE/bin\""

install_rc() {
    rc="$1"
    [ -f "$rc" ] || return 0
    if grep -qF "$RCLINE" "$rc" 2>/dev/null; then
        ok "$rc already has an intelnav block"
        return 0
    fi
    {
        printf '\n%s\n' "$RCLINE"
        printf '%s\n'   "$PATH_LINE"
        printf '%s\n'   "$LIBLLAMA_LINE"
    } >> "$rc"
    ok "added intelnav block to $rc"
}

if [ "$EDIT_RC" = 1 ] && [ "$ONLY_LIBLLAMA" = 0 ]; then
    install_rc "$HOME/.bashrc"
    install_rc "$HOME/.zshrc"
    install_rc "$HOME/.config/fish/config.fish"
    # For the current shell session: caller doesn't need to source rc.
    export PATH="$PREFIX/bin:$PATH"
    export INTELNAV_LIBLLAMA_DIR="$LIBLLAMA_CACHE/bin"
elif [ "$ONLY_LIBLLAMA" = 1 ]; then
    ok "libllama-only install; no PATH edit needed"
else
    warn "skipped rc-file edits (--no-rc). You'll need to:"
    printf '         %s\n' "$PATH_LINE"
    printf '         %s\n' "$LIBLLAMA_LINE"
fi

# ---------- doctor --------------------------------------------------
if [ "$RUN_DOCTOR" = 1 ] && [ "$ONLY_LIBLLAMA" = 0 ]; then
    msg "running intelnav doctor"
    # Call intelnav directly so this works even before the caller
    # sources their rc file in a new shell.
    INTELNAV_LIBLLAMA_DIR="$LIBLLAMA_CACHE/bin" "$PREFIX/bin/intelnav" doctor || true
fi

msg "done."
if [ "$ONLY_LIBLLAMA" = 0 ]; then
    ok "intelnav installed to $PREFIX"
fi
ok "libllama at $LIBLLAMA_CACHE/bin"
if [ "$EDIT_RC" = 1 ] && [ "$ONLY_LIBLLAMA" = 0 ]; then
    printf '    open a new shell (or `source ~/.bashrc`) to pick up PATH changes.\n'
fi
