pub mod Constants {
    // Core constants
    pub const MAX_UINT256: u256 =
        0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
    pub const DECIMAL_PRECISION: u256 = 1000000000000000000; // 1e18
    pub const _100PCT: u256 = DECIMAL_PRECISION;
    pub const _1PCT: u256 = DECIMAL_PRECISION / 100;

    // TODO: Should be lower here or inexistant.
    // Amount of ETH to be locked in gas pool on opening troves (0.0375 ETH in wei)
    pub const ETH_GAS_COMPENSATION: u256 = 37500000000000000; // 0.0375 ether

    // Liquidation
    pub const MIN_LIQUIDATION_PENALTY_SP: u256 = 5 * _1PCT; // 5% (5e16)
    pub const MAX_LIQUIDATION_PENALTY_REDISTRIBUTION: u256 = 20 * _1PCT; // 20% (20e16)

    // Collateral branch parameters
    pub const CCR_WETH: u256 = 150 * _1PCT; // 150%
    pub const CCR_SETH: u256 = 160 * _1PCT; // 160%
    pub const MCR_WETH: u256 = 110 * _1PCT; // 110%
    pub const MCR_SETH: u256 = 120 * _1PCT; // 120%
    pub const SCR_WETH: u256 = 110 * _1PCT; // 110%
    pub const SCR_SETH: u256 = 120 * _1PCT; // 120%

    // Batch CR buffer (same for all branches for now)
    pub const BCR_ALL: u256 = 10 * _1PCT; // 10%

    pub const LIQUIDATION_PENALTY_SP_WETH: u256 = 5 * _1PCT; // 5%
    pub const LIQUIDATION_PENALTY_SP_SETH: u256 = 5 * _1PCT; // 5%
    pub const LIQUIDATION_PENALTY_REDISTRIBUTION_WETH: u256 = 10 * _1PCT; // 10%
    pub const LIQUIDATION_PENALTY_REDISTRIBUTION_SETH: u256 = 20 * _1PCT; // 20%

    // Fraction of collateral awarded to liquidator
    pub const COLL_GAS_COMPENSATION_DIVISOR: u256 = 200; // dividing by 200 yields 0.5%
    pub const COLL_GAS_COMPENSATION_CAP: u256 = 2000000000000000000; // 2 ETH

    // Minimum amount of net bitUSD debt a trove must have
    pub const MIN_DEBT: u256 = 2000 * DECIMAL_PRECISION; // 2000e18

    pub const MIN_ANNUAL_INTEREST_RATE: u256 = _1PCT / 2; // 0.5%
    pub const MAX_ANNUAL_INTEREST_RATE: u256 = 250 * _1PCT; // 250%

    // Batch management params
    pub const MAX_ANNUAL_BATCH_MANAGEMENT_FEE: u128 = 100000000000000000; // 10% (1e17)
    pub const MIN_INTEREST_RATE_CHANGE_PERIOD: u64 = 3600; // 1 hour in seconds

    pub const REDEMPTION_FEE_FLOOR: u256 = _1PCT / 2; // 0.5%

    // Max batch shares ratio
    pub const MAX_BATCH_SHARES_RATIO: u256 = 1000000000; // 1e9

    // Half-life of 6h
    pub const REDEMPTION_MINUTE_DECAY_FACTOR: u256 = 998076443575628800;

    // BETA parameter
    pub const REDEMPTION_BETA: u256 = 1;

    // Initial base rate
    pub const INITIAL_BASE_RATE: u256 = _100PCT; // 100% initial redemption rate

    // Urgent redemption bonus
    pub const URGENT_REDEMPTION_BONUS: u256 = 2 * _1PCT; // 2% (2e16)

    // Time constants
    pub const ONE_MINUTE: u64 = 60; // 1 minute in seconds
    pub const ONE_YEAR: u64 = 31536000; // 365 days in seconds
    pub const UPFRONT_INTEREST_PERIOD: u64 = 604800; // 7 days in seconds
    pub const INTEREST_RATE_ADJ_COOLDOWN: u64 = 604800; // 7 days in seconds

    pub const SP_YIELD_SPLIT: u256 = 75 * _1PCT; // 75%
    pub const MIN_BIT_USD_IN_SP: u256 = DECIMAL_PRECISION; // 1e18
}
