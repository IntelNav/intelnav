//! Shared gateway state — config + peer directories + upstream client.

use std::sync::Arc;

use intelnav_core::Config;
use intelnav_net::{DhtDirectory, MdnsDirectory, PeerDirectory, RegistryDirectory, StaticDirectory};
use intelnav_runtime::Telemetry;

use crate::driver::GatewayDriver;

#[derive(Clone)]
pub struct GatewayState {
    pub config:       Arc<Config>,
    pub http:         reqwest::Client,
    pub static_dir:   Arc<StaticDirectory>,
    pub dht_dir:      Arc<DhtDirectory>,
    pub mdns_dir:     Option<Arc<MdnsDirectory>>,
    pub registry_dir: Option<Arc<RegistryDirectory>>,
    pub started_at:   std::time::Instant,
    /// Broadcast channel of [`intelnav_runtime::StepEvent`]. Real
    /// events come from the chain driver below when set; otherwise
    /// [`crate::server::run`] spawns a synth heartbeat loop so the
    /// SPA's `/v1/swarm/events` SSE always has *something* to show.
    /// Each event carries `synthetic: true` until real data replaces
    /// it.
    pub telemetry:    Telemetry,
    /// Optional chain-mode driver. When `Some`, `/v1/chat/completions`
    /// runs the configured peer chain locally instead of proxying to
    /// upstream — events flow through `telemetry`, the SPA shows
    /// real numbers, the chat physically routes through the visible
    /// peers. Enabled by setting `INTELNAV_GATEWAY_MODEL` to a GGUF
    /// path at startup.
    pub driver:       Option<GatewayDriver>,
}

impl GatewayState {
    pub fn directories(&self) -> Vec<Arc<dyn PeerDirectory>> {
        let mut v: Vec<Arc<dyn PeerDirectory>> = Vec::new();
        v.push(self.static_dir.clone());
        v.push(self.dht_dir.clone());
        if let Some(m) = &self.mdns_dir {
            v.push(m.clone());
        }
        if let Some(r) = &self.registry_dir {
            v.push(r.clone());
        }
        v
    }
}
