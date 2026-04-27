# IntelNav

**Decentralized, pipeline-parallel LLM inference on ordinary hardware.**

IntelNav chops a large language model into layer slices, spreads the slices
across peers, and streams hidden states through the chain to answer a prompt.
No single peer holds the whole model; prompts are encrypted end-to-end.

```
   prompt ──► [you: layers 0..k) ──► peer A: [k..m) ──► peer B: [m..N) ──► tokens
```

This repository is the reference implementation — a Rust workspace plus a
Python host for the contributor shard server.

---

## Quickstart

```bash
# one-shot bootstrap (installs system deps + rust)
bash scripts/provision.sh

# build the CLI
cargo build --release -p intelnav-cli

# single-node chat against a local GGUF
export INTELNAV_MODELS_DIR=/path/to/models_dir
./target/release/intelnav chat
```

`scripts/provision.sh` handles Debian/Ubuntu, Fedora, Arch, and macOS.

---

## Layout

```
intelnav/
├── Cargo.toml            workspace root
├── crates/
│   ├── core/             shared types, config, errors
│   ├── wire/             CBOR codecs for the protocol
│   ├── crypto/           Ed25519, X25519, AES-256-GCM
│   ├── net/              peer directories (static, mDNS, registry, DHT stub)
│   ├── runtime/          layer-range inference (ggml-backed)
│   ├── ggml/             libllama loader + GPU backend probe
│   ├── model-store/      GGUF chunker, stitcher, fetch + serve
│   ├── registry/         shard-registry coordinator
│   └── cli/              the `intelnav` binary (chat REPL, operator commands)
├── python/
│   └── intelnav_shard/   llama.cpp-backed contributor shard server
└── specs/                wire protocol + registry specs
```

---

## License

Apache-2.0.
