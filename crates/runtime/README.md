# intelnav-runtime

Layer-range inference backend — the piece that lets a peer run just
*some* of a model's layers on a hidden state and pass the result along.

### Backend

`libllama` (a fork at `IntelNav/llama.cpp` with patches for layer-range
forward + partial-model loading). Loaded lazily via `dlopen` from the
directory at `INTELNAV_LIBLLAMA_DIR/bin/`. The shim crate
`intelnav-ggml` brokers the FFI; `intelnav-runtime` consumes that
through `ModelHandle` / `Pipelined` and never touches libllama's C
surface directly.

### Modules

| Module          | Purpose                                                |
| --------------- | ------------------------------------------------------ |
| `device`        | `DevicePref::{Auto, Cpu, Cuda, Rocm, Metal, Vulkan}`.  |
| `model`         | `ModelHandle`, `ModelKind::from_arch` (sniffs GGUF).   |
| `pipeline`      | `Forwarding` / `Pipelined` traits — ggml plug points.  |
| `ggml_backend`  | libllama loader + range-forward / KV-truncate calls.   |
| `tokenizer`     | Loader + Qwen chat template.                           |
| `generate`      | Greedy / top-p sampler with repeat penalty.            |
| `chain`         | N-peer pipeline client: `Chain`, `ChainCfg`, `run_turn`. |
| `spec`          | Speculative decoding v1 (greedy draft-verify with compute/transfer overlap). |
| `sample`        | Sampler: temperature, top-p, repeat penalty.           |
| `probe`         | Host probe (backend + CPU/RAM + micro-bench).          |
| `telemetry`     | Per-hop timing for the SSE feed.                       |

### Examples

| Example       | Purpose                                            |
| ------------- | -------------------------------------------------- |
| `generate`    | Single-process end-to-end generation.              |
| `probe`       | One-shot host characterization.                    |
| `bench_chain` | Per-segment percentiles + end-to-end tok/s.        |
| `bench_ggml`  | libllama micro-bench across decode lengths.        |
| `smoke_load`  | GGUF load smoke test.                              |

The standalone `pipe_peer` / `pipe_driver` examples were retired —
their job (forward TCP listener) now lives in `intelnav-node` via
`crates/app/src/forward_server.rs`, which calls into this crate's
`ModelHandle::forward_range` directly.

Run any example with `cargo run --release -p intelnav-runtime --example <name> -- …`.

`#![forbid(unsafe_code)]`.
