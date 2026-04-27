//! Cheap GGUF metadata reader for the gateway model picker.
//!
//! Mmaps the file's header, walks the KV table once, and surfaces the
//! handful of fields the SPA needs to label a model: architecture,
//! display name, block count, MoE expert counts, embedding/head
//! widths. Tensor data is never touched — opening a 26 GiB Mixtral
//! GGUF here costs ~milliseconds.
//!
//! Where llama.cpp uses `<arch>.<key>` (e.g. `llama.expert_count`),
//! we don't know the architecture up front, so the parser matches
//! the SUFFIX of each KV key. That keeps us forward-compatible with
//! llama.cpp's per-arch namespacing — if a future model uses a new
//! arch tag, the picker still picks up `expert_count` without code
//! changes.

use std::path::Path;

use serde::{Deserialize, Serialize};

use crate::gguf::{Gguf, KvType};

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct ModelMetadata {
    /// `general.name` if present, otherwise the file stem.
    pub name:                  Option<String>,
    /// `general.architecture` — e.g. `"llama"`, `"qwen2"`,
    /// `"deepseek2"`, `"mixtral"`. Mixtral GGUFs typically carry
    /// `arch = "llama"` with `expert_count > 0` rather than a
    /// dedicated tag, which is why MoE detection is via expert
    /// count rather than the arch string.
    pub architecture:          Option<String>,
    /// `<arch>.block_count` — number of transformer blocks.
    pub block_count:           Option<u32>,
    /// `<arch>.embedding_length` — hidden state width per token.
    pub embedding_length:      Option<u32>,
    /// `<arch>.attention.head_count`.
    pub head_count:            Option<u32>,
    /// `<arch>.expert_count`. `Some(n)` with `n > 1` means MoE.
    pub expert_count:          Option<u32>,
    /// `<arch>.expert_used_count` — number of experts routed per
    /// token (Mixtral=2, DeepSeek-V2-Lite=6, …).
    pub expert_used_count:     Option<u32>,
    /// `<arch>.expert_shared_count` — DeepSeek-style shared
    /// experts that always fire regardless of routing.
    pub expert_shared_count:   Option<u32>,
}

impl ModelMetadata {
    /// True when this model has more than one routed expert per
    /// MoE layer. Avoids confusing single-expert "MoE" arches that
    /// libllama still tags with `expert_count = 1`.
    pub fn is_moe(&self) -> bool {
        matches!(self.expert_count, Some(n) if n > 1)
    }

    /// Short pill the SPA renders next to the model name, e.g.
    /// `"MoE 8×top-2"`. `None` for dense models.
    pub fn moe_label(&self) -> Option<String> {
        let n = self.expert_count?;
        if n <= 1 { return None; }
        let k = self.expert_used_count.unwrap_or(0);
        if k == 0 {
            Some(format!("MoE ×{n}"))
        } else {
            Some(format!("MoE {n}×top-{k}"))
        }
    }
}

/// Open the GGUF at `path` and pull out the metadata fields the
/// gateway model picker cares about. Returns a default-filled
/// [`ModelMetadata`] (rather than erroring) on KV-decode hiccups
/// that aren't fatal — the picker tolerates `None` everywhere.
pub fn read_model_metadata(path: impl AsRef<Path>) -> crate::gguf::Result<ModelMetadata> {
    let g = Gguf::open(path.as_ref())?;
    let mut m = ModelMetadata::default();
    for kv in g.kv_entries()? {
        let val = &g.as_bytes()[kv.value_range.clone()];
        match (kv.ty, kv.key) {
            (KvType::String, "general.name") => {
                m.name = read_str(val);
            }
            (KvType::String, "general.architecture") => {
                m.architecture = read_str(val);
            }
            (KvType::U32, key) if key.ends_with(".block_count") => {
                m.block_count = read_u32(val);
            }
            (KvType::U32, key) if key.ends_with(".embedding_length") => {
                m.embedding_length = read_u32(val);
            }
            (KvType::U32, key) if key.ends_with(".attention.head_count") => {
                m.head_count = read_u32(val);
            }
            (KvType::U32, key) if key.ends_with(".expert_count") => {
                m.expert_count = read_u32(val);
            }
            (KvType::U32, key) if key.ends_with(".expert_used_count") => {
                m.expert_used_count = read_u32(val);
            }
            (KvType::U32, key) if key.ends_with(".expert_shared_count") => {
                m.expert_shared_count = read_u32(val);
            }
            _ => {}
        }
    }
    Ok(m)
}

fn read_u32(bytes: &[u8]) -> Option<u32> {
    if bytes.len() < 4 { return None; }
    Some(u32::from_le_bytes(bytes[..4].try_into().ok()?))
}

fn read_str(bytes: &[u8]) -> Option<String> {
    if bytes.len() < 8 { return None; }
    let len = u64::from_le_bytes(bytes[..8].try_into().ok()?) as usize;
    let body = bytes.get(8..8 + len)?;
    Some(String::from_utf8_lossy(body).into_owned())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn dense_model_is_not_moe() {
        let m = ModelMetadata {
            architecture: Some("qwen2".into()),
            block_count: Some(24),
            ..Default::default()
        };
        assert!(!m.is_moe());
        assert_eq!(m.moe_label(), None);
    }

    #[test]
    fn single_expert_arch_does_not_show_pill() {
        // libllama tags some non-MoE arches with expert_count=1;
        // we want the pill to skip that case.
        let m = ModelMetadata {
            expert_count: Some(1),
            expert_used_count: Some(1),
            ..Default::default()
        };
        assert!(!m.is_moe());
        assert_eq!(m.moe_label(), None);
    }

    #[test]
    fn mixtral_8x_top2_label() {
        let m = ModelMetadata {
            architecture: Some("llama".into()),
            block_count: Some(32),
            expert_count: Some(8),
            expert_used_count: Some(2),
            ..Default::default()
        };
        assert!(m.is_moe());
        assert_eq!(m.moe_label().as_deref(), Some("MoE 8×top-2"));
    }

    #[test]
    fn deepseek_v2_lite_top6_label() {
        // DeepSeek-V2-Lite: 64 routed experts + 2 shared.
        let m = ModelMetadata {
            architecture: Some("deepseek2".into()),
            block_count: Some(27),
            expert_count: Some(64),
            expert_used_count: Some(6),
            expert_shared_count: Some(2),
            ..Default::default()
        };
        assert!(m.is_moe());
        assert_eq!(m.moe_label().as_deref(), Some("MoE 64×top-6"));
    }

    #[test]
    fn moe_with_unknown_topk_falls_back() {
        let m = ModelMetadata {
            expert_count: Some(8),
            ..Default::default()
        };
        assert!(m.is_moe());
        assert_eq!(m.moe_label().as_deref(), Some("MoE ×8"));
    }
}
