// Taken from src/dependencies/Constants.cairo

const DECIMAL_PRECISION = BigInt(10 ** 18);
const _1pct = BigInt(DECIMAL_PRECISION / BigInt(100));
export const CCR_TBTC = BigInt(150) * _1pct;
export const MCR_TBTC = BigInt(110) * _1pct;

export const SCR_TBTC = BigInt(110) * _1pct;

// Batch CR buffer (same for all branches for now)
// On top of MCR to join a batch, or adjust inside a batch
export const BCR_ALL = BigInt(10) * _1pct;

export const LIQUIDATION_PENALTY_SP_TBTC = BigInt(5) * _1pct;
export const LIQUIDATION_PENALTY_REDISTRIBUTION_TBTC = BigInt(10) * _1pct;