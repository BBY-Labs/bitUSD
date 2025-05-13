pub mod math_lib {
    use crate::dependencies::Constants::Constants::DECIMAL_PRECISION;

    pub fn sub_min_0(a: u256, b: u256) -> u256 {
        if a > b {
            a - b
        } else {
            0
        }
    }

    /// Multiply two decimal numbers and use normal rounding rules:
    /// -round product up if 19'th mantissa digit >= 5
    /// -round product down if 19'th mantissa digit < 5
    /// Used only inside the exponentiation, _decPow()
    pub fn dec_mul(x: u256, y: u256) -> u256 {
        let prod_xy = x * y;
        (prod_xy + (DECIMAL_PRECISION / 2)) / DECIMAL_PRECISION
    }

    /// _decPow: Exponentiation function for 18-digit decimal base, and integer exponent n.
    /// Uses the efficient "exponentiation by squaring" algorithm. O(log(n)) complexity.
    /// Called by function CollateralRegistry._calcDecayedBaseRate, that represent time in units of
    /// minutes The exponent is capped to avoid reverting due to overflow. The cap 525600000 equals
    /// "minutes in 1000 years": 60 * 24 * 365 * 1000
    /// If a period of > 1000 years is ever used as an exponent in either of the above functions,
    /// the result will be negligibly different from just passing the cap, since:
    /// In function 1), the decayed base rate will be 0 for 1000 years or > 1000 years
    /// In function 2), the difference in tokens issued at 1000 years and any time > 1000 years,
    /// will be negligible
    pub fn dec_pow(base: u256, minutes: u256) -> u256 {
        const CAP: u256 = 525_600_000; // cap = number of minutes in 1000 years, to avoid overflow.

        let mut n = if minutes > CAP {
            CAP
        } else {
            minutes
        };
        if n == 0 {
            return DECIMAL_PRECISION;
        }

        let mut y = DECIMAL_PRECISION;
        let mut x = base;

        // Exponentiation by squaring
        while n > 1 {
            if n % 2 == 0 {
                x = dec_mul(x, x);
                n = n / 2;
            } else {
                // if (n % 2 != 0)
                y = dec_mul(x, y);
                x = dec_mul(x, x);
                n = (n - 1) / 2;
            }
        }

        dec_mul(x, y)
    }

    pub fn get_absolute_difference(a: u256, b: u256) -> u256 {
        if a >= b {
            a - b
        } else {
            b - a
        }
    }

    pub fn compute_cr(coll: u256, debt: u256, price: u256) -> u256 {
        if debt > 0 {
            (coll * price) / debt
        } // Return the maximal value for uint256 if the debt is 0. Represents "infinite" CR.
        else {
            // if (_debt == 0)
            let max_uint256: u256 =
                0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff_u256;
            max_uint256
        }
    }

    // TODO: Double check math below.
    pub fn ceil_div(a: u256, b: u256) -> u256 {
        assert(b != 0, 'Division by zero');

        // If a is zero, the result is zero
        if a == 0 {
            return 0;
        }

        // Calculate ceiling division: (a - 1) / b + 1
        // This works because integer division truncates toward zero
        // Note: We must ensure this calculation doesn't overflow
        // Cairo's u256 handles overflow checking automatically
        let intermediate = (a - 1_u256) / b;
        return intermediate + 1_u256;
    }
}
