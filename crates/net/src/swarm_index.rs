//! Swarm-side model index.
//!
//! [`SwarmIndex`] sits on top of the Kademlia DHT and answers the
//! question the TUI's `/models` browser actually cares about:
//! *"which models can the network serve me right now, and how
//! complete is the coverage for each?"*
//!
//! The DHT only stores per-`(cid, start, end)` provider records and
//! per-`cid` model envelopes — it has no built-in enumeration. The
//! caller hands us a list of candidate models (from the local
//! catalog, mDNS hints, or peer gossip) and a set of candidate
//! ranges per model; we fan out the queries in parallel and produce
//! one [`SwarmModel`] summary per cid.
//!
//! The `ranges_to_probe` strategy lives at the call site: for a
//! known catalog model with N layers and a four-peer split, the
//! catalog supplies `[(0,8), (8,16), (16,24), (24,32)]`. Beta peers
//! use whatever splits the network has standardized for that model.

use std::sync::Arc;

use anyhow::Result;
use futures::future::join_all;
use serde::{Deserialize, Serialize};

use crate::dht::{ModelEnvelope, ProviderRecord};
use crate::swarm::Libp2pNode;

/// Aggregated swarm view of one model: the envelope, plus, for each
/// candidate slice, the set of providers that announced it.
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct SwarmModel {
    pub cid:       String,
    pub envelope:  Option<ModelEnvelope>,
    pub ranges:    Vec<RangeCoverage>,
}

/// One slice's coverage on the swarm.
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct RangeCoverage {
    pub start:     u16,
    pub end:       u16,
    pub providers: Vec<ProviderRecord>,
}

impl SwarmModel {
    /// Distinct providers across every probed range. A peer that
    /// advertises three slices counts once.
    pub fn unique_providers(&self) -> usize {
        let mut ids: std::collections::HashSet<&str> = std::collections::HashSet::new();
        for r in &self.ranges {
            for p in &r.providers {
                ids.insert(&p.peer_id);
            }
        }
        ids.len()
    }

    /// Ranges (start, end) the swarm has nobody for. Useful in the
    /// TUI to surface "this model isn't actually serveable yet" or
    /// "you could contribute slice X".
    pub fn gaps(&self) -> Vec<(u16, u16)> {
        self.ranges.iter()
            .filter(|r| r.providers.is_empty())
            .map(|r| (r.start, r.end))
            .collect()
    }

    /// Whether every probed range has at least one provider.
    pub fn fully_served(&self) -> bool {
        !self.ranges.is_empty() && self.ranges.iter().all(|r| !r.providers.is_empty())
    }
}

/// Wrap a [`Libp2pNode`] handle behind a small index API.
#[derive(Clone)]
pub struct SwarmIndex {
    node: Arc<Libp2pNode>,
}

impl SwarmIndex {
    pub fn new(node: Arc<Libp2pNode>) -> Self {
        Self { node }
    }

    /// Refresh one model's coverage. Probes every candidate range in
    /// parallel and the model envelope. Returns a populated
    /// [`SwarmModel`] regardless of how many ranges responded —
    /// gaps are first-class in the result.
    pub async fn refresh_one(&self, cid: &str, ranges: &[(u16, u16)]) -> Result<SwarmModel> {
        let envelope = self.node.fetch_model_envelope(cid).await.unwrap_or(None);

        let probes = ranges.iter().map(|(s, e)| {
            let node = self.node.clone();
            let cid = cid.to_string();
            let s = *s; let e = *e;
            async move {
                let providers = node.find_shard_providers(&cid, s, e).await
                    .unwrap_or_default();
                RangeCoverage { start: s, end: e, providers }
            }
        });
        let results = join_all(probes).await;

        Ok(SwarmModel {
            cid: cid.to_string(),
            envelope,
            ranges: results,
        })
    }

    /// Refresh every model in `requests`. One in-flight query per
    /// model plus per-range fan-out gives us at most
    /// `models * ranges` concurrent kad queries — kad caps that
    /// internally so it's fine to fire all at once.
    pub async fn refresh_many(
        &self,
        requests: &[(String, Vec<(u16, u16)>)],
    ) -> Vec<SwarmModel> {
        let probes = requests.iter().map(|(cid, ranges)| {
            let me = self.clone();
            let cid = cid.clone();
            let ranges = ranges.clone();
            async move {
                me.refresh_one(&cid, &ranges).await.ok()
            }
        });
        join_all(probes).await.into_iter().flatten().collect()
    }
}
