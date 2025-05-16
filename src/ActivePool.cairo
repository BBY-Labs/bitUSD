use starknet::ContractAddress;
use crate::TroveManager::TroveChange;

#[starknet::interface]
pub trait IActivePool<TContractState> {
    // View
    fn get_coll_balance(self: @TContractState) -> u256;
    fn calc_pending_agg_interest(self: @TContractState) -> u256;
    fn calc_pending_SP_yield(self: @TContractState) -> u256;
    fn calc_pending_agg_batch_management_fees(self: @TContractState) -> u256;
    fn get_new_approx_avg_interest_rate_from_trove_change(
        self: @TContractState, trove_change: TroveChange,
    ) -> u256;
    fn get_bit_usd_debt(self: @TContractState) -> u256;
    // Pool functionality
    fn send_coll(ref self: TContractState, account: ContractAddress, amount: u256);
    fn send_coll_to_default_pool(ref self: TContractState, amount: u256);
    fn receive_coll(ref self: TContractState, amount: u256);
    fn account_for_received_coll(ref self: TContractState, amount: u256);
    // Aggregate interest operations
    fn mint_agg_interest_and_account_for_trove_change(
        ref self: TContractState, trove_change: TroveChange, batch_address: ContractAddress,
    );
    fn mint_agg_interest(ref self: TContractState);
    // Batch management
    fn mint_batch_management_fee_and_account_for_change(
        ref self: TContractState, trove_change: TroveChange, batch_address: ContractAddress,
    );
    // Shutdown
    fn set_shutdown_flag(ref self: TContractState);
    fn has_been_shutdown(self: @TContractState) -> bool;
}


#[starknet::contract]
pub mod ActivePool {
    use core::cmp::min;
    use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use starknet::{ContractAddress, get_block_timestamp, get_caller_address, get_contract_address};
    use crate::AddressesRegistry::{IAddressesRegistryDispatcher, IAddressesRegistryDispatcherTrait};
    use crate::BitUSD::{IBitUSDDispatcher, IBitUSDDispatcherTrait};
    use crate::DefaultPool::{IDefaultPoolDispatcher, IDefaultPoolDispatcherTrait};
    use crate::StabilityPool::{IStabilityPoolDispatcher, IStabilityPoolDispatcherTrait};
    use crate::dependencies::Constants::Constants::{DECIMAL_PRECISION, ONE_YEAR, SP_YIELD_SPLIT};
    use crate::dependencies::ConversionLib::conversion_lib;
    use crate::dependencies::MathLib::math_lib;
    use super::{IActivePool, TroveChange};
    //////////////////////////////////////////////////////////////
    //                         CONSTANTS                        //
    //////////////////////////////////////////////////////////////

    const NAME: felt252 = 'ActivePool';

    //////////////////////////////////////////////////////////////
    //                          STORAGE                         //
    //////////////////////////////////////////////////////////////

    #[storage]
    struct Storage {
        coll_token: ContractAddress,
        borrower_operations: ContractAddress,
        trove_manager: ContractAddress,
        default_pool: ContractAddress,
        bit_usd: ContractAddress,
        interest_router: ContractAddress,
        stability_pool: ContractAddress,
        coll_balance: u256,
        // Aggregate recorded debt tracker. Updated whenever a Trove's debt is touched AND whenever
        // the aggregate pending interest is minted.
        // "D" in the spec.
        agg_recorded_debt: u256,
        // Sum of individual recorded Trove debts weighted by their respective chosen interest
        // rates.
        // Updated at individual Trove operations.
        // "S" in the spec.
        agg_weighted_debt_sum: u256,
        // Last time at which the aggregate recorded debt and weighted sum were updated
        last_agg_update_time: u64,
        // Timestamp at which branch was shut down. 0 if not shut down.
        shutdown_time: u64,
        // Aggregate batch fees tracker
        agg_batch_management_fees: u256,
        // Sum of individual recorded Trove debts weighted by their respective batch management fees
        // Updated at individual batched Trove operations.
        agg_weighted_batch_management_fee_sum: u256,
        // Last time at which the aggregate batch fees and weighted sum were updated.
        last_agg_batch_management_fees_update_time: u64,
    }

    //////////////////////////////////////////////////////////////
    //                          EVENTS                          //
    //////////////////////////////////////////////////////////////

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        CollTokenAddressChanged: CollTokenAddressChanged,
        BorrowerOperationsAddressChanged: BorrowerOperationsAddressChanged,
        TroveManagerAddressChanged: TroveManagerAddressChanged,
        DefaultPoolAddressChanged: DefaultPoolAddressChanged,
        StabilityPoolAddressChanged: StabilityPoolAddressChanged,
        ActivePoolBoldDebtUpdated: ActivePoolBoldDebtUpdated,
        ActivePoolCollBalanceUpdated: ActivePoolCollBalanceUpdated,
    }

    #[derive(Drop, starknet::Event)]
    pub struct CollTokenAddressChanged {
        pub new_coll_token_address: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    pub struct BorrowerOperationsAddressChanged {
        pub new_borrower_operations_address: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    pub struct TroveManagerAddressChanged {
        pub new_trove_manager_address: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    pub struct DefaultPoolAddressChanged {
        pub new_default_pool_address: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    pub struct StabilityPoolAddressChanged {
        pub new_stability_pool_address: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    pub struct ActivePoolBoldDebtUpdated {
        pub recorded_debt_sum: u256,
    }

    #[derive(Drop, starknet::Event)]
    pub struct ActivePoolCollBalanceUpdated {
        pub coll_balance: u256,
    }

    //////////////////////////////////////////////////////////////
    //                     CONSTRUCTOR                          //
    //////////////////////////////////////////////////////////////

    #[constructor]
    fn constructor(ref self: ContractState, addresses_registry_address: ContractAddress) {
        let addresses_registry = IAddressesRegistryDispatcher {
            contract_address: addresses_registry_address,
        };

        self.coll_token.write(addresses_registry.get_coll_token());
        self.borrower_operations.write(addresses_registry.get_borrower_operations());
        self.trove_manager.write(addresses_registry.get_trove_manager());
        self.stability_pool.write(addresses_registry.get_stability_pool());
        self.default_pool.write(addresses_registry.get_default_pool());
        self.interest_router.write(addresses_registry.get_interest_router());
        self.bit_usd.write(addresses_registry.get_bitusd_token());

        self
            .emit(
                event: CollTokenAddressChanged { new_coll_token_address: self.coll_token.read() },
            );
        self
            .emit(
                event: BorrowerOperationsAddressChanged {
                    new_borrower_operations_address: self.borrower_operations.read(),
                },
            );
        self
            .emit(
                event: TroveManagerAddressChanged {
                    new_trove_manager_address: self.trove_manager.read(),
                },
            );
        self
            .emit(
                event: DefaultPoolAddressChanged {
                    new_default_pool_address: self.default_pool.read(),
                },
            );
        self
            .emit(
                event: StabilityPoolAddressChanged {
                    new_stability_pool_address: self.stability_pool.read(),
                },
            );
    }

    //////////////////////////////////////////////////////////////
    //                   EXTERNAL FUNCTIONS                     //
    //////////////////////////////////////////////////////////////

    #[abi(embed_v0)]
    impl IActivePoolImpl of IActivePool<ContractState> {
        fn mint_agg_interest(ref self: ContractState) {
            _require_caller_is_BO_or_SP(@self);
            let agg_interest = _mint_agg_interest(ref self, 0);
            let agg_recorded_debt = self.agg_recorded_debt.read();
            self.agg_recorded_debt.write(agg_recorded_debt + agg_interest);
        }

        // This function is called inside all state-changing user ops: borrower ops, liquidations,
        // redemptions and SP deposits/withdrawals.
        // Some user ops trigger debt changes to Trove(s), in which case _troveDebtChange will be
        // non-zero.
        // The aggregate recorded debt is incremented by the aggregate pending interest, plus the
        // net Trove debt change.
        // The net Trove debt change consists of the sum of a) any debt issued/repaid and b) any
        // redistribution debt gain applied in the encapsulating operation.
        // It does *not* include the Trove's individual accrued interest - this gets accounted for
        // in the aggregate accrued interest.
        // The net Trove debt change could be positive or negative in a repayment (depending on
        // whether its redistribution gain or repayment amount is larger), so this function accepts
        // both the increase and the decrease to avoid using (and converting to/from) signed ints.
        fn mint_agg_interest_and_account_for_trove_change(
            ref self: ContractState, trove_change: TroveChange, batch_address: ContractAddress,
        ) {
            _require_caller_is_BO_or_TM(@self);

            let zero_address: ContractAddress = 0.try_into().unwrap();
            // Batch management fees.
            if (batch_address != zero_address) {
                _mint_batch_management_fee_and_account_for_change(
                    ref self, @trove_change, batch_address,
                );
            }

            let last_agg_recorded_debt = self.agg_recorded_debt.read();
            let mut new_agg_recorded_debt = last_agg_recorded_debt
                + _mint_agg_interest(
                    ref self, trove_change.upfront_fee,
                ); // adds minted agg. interest + upfront fee
            new_agg_recorded_debt += trove_change.applied_redist_bit_usd_debt_gain;
            new_agg_recorded_debt += trove_change.debt_increase;
            new_agg_recorded_debt += trove_change.debt_decrease;
            self.agg_recorded_debt.write(new_agg_recorded_debt);

            // assert(aggRecordedDebt >= 0) // This should never be negative. If all redistribution
            // gians and all aggregate interest was applied and all Trove debts were repaid, it
            // should become 0.
            let last_agg_weighted_debt_sum = self.agg_weighted_debt_sum.read();
            let mut new_agg_weighted_debt_sum = last_agg_weighted_debt_sum
                + trove_change.new_weighted_recorded_debt;
            new_agg_weighted_debt_sum -= trove_change.old_weighted_recorded_debt;
            self.agg_weighted_debt_sum.write(new_agg_weighted_debt_sum);
        }

        fn mint_batch_management_fee_and_account_for_change(
            ref self: ContractState, trove_change: TroveChange, batch_address: ContractAddress,
        ) {
            _require_caller_is_TM(@self);
            let trove_change_ref = @trove_change;
            _mint_batch_management_fee_and_account_for_change(
                ref self, trove_change_ref, batch_address,
            );
        }

        fn set_shutdown_flag(ref self: ContractState) {
            _require_caller_is_TM(@self);
            self.shutdown_time.write(get_block_timestamp());
        }

        fn send_coll(ref self: ContractState, account: ContractAddress, amount: u256) {
            _require_caller_is_BO_or_TM_or_SP(@self);
            _account_for_send_coll(ref self, amount);

            let coll_token_address = self.coll_token.read();
            let coll_token = IERC20Dispatcher { contract_address: coll_token_address };
            coll_token.transfer(account, amount);
        }

        fn send_coll_to_default_pool(ref self: ContractState, amount: u256) {
            _require_caller_is_TM(@self);
            _account_for_send_coll(ref self, amount);

            let default_pool_address = self.default_pool.read();
            let default_pool = IDefaultPoolDispatcher { contract_address: default_pool_address };
            default_pool.receive_coll(amount);
        }

        // Pull Coll tokens from sender
        fn receive_coll(ref self: ContractState, amount: u256) {
            _require_caller_is_BO_or_DP(@self);
            _account_for_received_coll(ref self, amount);

            let coll_token_address = self.coll_token.read();
            let coll_token = IERC20Dispatcher { contract_address: coll_token_address };
            coll_token.transfer_from(get_caller_address(), get_contract_address(), amount);
        }

        fn account_for_received_coll(ref self: ContractState, amount: u256) {
            _require_caller_is_BO_or_DP(@self);
            _account_for_received_coll(ref self, amount);
        }

        ////////////////////////////////////////////////////////////////
        //                     VIEW FUNCTIONS                         //
        ////////////////////////////////////////////////////////////////
        fn has_been_shutdown(self: @ContractState) -> bool {
            let is_shutdown = self.shutdown_time.read() != 0;
            is_shutdown
        }

        fn get_coll_balance(self: @ContractState) -> u256 {
            self.coll_balance.read()
        }

        fn calc_pending_agg_interest(self: @ContractState) -> u256 {
            _calc_pending_agg_interest(self)
        }

        fn calc_pending_SP_yield(self: @ContractState) -> u256 {
            let calc_pending_agg_interest = _calc_pending_agg_interest(self);
            let pending_sp_yield = (calc_pending_agg_interest * SP_YIELD_SPLIT) / DECIMAL_PRECISION;
            pending_sp_yield
        }

        fn calc_pending_agg_batch_management_fees(self: @ContractState) -> u256 {
            _calc_pending_agg_batch_management_fee(self)
        }

        fn get_new_approx_avg_interest_rate_from_trove_change(
            self: @ContractState, trove_change: TroveChange,
        ) -> u256 {
            // We are ignoring the upfront fee when calculating the approx. avg. interest rate.
            assert(trove_change.upfront_fee == 0, 'AP: upfront fee not 0');

            if (self.shutdown_time.read() != 0) {
                0
            } else {
                let last_agg_recorded_debt = self.agg_recorded_debt.read();
                let mut new_agg_recorded_debt = last_agg_recorded_debt
                    + _calc_pending_agg_interest(self);
                new_agg_recorded_debt += trove_change.applied_redist_bit_usd_debt_gain;
                new_agg_recorded_debt += trove_change.debt_increase;
                new_agg_recorded_debt += trove_change.batch_accrued_management_fee;
                new_agg_recorded_debt -= trove_change.debt_decrease;

                let last_agg_weighted_debt_sum = self.agg_weighted_debt_sum.read();
                let mut new_agg_weighted_debt_sum = last_agg_weighted_debt_sum
                    + trove_change.new_weighted_recorded_debt;
                new_agg_weighted_debt_sum -= trove_change.old_weighted_recorded_debt;

                // Avoid division by 0
                if new_agg_recorded_debt > 0 {
                    new_agg_weighted_debt_sum / new_agg_recorded_debt
                } else {
                    0
                }
            }
        }

        // Returns sum of agg.recorded debt plus agg. pending interest. Excludes pending redist.
        // gains.
        fn get_bit_usd_debt(self: @ContractState) -> u256 {
            let agg_recorded_debt = self.agg_recorded_debt.read();
            let pending_agg_interest = _calc_pending_agg_interest(self);
            let agg_batch_management_fees = self.agg_recorded_debt.read();
            let pending_agg_batch_management_fee = _calc_pending_agg_batch_management_fee(self);

            agg_recorded_debt
                + pending_agg_interest
                + agg_batch_management_fees
                + pending_agg_batch_management_fee
        }
    }

    ////////////////////////////////////////////////////////////////
    //                     INTERNAL FUNCTIONS                     //
    ////////////////////////////////////////////////////////////////

    fn _account_for_send_coll(ref self: ContractState, amount: u256) {
        let new_coll_balance = self.coll_balance.read() - amount;
        self.coll_balance.write(new_coll_balance);
        self.emit(event: ActivePoolCollBalanceUpdated { coll_balance: new_coll_balance });
    }

    fn _account_for_received_coll(ref self: ContractState, amount: u256) {
        let new_coll_balance = self.coll_balance.read() + amount;
        self.coll_balance.write(new_coll_balance);
        self.emit(event: ActivePoolCollBalanceUpdated { coll_balance: new_coll_balance });
    }

    fn _mint_agg_interest(ref self: ContractState, upfront_fee: u256) -> u256 {
        let pending_agg_interest = _calc_pending_agg_interest(@self);
        let minted_amount = pending_agg_interest + upfront_fee;

        // Mint part of the bitUSD interest to the SP and part to the router for LPs.
        if (minted_amount > 0) {
            let sp_yield = SP_YIELD_SPLIT * minted_amount / DECIMAL_PRECISION;
            let remainder_to_lps = minted_amount - sp_yield;

            let bit_usd_address = self.bit_usd.read();
            let bit_usd = IBitUSDDispatcher { contract_address: bit_usd_address };
            bit_usd.mint(self.interest_router.read(), remainder_to_lps);

            if (sp_yield > 0) {
                // Distribute yield to stability pool.
                let stability_pool_address = self.stability_pool.read();
                bit_usd.mint(stability_pool_address, sp_yield);

                let stability_pool = IStabilityPoolDispatcher {
                    contract_address: stability_pool_address,
                };
                stability_pool.trigger_bitusd_rewards(sp_yield);
            }
        }

        self.last_agg_update_time.write(get_block_timestamp());
        minted_amount
    }

    fn _calc_pending_agg_interest(self: @ContractState) -> u256 {
        if self.shutdown_time.read() != 0 {
            return 0;
        } else {
            // We use the ceiling of the division here to ensure positive error, while we use
            // regular floor division when calculating the interest accrued by individual Troves.
            // This ensures that `system debt >= sum(trove debt)` always holds, and thus system debt
            // won't turn negative even if all Trove debt is repaid. The difference should be small
            // and it should scale with the number of interest minting events.
            let agg_weighted_debt_sum = self.agg_weighted_debt_sum.read();
            let last_agg_update_time = conversion_lib::u256_from_u64(
                self.last_agg_update_time.read(),
            );

            let timestamp = conversion_lib::u256_from_u64(get_block_timestamp());

            let acc_weighted_debt = agg_weighted_debt_sum * (timestamp - last_agg_update_time);
            let one_year_u256 = conversion_lib::u256_from_u64(ONE_YEAR);
            return math_lib::ceil_div(acc_weighted_debt, one_year_u256 * DECIMAL_PRECISION);
        }
    }

    fn _mint_batch_management_fee_and_account_for_change(
        ref self: ContractState, trove_change: @TroveChange, batch_address: ContractAddress,
    ) {
        let last_agg_recorded_debt = self.agg_recorded_debt.read();
        let accrued_management_fee = *trove_change.batch_accrued_management_fee;
        self.agg_recorded_debt.write(last_agg_recorded_debt + accrued_management_fee);

        // Calculate new batch management fees
        let last_agg_batch_management_fees = self.agg_batch_management_fees.read();
        let mut new_agg_batch_management_fees = last_agg_batch_management_fees
            + _calc_pending_agg_batch_management_fee(@self);
        new_agg_batch_management_fees = new_agg_batch_management_fees - accrued_management_fee;
        self.agg_batch_management_fees.write(new_agg_batch_management_fees);

        let last_agg_weighted_batch_management_fee_sum = self
            .agg_weighted_batch_management_fee_sum
            .read();
        let mut new_agg_weighted_batch_management_fee_sum =
            last_agg_weighted_batch_management_fee_sum
            + *trove_change.new_weighted_recorded_batch_management_fee;
        new_agg_weighted_batch_management_fee_sum = new_agg_weighted_batch_management_fee_sum
            - *trove_change.old_weighted_recorded_batch_management_fee;
        self.agg_weighted_batch_management_fee_sum.write(new_agg_weighted_batch_management_fee_sum);

        // Mint fee to batch address
        if (accrued_management_fee > 0) {
            let bit_usd_address = self.bit_usd.read();
            let bit_usd = IBitUSDDispatcher { contract_address: bit_usd_address };
            bit_usd.mint(batch_address, accrued_management_fee);
        }

        self.last_agg_batch_management_fees_update_time.write(get_block_timestamp());
    }

    fn _calc_pending_agg_batch_management_fee(self: @ContractState) -> u256 {
        let period_end = if self.shutdown_time.read() != 0 {
            conversion_lib::u256_from_u64(self.shutdown_time.read())
        } else {
            conversion_lib::u256_from_u64(get_block_timestamp())
        };

        let agg_weighted_batch_management_fee_sum = self
            .agg_weighted_batch_management_fee_sum
            .read();
        let period_start = min(agg_weighted_batch_management_fee_sum, period_end);
        let agg_weighted_batch_management_fee_on_period = self
            .agg_weighted_batch_management_fee_sum
            .read()
            * (period_end - period_start);
        let one_year_u256 = conversion_lib::u256_from_u64(ONE_YEAR);
        math_lib::ceil_div(
            agg_weighted_batch_management_fee_on_period, one_year_u256 * DECIMAL_PRECISION,
        )
    }

    ////////////////////////////////////////////////////////////////
    //                     ACCESS FUNCTIONS                       //
    ////////////////////////////////////////////////////////////////

    fn _require_caller_is_BO_or_SP(self: @ContractState) {
        let caller = get_caller_address();
        let is_BO = caller == self.borrower_operations.read();
        let is_SP = caller == self.stability_pool.read();
        assert(is_BO || is_SP, 'AP: Caller is not BO or SP');
    }

    fn _require_caller_is_TM(self: @ContractState) {
        let caller = get_caller_address();
        assert(caller == self.trove_manager.read(), 'AP: Caller is not TM');
    }

    fn _require_caller_is_BO_or_TM(self: @ContractState) {
        let caller = get_caller_address();
        let is_BO = caller == self.borrower_operations.read();
        let is_TM = caller == self.trove_manager.read();
        assert(is_BO || is_TM, 'AP: Caller is not BO or TM');
    }

    fn _require_caller_is_BO_or_TM_or_SP(self: @ContractState) {
        let caller = get_caller_address();
        let is_BO = caller == self.borrower_operations.read();
        let is_TM = caller == self.trove_manager.read();
        let is_SP = caller == self.stability_pool.read();
        assert(is_BO || is_TM || is_SP, 'AP: Caller is not BO, TM or SP');
    }

    fn _require_caller_is_BO_or_DP(self: @ContractState) {
        let caller = get_caller_address();
        let is_BO = caller == self.borrower_operations.read();
        let is_DP = caller == self.default_pool.read();
        assert(is_BO || is_DP, 'AP: Caller is not BO or DP');
    }
}
