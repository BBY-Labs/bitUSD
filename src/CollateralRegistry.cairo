use starknet::ContractAddress;

#[starknet::interface]
pub trait ICollateralRegistry<TContractState> {
    fn base_rate(self: @TContractState) -> u256;
    fn last_fee_operation_time(self: @TContractState) -> u64;
    fn redeem_collateral(
        ref self: TContractState,
        bit_usd_amount: u256,
        max_iterations: u256,
        max_fee_percentage: u256,
    );
    fn get_collateral(self: @TContractState, index: u8) -> ContractAddress;
    fn get_trove_manager(self: @TContractState, index: u8) -> ContractAddress;
    fn get_redemption_rate(self: @TContractState) -> u256;
    fn get_redemption_rate_with_decay(self: @TContractState) -> u256;
    fn get_redemption_rate_for_redeemed_amount(
        self: @TContractState, redeemed_amount: u256,
    ) -> u256;
    fn get_redemption_fee_with_decay(self: @TContractState, eth_drawn: u256) -> u256;
    fn get_effective_redemption_fee_in_bold(self: @TContractState, redeemed_amount: u256) -> u256;
}


#[starknet::contract]
pub mod CollateralRegistry {
    use core::cmp::min;
    use core::traits::Into;
    use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use starknet::{ContractAddress, get_block_timestamp, get_caller_address};
    use crate::BitUSD::{IBitUSDDispatcher, IBitUSDDispatcherTrait};
    use crate::TroveManager::{ITroveManagerDispatcher, ITroveManagerDispatcherTrait};
    use crate::dependencies::Constants::Constants::{
        DECIMAL_PRECISION, INITIAL_BASE_RATE, ONE_MINUTE, REDEMPTION_FEE_FLOOR,
        REDEMPTION_MINUTE_DECAY_FACTOR,
    };
    use crate::dependencies::MathLib::math_lib;
    use super::ICollateralRegistry;

    //////////////////////////////////////////////////////////////
    //                          STORAGE                         //
    //////////////////////////////////////////////////////////////

    #[storage]
    struct Storage {
        number_of_collaterals: u8,
        collateral_0: ContractAddress,
        collateral_1: ContractAddress,
        collateral_2: ContractAddress,
        trove_manager_0: ContractAddress,
        trove_manager_1: ContractAddress,
        trove_manager_2: ContractAddress,
        bit_usd: ContractAddress,
        base_rate: u256,
        last_fee_operation_time: u64,
    }

    //////////////////////////////////////////////////////////////
    //                          STRUCTS                         //
    //////////////////////////////////////////////////////////////

    #[derive(Drop, Serde)]
    struct RedemptionTotals {
        num_collaterals: u8,
        bit_usd_supply_at_start: u256,
        unbacked: u256,
        redeemed_amount: u256,
    }

    //////////////////////////////////////////////////////////////
    //                          EVENTS                          //
    //////////////////////////////////////////////////////////////

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        BaseRateUpdated: BaseRateUpdated,
        LastFeeOpTimeUpdated: LastFeeOpTimeUpdated,
    }

    #[derive(Drop, starknet::Event)]
    pub struct BaseRateUpdated {
        pub base_rate: u256,
    }

    #[derive(Drop, starknet::Event)]
    pub struct LastFeeOpTimeUpdated {
        pub last_fee_op_time: u64,
    }

    ////////////////////////////////////////////////////////////////
    //                        CONSTRUCTOR                         //
    ////////////////////////////////////////////////////////////////

    #[constructor]
    fn constructor(
        ref self: ContractState,
        bit_usd: ContractAddress,
        collateral_tokens: Span<ContractAddress>,
        trove_managers: Span<ContractAddress>,
    ) {
        let num_tokens = collateral_tokens.len();

        assert(num_tokens > 0, 'CR: Collateral list empty');
        assert(num_tokens <= 3, 'CR: Collateral list too long');

        // Add first collateral token and trove manager to storage.
        self.collateral_0.write(*collateral_tokens.at(0));
        self.trove_manager_0.write(*trove_managers.at(0));
        // Add other collaterals with associated trove_manager if they exist.
        if num_tokens > 1 {
            self.collateral_1.write(*collateral_tokens.at(1));
            self.trove_manager_1.write(*trove_managers.at(1));
        }
        if num_tokens > 2 {
            self.collateral_2.write(*collateral_tokens.at(2));
            self.trove_manager_2.write(*trove_managers.at(2));
        }

        self.bit_usd.write(bit_usd);
        self.last_fee_operation_time.write(get_block_timestamp());
        self.base_rate.write(INITIAL_BASE_RATE);

        self.emit(event: BaseRateUpdated { base_rate: INITIAL_BASE_RATE });
    }

    ////////////////////////////////////////////////////////////////
    //                     EXTERNAL FUNCTIONS                     //
    ////////////////////////////////////////////////////////////////

    #[abi(embed_v0)]
    impl CollateralRegistryImpl of ICollateralRegistry<ContractState> {
        fn base_rate(self: @ContractState) -> u256 {
            self.base_rate.read()
        }

        fn last_fee_operation_time(self: @ContractState) -> u64 {
            self.last_fee_operation_time.read()
        }

        fn get_collateral(self: @ContractState, index: u8) -> ContractAddress {
            match index {
                0 => self.collateral_0.read(),
                1 => self.collateral_1.read(),
                2 => self.collateral_2.read(),
                _ => panic!("CR: Invalid collateral index"),
            }
        }

        fn get_trove_manager(self: @ContractState, index: u8) -> ContractAddress {
            match index {
                0 => self.trove_manager_0.read(),
                1 => self.trove_manager_1.read(),
                2 => self.trove_manager_2.read(),
                _ => panic!("CR: Invalid Trove Manager index"),
            }
        }

        fn redeem_collateral(
            ref self: ContractState,
            bit_usd_amount: u256,
            max_iterations: u256,
            max_fee_percentage: u256,
        ) {
            _require_valid_max_fee_percentage(max_fee_percentage);
            _require_amount_greater_than_zero(bit_usd_amount);

            let mut totals = RedemptionTotals {
                num_collaterals: 0, bit_usd_supply_at_start: 0, unbacked: 0, redeemed_amount: 0,
            };

            totals.num_collaterals = self.number_of_collaterals.read();

            let mut unbacked_portions: Array<u256> = ArrayTrait::new();
            let mut prices: Array<u256> = ArrayTrait::new();

            let bit_usd_address = self.bit_usd.read();
            let bit_usd = IERC20Dispatcher { contract_address: bit_usd_address };
            let bit_usd_supply_at_start = bit_usd.total_supply();

            // Decay the baseRate due to time passed, and then increase it according to the size of
            // this redemption.
            // Use the saved total bitUSD supply value, from before it was reduced by the
            // redemption.
            // We only compute it here, and update it at the end,
            // because the final redeemed amount may be less than the requested amount
            // Redeemers should take this into account in order to request the optimal amount to not
            // overpay
            let updated_base_rate = _get_updated_base_rate_from_redemption(
                @self, bit_usd_amount, bit_usd_supply_at_start,
            );
            let redemption_rate = _calculate_redemption_rate(updated_base_rate);
            assert(redemption_rate <= max_fee_percentage, 'CR: Max fee exceeded');
            // Implicit by the above and the _requireValidMaxFeePercentage checks
            //require(newBaseRate < DECIMAL_PRECISION, "CR: Fee would eat up all collateral");

            // Gather and accumulate unbacked portions
            let mut i = 0;
            while i < totals.num_collaterals {
                let trove_address = self.get_trove_manager(i);
                let trove_manager = ITroveManagerDispatcher { contract_address: trove_address };
                let (unbacked_portion, price, redeemable) = trove_manager
                    .get_unbacked_portion_price_and_redeemability();

                prices.append(price);

                if redeemable {
                    totals.unbacked = totals.unbacked + unbacked_portion;
                    unbacked_portions.append(unbacked_portion);
                } else {
                    unbacked_portions.append(0);
                }

                i += 1;
            }

            // There’s an unlikely scenario where all the normally redeemable branches (i.e.
            // having Total Collateral Ratio > Soft Collateral Ratio)
            // have 0 unbacked. In that case, we redeem proportinally to branch size
            if totals.unbacked == 0 {
                let mut i = 0;
                while i < totals.num_collaterals {
                    let trove_address = self.get_trove_manager(i);
                    let trove_manager = ITroveManagerDispatcher { contract_address: trove_address };

                    // Destructure the tuple returned by the call
                    let (_, _, redeemable) = trove_manager
                        .get_unbacked_portion_price_and_redeemability();

                    if redeemable {
                        let unbacked_portion = trove_manager.get_entire_branch_debt();
                        totals.unbacked = totals.unbacked + unbacked_portion;
                        unbacked_portions.append(unbacked_portion);
                    } else {
                        unbacked_portions.append(0_u256);
                    }

                    i += 1;
                }
            }

            // Compute redemption amount for each collateral and redeem against the corresponding
            // TroveManager
            // TODO: Double check use of span here.
            i = 0;
            let unbacked_portions_span = unbacked_portions.span();
            while i < totals.num_collaterals {
                let i_usize = i.try_into().unwrap(); // Convert u256 -> usize safely
                let unbacked_portion = *unbacked_portions_span.at(i_usize);

                if unbacked_portion > 0 {
                    let redeem_amount = bit_usd_amount * unbacked_portion / totals.unbacked;

                    if redeem_amount > 0 {
                        let trove_address = self
                            .get_trove_manager(i); // Implemented with match or map
                        let trove_manager = ITroveManagerDispatcher {
                            contract_address: trove_address,
                        };

                        let prices_span = prices.span();
                        let price = *prices_span.at(i_usize);

                        let redeemed_amount = trove_manager
                            .redeem_collateral(
                                get_caller_address(),
                                redeem_amount,
                                price,
                                redemption_rate,
                                max_iterations,
                            );
                        totals.redeemed_amount = totals.redeemed_amount + redeemed_amount;
                    }
                }
            }

            _update_base_rate_and_get_redemption_rate(
                ref self, totals.redeemed_amount, totals.bit_usd_supply_at_start,
            );

            // Burn the total bitUSD that is cancelled with debt.
            if totals.redeemed_amount > 0 {
                let bit_usd_address = self.bit_usd.read();
                let bit_usd = IBitUSDDispatcher { contract_address: bit_usd_address };
                bit_usd.burn(get_caller_address(), totals.redeemed_amount);
            }
        }

        ////////////////////////////////////////////////////////////////
        //                 REDEMPTION RATE VIEW FUNCTIONS             //
        ////////////////////////////////////////////////////////////////

        fn get_redemption_rate(self: @ContractState) -> u256 {
            let base_rate = self.base_rate.read();
            let redemption_rate = _calculate_redemption_rate(base_rate);
            redemption_rate
        }

        fn get_redemption_rate_with_decay(self: @ContractState) -> u256 {
            _calculate_redemption_rate(_calculate_decayed_base_rate(self))
        }

        fn get_redemption_rate_for_redeemed_amount(
            self: @ContractState, redeemed_amount: u256,
        ) -> u256 {
            let bit_usd = IERC20Dispatcher { contract_address: self.bit_usd.read() };
            let total_bit_usd_supply = bit_usd.total_supply();

            let new_base_rate = _get_updated_base_rate_from_redemption(
                self, redeemed_amount, total_bit_usd_supply,
            );

            let redemption_rate = _calculate_redemption_rate(new_base_rate);
            redemption_rate
        }

        fn get_redemption_fee_with_decay(self: @ContractState, eth_drawn: u256) -> u256 {
            _get_redemption_rate_with_decay(self)
        }

        fn get_effective_redemption_fee_in_bold(
            self: @ContractState, redeemed_amount: u256,
        ) -> u256 {
            let bit_usd = IERC20Dispatcher { contract_address: self.bit_usd.read() };
            let total_bit_usd_supply = bit_usd.total_supply();

            let new_base_rate = _get_updated_base_rate_from_redemption(
                self, redeemed_amount, total_bit_usd_supply,
            );
            _calculate_redemption_fee(_calculate_redemption_rate(new_base_rate), redeemed_amount)
        }
    }

    ////////////////////////////////////////////////////////////////
    //                     INTERNAL FUNCTIONS                     //
    ////////////////////////////////////////////////////////////////

    fn _require_valid_max_fee_percentage(max_fee_percentage: u256) {
        assert(
            max_fee_percentage >= REDEMPTION_FEE_FLOOR && max_fee_percentage <= DECIMAL_PRECISION,
            'CR: Max fee not in range',
        );
    }

    fn _require_amount_greater_than_zero(amount: u256) {
        assert(amount > 0, 'CR: amount <= 0')
    }

    // This function calculates the new baseRate in the following way:
    // 1) decays the baseRate based on time passed since last redemption or bitUSD borrowing
    // operation.
    // then,
    // 2) increases the baseRate based on the amount redeemed, as a proportion of total supply
    fn _get_updated_base_rate_from_redemption(
        self: @ContractState, redeem_amount: u256, total_bit_usd_supply: u256,
    ) -> u256 {
        // decay the base rate
        let decayed_base_rate = _calculate_decayed_base_rate(self);

        // get the fraction of total supply that was redeemed
        let redeemed_bit_usd_fraction = redeem_amount * DECIMAL_PRECISION / total_bit_usd_supply;

        let new_base_rate = decayed_base_rate + redeemed_bit_usd_fraction / total_bit_usd_supply;
        let new_base_rate_capped = min(new_base_rate, DECIMAL_PRECISION);
        new_base_rate_capped
    }

    fn _minutes_passed_since_last_fee_op(self: @ContractState) -> u64 {
        (get_block_timestamp() - self.last_fee_operation_time.read()) / ONE_MINUTE
    }

    fn _update_last_fee_op_time(ref self: ContractState) {
        let minutes_passed = _minutes_passed_since_last_fee_op(@self);
        if minutes_passed > 0 {
            let last_fee_op_time = self.last_fee_operation_time.read();
            let updated_last_fee_op_time = last_fee_op_time + (ONE_MINUTE * minutes_passed);
            self.last_fee_operation_time.write(updated_last_fee_op_time);
        }
    }

    fn _update_base_rate_and_get_redemption_rate(
        ref self: ContractState, bit_usd_amount: u256, total_bit_usd_supply_at_start: u256,
    ) {
        let new_base_rate = _get_updated_base_rate_from_redemption(
            @self, bit_usd_amount, total_bit_usd_supply_at_start,
        );

        //assert(newBaseRate <= DECIMAL_PRECISION); // This is already enforced in
        //`_getUpdatedBaseRateFromRedemption`
        self.base_rate.write(new_base_rate);
        self.emit(event: BaseRateUpdated { base_rate: new_base_rate });

        _update_last_fee_op_time(ref self);
    }

    fn _calculate_decayed_base_rate(self: @ContractState) -> u256 {
        let minutes_passed = _minutes_passed_since_last_fee_op(self);
        let minutes_passed_u256 = minutes_passed.into();
        let decay_factor = math_lib::dec_pow(REDEMPTION_MINUTE_DECAY_FACTOR, minutes_passed_u256);
        let decayed_base_rate = self.base_rate.read() * decay_factor / DECIMAL_PRECISION;
        decayed_base_rate
    }

    fn _calculate_redemption_rate(base_rate: u256) -> u256 {
        min(REDEMPTION_FEE_FLOOR + base_rate, DECIMAL_PRECISION)
    }

    fn _calculate_redemption_fee(redemption_rate: u256, amount: u256) -> u256 {
        redemption_rate * amount / DECIMAL_PRECISION
    }

    fn _get_redemption_rate_with_decay(self: @ContractState) -> u256 {
        _calculate_redemption_rate(_calculate_decayed_base_rate(self))
    }
}
