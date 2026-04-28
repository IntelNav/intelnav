# intelnav-crypto

Identity, handshake, and prompt-confidentiality primitives.

- `Identity` — long-lived Ed25519 signing key. `PeerId = multihash(pubkey)`.
  `generate()`, `from_seed(&[u8;32])`, `sign(msg)`, `peer_id()`. The
  daemon stores its seed at `~/.local/share/intelnav/peer.key` (0600);
  the chat client reads the same file so both processes show up to the
  swarm as the same peer.
- `verify(peer_pub, msg, sig)` — signature check.
- `EphemeralHandshake` / `StaticHandshake` — X25519 key exchange.
  Used to set up the end-to-end encrypted prompt channel between the
  chat client and the entry peer in a chain.
- `session_key(shared)` — blake3-XOF key derivation with the
  `"intelnav/v1/prompt"` domain-separation tag. 32 bytes out.
- `encrypt` / `decrypt` — AES-256-GCM over the user prompt with a
  freshly generated 96-bit nonce.

`#![forbid(unsafe_code)]`.
