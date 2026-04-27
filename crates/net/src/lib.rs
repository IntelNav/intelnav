//! `intelnav-net` — peer discovery & network substrate.
//!
//! [`swarm::Libp2pNode`] is the long-lived libp2p host: TCP +
//! Noise XX + yamux + identify + ping + Kademlia. The shard index
//! lives on top of Kademlia in [`dht`] — peers PUT a provider
//! record per `(model_cid, layer_range)` slice they own and GET to
//! discover who else does.
//!
//! Three directory implementations exist alongside the swarm for the
//! boot path before the DHT routing table is populated:
//!
//! * [`StaticDirectory`] — hardcoded peers from config.
//! * [`MdnsDirectory`]   — mDNS/Bonjour local-network discovery.
//! * [`RegistryDirectory`] — periodically polls a shard-registry HTTP API.

#![forbid(unsafe_code)]

pub mod dht;
pub mod directory;
pub mod mdns;
pub mod registry_dir;
pub mod swarm;
pub mod swarm_index;

pub use dht::{model_key, shard_key, ModelEnvelope, ProviderRecord};
pub use directory::{PeerDirectory, PeerRecord, StaticDirectory};
pub use mdns::MdnsDirectory;
pub use registry_dir::RegistryDirectory;
pub use swarm::{
    spawn as spawn_libp2p_node, identity_to_keypair, IdentifiedPeer, IntelNavBehaviour,
    Libp2pNode, AGENT_VERSION, PROTOCOL_VERSION,
};
pub use libp2p::Multiaddr;
pub use swarm_index::{RangeCoverage, SwarmIndex, SwarmModel};
