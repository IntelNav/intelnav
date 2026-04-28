# intelnav-cli

The user-facing `intelnav` binary. Ratatui-based chat TUI plus a few
operator subcommands. Thin wrapper over `intelnav-app` — every
substantive code path lives there so `intelnav-node` can share it.

### Subcommands

```
intelnav                      # default: chat (interactive TUI)
intelnav chat                 # explicit
intelnav ask [prompt]         # non-interactive one-shot (stdin if no arg)
intelnav models [--json]      # list cached local models
intelnav doctor               # preflight (libllama, identity, GPU, models)
intelnav init [--force]       # write default config + generate peer identity
```

First-run UX is automatic: `intelnav` writes `config.toml`, generates
`peer.key`, picks free `chunks_addr` / `forward_addr` ports, fetches
the bootstrap seed list, auto-discovers libllama in
`~/.cache/intelnav/libllama/bin`, and probes the GPU to set
`HSA_OVERRIDE_GFX_VERSION` if the card needs it. `intelnav init` is
only there for the `--force` regenerate path.

### Slash commands inside the TUI

```
/help                                 list commands
/models                               three-source picker (local · swarm · hub)
/hosting                              what slices you host + active chains
/leave [<n> | <cid> <start> <end>]    drain a slice
/service install|status|uninstall     manage the intelnav-node systemd unit
/peers host:port,... split,...        ad-hoc pipeline chain
/draft <path> [k]                     enable speculative decoding
/wire fp16|int8                       activation dtype on the chain
/mode local|network                   pick backend
/model <name>                         switch active model
/keybindings                          full keyboard shortcut list
/doctor                               preflight inline
/clear                                clear transcript
/quit                                 exit
```

### Keybindings

`/keybindings` prints the canonical list. Highlights:

- `Esc Esc` — clear input (double-tap within 600 ms)
- `\` + `Enter` — newline (alongside `Shift+Enter`)
- `Ctrl+G` — edit current input in `$EDITOR`
- `Ctrl+Shift+_` — undo last input edit
- `Alt+P` — cycle to next cached model
- `Ctrl+L` — clear transcript

### Config + env

Config lives at `$XDG_CONFIG_HOME/intelnav/config.toml`. Every field
is overridable via `INTELNAV_*` env vars — see
[`crates/core/src/config.rs`](../core/src/config.rs) for the full
list. The ones you'll touch most:

- `INTELNAV_MODE` — `local | network`.
- `INTELNAV_MODELS_DIR` — where to scan for local GGUFs.
- `INTELNAV_LIBLLAMA_DIR` — override libllama discovery.
- `INTELNAV_RELAY_ONLY` — skip the contribution gate (DHT-only mode).
- `INTELNAV_PEERS` + `INTELNAV_SPLITS` — ad-hoc pipeline chain.
- `INTELNAV_WIRE_DTYPE` — `fp16 | int8`.

### Logging

When the TUI is active, tracing output + raw FD 2 are redirected to
`$XDG_STATE_HOME/intelnav/intelnav.log` so native deps can't paint
over the Ratatui canvas. `-v` = debug, `-vv` = trace.

`#![deny(unsafe_code)]` except for the `libc::dup2` stderr redirect,
which is inline-`#[allow(unsafe_code)]` with justification.
