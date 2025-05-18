pub mod conversion_lib {
    pub fn u256_from_u64(x: u64) -> u256 {
        u256 { low: x.into(), high: 0 }
    }
}
