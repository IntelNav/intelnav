fn main() -> anyhow::Result<()> {
    for arg in std::env::args().skip(1) {
        let m = intelnav_model_store::read_model_metadata(&arg)?;
        println!("{arg}");
        println!("  arch         : {:?}", m.architecture);
        println!("  name         : {:?}", m.name);
        println!("  blocks       : {:?}", m.block_count);
        println!("  embed        : {:?}", m.embedding_length);
        println!("  heads        : {:?}", m.head_count);
        println!("  experts      : {:?}", m.expert_count);
        println!("  experts_used : {:?}", m.expert_used_count);
        println!("  is_moe       : {} ({:?})", m.is_moe(), m.moe_label());
    }
    Ok(())
}
