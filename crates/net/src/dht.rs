//! Shard discovery over the Kademlia DHT.
//!
//! Two record types live on the DHT:
//!
//! 1. **Shard provider record** — keyed by `shard_key(cid, start, end)`.
//!    Value: a CBOR-encoded [`ProviderRecord`] describing one peer
//!    that owns this exact slice. Multiple peers PUT-ing the same
//!    key all show up as separate records on `get_record`, so a
//!    fan-out lookup gives the union of providers for a slice.
//!
//! 2. **Model envelope** — keyed by `model_key(cid)`. Value: a
//!    CBOR-encoded [`ModelEnvelope`] with the metadata a fresh peer
//!    needs to join (n_layers, arch, total size). Any provider can
//!    PUT this; conflicts are tolerated because the envelope is
//!    short and idempotent.
//!
//! The DHT is reachable through the [`Libp2pNode::announce_shard`] /
//! [`Libp2pNode::find_shard_providers`] thin wrappers — they queue
//! commands on the swarm task and translate the resulting Kademlia
//! query events back into oneshot replies.

use anyhow::{anyhow, Result};
use libp2p::kad::RecordKey;
use serde::{Deserialize, Serialize};
use tokio::sync::oneshot;

use crate::swarm::{Command, Libp2pNode};

/// One peer that serves a specific layer slice for a model.
///
/// Stored as the value under a Kademlia record key derived from
/// `(model_cid, start, end)`. Multiple providers for the same slice
/// each PUT a separate record under the same key — Kademlia keeps
/// them all and `get_record` returns each as it arrives during the
/// fan-out walk.
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct ProviderRecord {
    /// libp2p peer id, base58-encoded so the wire bytes survive a
    /// round trip through serde without depending on libp2p types.
    pub peer_id:    String,
    /// Multiaddrs the peer listens on (TCP or QUIC) — what callers
    /// dial when they want to connect a chain to this slice.
    pub addrs:      Vec<String>,
    /// Optional `host:port` of the chunk-server for Path-B downloads.
    pub chunks_url: Option<String>,
    /// CID of the model manifest this peer serves (cache-indexed
    /// path under the chunk-server). Lets a fresh peer that only
    /// knows `model_cid` reconstruct the full manifest URL:
    /// `http://<chunks_url>/<manifest_cid>/manifest.json`.
    pub manifest_cid: Option<String>,
    /// Optional `host:port` of the inference TCP listener (`pipe_peer`).
    pub forward_url: Option<String>,
    /// UNIX seconds at which the publishing peer minted this record.
    /// Helps freshness-rank the result set on the consumer side.
    pub minted_at:  u64,
}

/// Lightweight model metadata stored under `model_key(cid)`.
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct ModelEnvelope {
    pub cid:           String,
    pub display_name:  String,
    pub arch:          String,
    pub block_count:   u32,
    pub total_bytes:   u64,
    pub quant:         String,
}

/// Build a Kademlia record key for a (model, layer-range) shard.
///
/// We hash the canonical string `intelnav/shard/v1|<cid>|<start>|<end>`
/// with blake3 so distinct ranges land on distinct DHT buckets and the
/// result is short. blake3 → 32 bytes is well under the kad key size
/// budget.
pub fn shard_key(cid: &str, start: u16, end: u16) -> RecordKey {
    let s = format!("intelnav/shard/v1|{cid}|{start}|{end}");
    let h = blake3::hash(s.as_bytes());
    RecordKey::new(&h.as_bytes().as_slice())
}

/// Build a Kademlia record key for the model envelope.
pub fn model_key(cid: &str) -> RecordKey {
    let s = format!("intelnav/model/v1|{cid}");
    let h = blake3::hash(s.as_bytes());
    RecordKey::new(&h.as_bytes().as_slice())
}

impl Libp2pNode {
    /// Announce that this peer owns the slice `[start..end)` for
    /// model `cid`. The provider record is published to Kademlia and
    /// republished on the configured publication interval — callers
    /// must invoke this periodically (the CLI's announce task does).
    pub async fn announce_shard(
        &self,
        cid: &str,
        start: u16,
        end: u16,
        record: ProviderRecord,
    ) -> Result<()> {
        let key = shard_key(cid, start, end);
        let mut buf = Vec::new();
        ciborium::into_writer(&record, &mut buf)
            .map_err(|e| anyhow!("encode provider record: {e}"))?;
        let (done, rx) = oneshot::channel();
        self.tx.send(Command::AnnounceShard { key, meta: buf, done }).await
            .map_err(|_| anyhow!("swarm task is gone"))?;
        rx.await.map_err(|_| anyhow!("announce reply dropped"))?
    }

    /// Find peers that advertise the slice `[start..end)` for model
    /// `cid`. Returns whatever providers the Kademlia query found
    /// before the iterative walk terminated.
    pub async fn find_shard_providers(
        &self,
        cid: &str,
        start: u16,
        end: u16,
    ) -> Result<Vec<ProviderRecord>> {
        let raw = self.get_record_raw(shard_key(cid, start, end)).await?;
        Ok(raw.into_iter()
            .filter_map(|v| ciborium::from_reader::<ProviderRecord, _>(&v[..]).ok())
            .collect())
    }

    /// Publish the envelope (display name, arch, block count …) for
    /// model `cid` so a fresh peer that only knows the cid can pull
    /// enough metadata to render a row.
    pub async fn announce_model(&self, env: &ModelEnvelope) -> Result<()> {
        let key = model_key(&env.cid);
        let mut buf = Vec::new();
        ciborium::into_writer(env, &mut buf)
            .map_err(|e| anyhow!("encode model envelope: {e}"))?;
        let (done, rx) = oneshot::channel();
        self.tx.send(Command::AnnounceShard { key, meta: buf, done }).await
            .map_err(|_| anyhow!("swarm task is gone"))?;
        rx.await.map_err(|_| anyhow!("announce reply dropped"))?
    }

    /// Look up the envelope for model `cid`. Returns the first record
    /// that decodes cleanly; conflicting envelopes are tolerated since
    /// the schema is small + idempotent.
    pub async fn fetch_model_envelope(&self, cid: &str) -> Result<Option<ModelEnvelope>> {
        let raw = self.get_record_raw(model_key(cid)).await?;
        Ok(raw.into_iter()
            .find_map(|v| ciborium::from_reader::<ModelEnvelope, _>(&v[..]).ok()))
    }

    async fn get_record_raw(&self, key: RecordKey) -> Result<Vec<Vec<u8>>> {
        let (done, rx) = oneshot::channel();
        self.tx.send(Command::GetShardProviders { key, done }).await
            .map_err(|_| anyhow!("swarm task is gone"))?;
        rx.await.map_err(|_| anyhow!("find reply dropped"))?
    }
}
