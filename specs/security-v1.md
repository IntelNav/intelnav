# IntelNav Security Model — v1 (normative)

The Rust surface for this model is split between `crates/crypto`
(primitives), `crates/wire` (envelope formats), and `crates/net`
(libp2p transport).

## Identity

Long-lived Ed25519 keypair generated on first start; peer ID is
`multihash(pubkey)`. The seed lives at
`~/.local/share/intelnav/peer.key` with mode `0600` and is shared by
the chat client (`intelnav`) and the host daemon (`intelnav-node`),
so they appear to the swarm as the same peer. Implementation in
[`crates/crypto/src/identity.rs`](../crates/crypto/src/identity.rs).

## Prompt confidentiality

Ephemeral X25519 exchange between the chat client and the **entry
peer** of the chain (the peer that owns the lowest layer range). The
shared secret is fed through `session_key()` (blake3-XOF with the
`"intelnav/v1/prompt"` domain-separation tag, 32 bytes out) and used
to AES-256-GCM-encrypt the prompt with a fresh 96-bit nonce per turn.

Mid-chain peers (those owning slices `[k..N)` for `k > 0`) only see
hidden states — never the prompt cleartext. Tail peer (owns the head
slice and produces tokens) sees the sampled token sequence at
generation time but not the prompt cleartext either, since the prompt
was already consumed by the entry peer's embed step.

## Result integrity

`t`-of-`n` quorum over disjoint chains. Default `t=n=1` (single
chain, no quorum) — suitable for low-stakes workloads. Configurable
per-session via the `quorum` field on `Config` and overridable inline
with `/quorum <n>`. Higher quorum trades cost (n× the inference work)
for resistance against a malicious tail peer that returns wrong
tokens.

When a chain is built via the DHT (`SwarmIndex::from_swarm_with_probe`),
disjoint quorums are produced by selecting non-overlapping providers
per range. With only one provider per range, the swarm degrades
gracefully to `t=1` and the user sees a status-line warning.

## Transport

Every libp2p hop uses Noise XX with the peer's static Ed25519 keypair
as long-term identity. The forward inference channel (chat ↔ entry
peer ↔ … ↔ tail peer) currently runs over plain TCP framed with
length-prefixed CBOR `Msg` envelopes; an upcoming patch wraps that
channel in Noise as well, sharing the libp2p stack's session keys.

## Threat model — what's in scope today

| Threat | Status |
| - | - |
| A peer returning corrupted tokens | Quorum (configurable, default off) |
| A peer reading prompt cleartext | Mitigated by X25519 + AES-256-GCM end-to-end with the entry peer |
| A peer reading hidden states | Out of scope: hidden states are non-trivial to reconstruct prompts from but are NOT cryptographically protected mid-chain |
| Bootstrap-list tampering | Mitigated by HTTPS + a future signed manifest (TODO; today: trust on first fetch, cached) |
| Sybil attacks on Kademlia | Out of scope for v1; mitigated weakly by `peer_id` derivation and freshness ranking on `minted_at` |
| A daemon being instructed to host a corrupted slice | Mitigated by content-addressed model CIDs (blake3); a slice's `manifest.json` hash chains down to every chunk |

## Out of scope

- Anonymous routing / onion routing. The DHT exposes peer IDs and
  multiaddrs; building a Tor-like overlay on top is a v2 question.
- Differential privacy on logits. The current sampler doesn't add
  noise at the head; quorum is the only result-integrity tool today.
- Plaintext-in-memory protections. Mid-chain peers see hidden states
  in RAM; assume a peer with kernel-level access to a hop can probe
  state.
