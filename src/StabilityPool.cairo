use starknet::ContractAddress;

#[starknet::interface]
pub trait IStabilityPool<TContractState> {
    // TODO missing getters?
    fn deposits(self: @TContractState, depositor: ContractAddress) -> u256;
    // --- Getters for public variables. Required by IPool interface ---
    fn get_coll_balance(self: @TContractState) -> u256;
    fn get_total_bitusd_deposits(self: @TContractState) -> u256;
    fn get_yield_gains_owed(self: @TContractState) -> u256;
    fn get_yield_gains_pending(self: @TContractState) -> u256;
    // --- External Depositor Functions ---

    //   provideToSP()
    // - Calculates depositor's Coll gain
    // - Calculates the compounded deposit
    // - Increases deposit, and takes new snapshots of accumulators P and S
    // - Sends depositor's accumulated Coll gains to depositor
    fn provide_to_sp(ref self: TContractState, top_up: u256, do_claim: bool);

    // withdrawFromSP():
    // - Calculates depositor's Coll gain
    // - Calculates the compounded deposit
    // - Sends the requested BOLD withdrawal to depositor
    // - (If _amount > userDeposit, the user withdraws all of their compounded deposit)
    // - Decreases deposit by withdrawn amount and takes new snapshots of accumulators P and S
    fn withdraw_from_sp(ref self: TContractState, amount: u256, do_claim: bool);
    // This function is only needed in the case a user has no deposit but still has remaining
    // stashed Coll gains.
    fn claim_all_coll_gains(ref self: TContractState);

    // - Triggers a BitUSD reward distribution
    fn trigger_bitusd_rewards(ref self: TContractState, bold_yield: u256);

    //  Cancels out the specified debt against the Bold contained in the Stability Pool (as far as
    //  possible) and transfers the Trove's Coll collateral from ActivePool to StabilityPool.
    //  Only called by liquidation functions in the TroveManager.
    fn offset(ref self: TContractState, debt_to_offset: u256, coll_to_add: u256);

    fn get_depositor_coll_gain(self: @TContractState, depositor: ContractAddress) -> u256;
    fn get_depositor_yield_gain(self: @TContractState, depositor: ContractAddress) -> u256;
    fn get_compounded_bitusd_deposit(self: @TContractState, depositor: ContractAddress) -> u256;

    fn get_depositor_yield_gain_with_pending(
        self: @TContractState, depositor: ContractAddress,
    ) -> u256;

    // TODO: Remove below fix
    fn set_addresses(ref self: TContractState, addresses_registry: ContractAddress);
}

//! The Stability Pool holds Bold tokens deposited by Stability Pool depositors.
//!
//! When a trove is liquidated, then depending on system conditions, some of its Bold debt gets
//! offset with Bold in the Stability Pool:  that is, the offset debt evaporates, and an equal
//! amount of Bold tokens in the Stability Pool is burned.
//!
//! Thus, a liquidation causes each depositor to receive a Bold loss, in proportion to their deposit
//! as a share of total deposits.
//! They also receive an Coll gain, as the collateral of the liquidated trove is distributed among
//! Stability depositors, in the same proportion.
//!
//! When a liquidation occurs, it depletes every deposit by the same fraction: for example, a
//! liquidation that depletes 40%
//! of the total Bold in the Stability Pool, depletes 40% of each deposit.
//!
//! A deposit that has experienced a series of liquidations is termed a "compounded deposit": each
//! liquidation depletes the deposit, multiplying it by some factor in range ]0,1[
//!
//!
//! --- IMPLEMENTATION ---
//!
//! We use a highly scalable method of tracking deposits and Coll gains that has O(1) complexity.
//!
//! When a liquidation occurs, rather than updating each depositor's deposit and Coll gain, we
//! simply update two state variables:
//! a product P, and a sum S.
//!
//! A mathematical manipulation allows us to factor out the initial deposit, and accurately track
//! all depositors' compounded deposits and accumulated Coll gains over time, as liquidations occur,
//! using just these two variables P and S. When depositors join the Stability Pool, they get a
//! snapshot of the latest P and S: P_t and S_t, respectively.
//!
//! The formula for a depositor's accumulated Coll gain is derived here:
//! https://github.com/liquity/dev/blob/main/papers/Scalable_Reward_Distribution_with_Compounding_Stakes.pdf
//!
//! For a given deposit d_t, the ratio P/P_t tells us the factor by which a deposit has decreased
//! since it joined the Stability Pool, and the term d_t * (S - S_t)/P_t gives us the deposit's
//! total accumulated Coll gain.
//!
//! Each liquidation updates the product P and sum S. After a series of liquidations, a compounded
//! deposit and corresponding Coll gain can be calculated using the initial deposit, the
//! depositor’s snapshots of P and S, and the latest values of P and S.
//!
//! Any time a depositor updates their deposit (withdrawal, top-up) their accumulated Coll gain is
//! paid out, their new deposit is recorded (based on their latest compounded deposit and modified
//! by the withdrawal/top-up), and they receive new snapshots of the latest P and S.
//! Essentially, they make a fresh deposit that overwrites the old one.
//!
//!
//! --- SCALE FACTOR ---
//!
//! Since P is a running product in range ]0,1] that is always-decreasing, it should never reach 0
//! when multiplied by a number in range ]0,1[.
//! Unfortunately, Solidity floor division always reaches 0, sooner or later.
//!
//! A series of liquidations that nearly empty the Pool (and thus each multiply P by a very small
//! number in range ]0,1[ ) may push P to its 36 digit decimal limit, and round it to 0, when in
//! fact the Pool hasn't been emptied: this would break deposit tracking.
//!
//! P is stored at 36-digit precision as a uint. That is, a value of "1" is represented by a value
//! of 1e36 in the code.
//!
//! So, to track P accurately, we use a scale factor: if a liquidation would cause P to decrease
//! below 1e27, we first multiply P by 1e9, and increment a currentScale factor by 1.
//!
//! The added benefit of using 1e9 for the scale factor that it ensures negligible precision loss
//! close to the scale boundary: when P is at its minimum value of 1e27, the relative precision loss
//! in P due to floor division is only on the order of 1e-27.
//!
//! --- MIN BOLD IN SP ---
//!
//! Once totalBoldDeposits has become >= MIN_BOLD_IN_SP, a liquidation may never fully empty the
//! Pool - a minimum of 1 BOLD remains in the SP at all times thereafter.
//! This is enforced for liquidations in TroveManager.batchLiquidateTroves, and for withdrawals in
//! StabilityPool.withdrawFromSP.
//! As such, it is impossible to empty the Stability Pool via liquidations, and P can never become
//! 0.
//!
//! --- TRACKING DEPOSIT OVER SCALE CHANGES ---
//!
//! When a deposit is made, it gets a snapshot of the currentScale.
//!
//! When calculating a compounded deposit, we compare the current scale to the deposit's scale
//! snapshot. If they're equal, the compounded deposit is given by d_t * P/P_t.
//! If it spans one scale change, it is given by d_t * P/(P_t * 1e9).
//!
//!  --- TRACKING DEPOSITOR'S COLL GAIN OVER SCALE CHANGES  ---
//!
//! We calculate the depositor's accumulated Coll gain for the scale at which they made the deposit,
//! using the Coll gain formula:
//! e_1 = d_t * (S - S_t) / P_t
//!
//! and also for the scale after, taking care to divide the latter by a factor of 1e9:
//! e_2 = d_t * S / (P_t * 1e9)
//!
//! The gain in the second scale will be full, as the starting point was in the previous scale, thus
//! no need to subtract anything.
//! The deposit therefore was present for reward events from the beginning of that second scale.
//!
//!        S_i-S_t + S_{i+1}
//!      .<--------.------------>
//!      .         .
//!      . S_i     .   S_{i+1}
//!   <--.-------->.<----------->
//!   S_t.         .
//!   <->.         .
//!      t         .
//!  |---+---------|-------------|-----...
//!         i            i+1
//!
//! The sum of (e_1 + e_2) captures the depositor's total accumulated Coll gain, handling the case
//! where their deposit spanned one scale change.
//!
//! --- UPDATING P WHEN A LIQUIDATION OCCURS ---
//!
//! Please see the implementation spec in the proof document, which closely follows on from the
//! compounded deposit / Coll gain derivations:
//! https://github.com/liquity/liquity/blob/master/papers/Scalable_Reward_Distribution_with_Compounding_Stakes.pdf
//!

// TODO: component LiquityBase, IStabilityPool, IStabilityPoolEvents

#[starknet::contract]
pub mod StabilityPool {
    use alexandria_math::const_pow::pow10;
    use alexandria_math::fast_power::fast_power;
    use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };
    use starknet::{ContractAddress, get_caller_address, get_contract_address};
    use crate::ActivePool::{IActivePoolDispatcher, IActivePoolDispatcherTrait};
    use crate::AddressesRegistry::{IAddressesRegistryDispatcher, IAddressesRegistryDispatcherTrait};
    use crate::BitUSD::{IBitUSDDispatcher, IBitUSDDispatcherTrait};
    use crate::dependencies::Constants::Constants::MIN_BITUSD_IN_SP;
    use crate::dependencies::LiquityBase::LiquityBaseComponent;
    use crate::i257::{I257Trait, i257};

    //////////////////////////////////////////////////////////////
    //                        COMPONENTS                        //
    //////////////////////////////////////////////////////////////

    component!(path: LiquityBaseComponent, storage: liquity_base, event: LiquityBaseEvent);

    //////////////////////////////////////////////////////////////
    //                        CONSTANTS                         //
    //////////////////////////////////////////////////////////////

    const P_PRECISION: u256 = 1000000000000000000000000000000000000; // 1e36

    // A scale change will happen if P decreases by a factor of at least this much
    const SCALE_FACTOR: u256 = 1000000000; // 1e9

    // Highest power `SCALE_FACTOR` can be raised to without overflow
    const MAX_SCALE_FACTOR_EXPONENT: u256 = 8;
    // TODO: NAME = "StabilityPool"

    // The number of scale changes after which an untouched deposit stops receiving yield / coll
    // gains
    const SCALE_SPAN: u256 = 2;

    //////////////////////////////////////////////////////////////
    //                          STORAGE                         //
    //////////////////////////////////////////////////////////////

    #[storage]
    struct Storage {
        coll_token: ContractAddress, // immutable TODO check IERC20
        trove_manager: ContractAddress, // immutable TODO check ITroveManager
        bitusd_token: ContractAddress, // immutable TODO check IBoldToken
        coll_balance: u256, // deposited coll tracker
        // Tracker for Bold held in the pool. Changes when users deposit/withdraw, and when Trove
        // debt is offset.
        total_bitusd_deposits: u256,
        // Total remaining Bold yield gains (from Trove interest mints) held by SP, and not yet
        // paid out to depositors From the contract's perspective, this is a write-only variable.
        yield_gains_owed: u256,
        // Total remaining Bold yield gains (from Trove interest mints) held by SP, not yet paid
        // out to depositors, and not accounted for because they were received when the total
        // deposits were too small
        yield_gains_pending: u256,
        deposits: Map<ContractAddress, Deposit>,
        deposit_snapshots: Map<ContractAddress, Snapshots>,
        stashed_coll: Map<ContractAddress, u256>,
        P: u256, // TODO: initialize to P_PRECISION
        // Each time the scale of P shifts by SCALE_FACTOR, the scale is incremented by 1
        current_scale: u256,
        // Coll Gain sum 'S': During its lifetime, each deposit d_t earns an Coll gain of ( d_t * [S
        // - S_t] )/P_t, where S_t is the depositor's snapshot of S taken at the time t when the
        // deposit was made.
        //
        // The 'S' sums are stored in a mapping (scale => sum).
        // - The mapping records the sum S at different scales.
        //
        scale_to_s: Map<u256, u256>,
        scale_to_b: Map<u256, u256>,
        #[substorage(v0)]
        liquity_base: LiquityBaseComponent::Storage,
    }

    //////////////////////////////////////////////////////////////
    //                          STRUCTS                         //
    //////////////////////////////////////////////////////////////

    #[derive(Copy, Drop, Serde, Default, starknet::Store)]
    struct Deposit {
        initial_value: u256,
    }

    #[derive(Copy, Drop, Default, Serde, starknet::Store)]
    struct Snapshots {
        S: u256, // Coll rewar sum liqs
        P: u256,
        B: u256, // Bold reward sum from minted interest
        scale: u256,
    }

    //////////////////////////////////////////////////////////////
    //                          EVENTS                          //
    //////////////////////////////////////////////////////////////
    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        StabilityPoolCollBalanceUpdated: StabilityPoolCollBalanceUpdated,
        StabilityPoolBitUSDBalanceUpdated: StabilityPoolBitUSDBalanceUpdated,
        P_Updated: P_Updated,
        S_Updated: S_Updated,
        B_Updated: B_Updated,
        ScaleUpdated: ScaleUpdated,
        DepositUpdated: DepositUpdated,
        DepositOperation: DepositOperation,
        TroveManagerAddressChanged: TroveManagerAddressChanged,
        BitUSDTokenAddressChanged: BitUSDTokenAddressChanged,
        #[flat]
        LiquityBaseEvent: LiquityBaseComponent::Event,
    }

    #[derive(Copy, Drop, Serde)]
    enum Operation {
        provide_to_sp,
        withdraw_from_sp,
        claim_all_coll_gains,
    }

    #[derive(Drop, starknet::Event)]
    struct StabilityPoolCollBalanceUpdated {
        new_balance: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct StabilityPoolBitUSDBalanceUpdated {
        new_balance: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct P_Updated {
        P: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct S_Updated {
        S: u256,
        scale: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct B_Updated {
        B: u256,
        scale: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct ScaleUpdated {
        current_scale: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct DepositUpdated {
        depositor: ContractAddress,
        new_deposit: u256,
        stashed_coll: u256,
        snapshot_p: u256,
        snapshot_s: u256,
        snapshot_b: u256,
        snapshot_scale: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct DepositOperation {
        depositor: ContractAddress,
        operation: Operation,
        deposit_loss_since_last_operation: u256,
        top_up_or_withdrawal: i257, // TODO: handle i256
        yield_gain_since_last_operation: u256,
        yield_gain_claimed: u256,
        eth_gain_since_last_operation: u256,
        eth_gain_claimed: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct TroveManagerAddressChanged {
        new_trove_manager_address: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct BitUSDTokenAddressChanged {
        new_bitusd_token_address: ContractAddress,
    }

    ////////////////////////////////////////////////////////////////
    //                 EXPOSE COMPONENT FUNCTIONS                 //
    ////////////////////////////////////////////////////////////////

    #[abi(embed_v0)]
    impl LiquityBaseImpl = LiquityBaseComponent::LiquityBaseImpl<ContractState>;

    impl LiquityBaseInternalImpl = LiquityBaseComponent::InternalImpl<ContractState>;

    ////////////////////////////////////////////////////////////////
    //                        CONSTRUCTOR                         //
    ////////////////////////////////////////////////////////////////

    #[constructor]
    fn constructor(ref self: ContractState, addresses_registry: ContractAddress) {
        let addresses_registry = IAddressesRegistryDispatcher {
            contract_address: addresses_registry,
        };
        self.liquity_base.initializer(addresses_registry.contract_address);

        self.P.write(P_PRECISION);
        self.coll_token.write(addresses_registry.get_coll_token());
        self.trove_manager.write(addresses_registry.get_trove_manager());
        self.bitusd_token.write(addresses_registry.get_bitusd_token());
    }

    ////////////////////////////////////////////////////////////////
    //                        GETTERS                             //
    ////////////////////////////////////////////////////////////////

    #[abi(embed_v0)]
    impl StabilityPoolImpl of super::IStabilityPool<ContractState> {
        fn deposits(self: @ContractState, depositor: ContractAddress) -> u256 {
            self.deposits.read(depositor).initial_value
        }

        // TODO: Remove below fix
        fn set_addresses(ref self: ContractState, addresses_registry: ContractAddress) {
            let addresses_registry_contract = IAddressesRegistryDispatcher {
                contract_address: addresses_registry,
            };

            self.coll_token.write(addresses_registry_contract.get_coll_token());
            self.trove_manager.write(addresses_registry_contract.get_trove_manager());
            self.bitusd_token.write(addresses_registry_contract.get_bitusd_token());
            self.liquity_base.active_pool.write(addresses_registry_contract.get_active_pool());
            self.liquity_base.default_pool.write(addresses_registry_contract.get_default_pool());
            self.liquity_base.price_feed.write(addresses_registry_contract.get_price_pool());
        }

        fn get_coll_balance(self: @ContractState) -> u256 {
            self.coll_balance.read()
        }

        fn get_total_bitusd_deposits(self: @ContractState) -> u256 {
            self.total_bitusd_deposits.read()
        }

        fn get_yield_gains_owed(self: @ContractState) -> u256 {
            self.yield_gains_owed.read()
        }

        fn get_yield_gains_pending(self: @ContractState) -> u256 {
            self.yield_gains_pending.read()
        }

        fn get_depositor_yield_gain_with_pending(
            self: @ContractState, depositor: ContractAddress,
        ) -> u256 {
            if (self.total_bitusd_deposits.read() < MIN_BITUSD_IN_SP) {
                return 0;
            }

            let initial_deposit = self.deposits.read(depositor).initial_value;
            if (initial_deposit == 0) {
                return 0;
            }

            let snapshots = self.deposit_snapshots.read(depositor);
            let mut new_yield_gains_owed = self.yield_gains_owed.read();

            // Yield gains from the same scale in which the deposit was made need no scaling
            let mut normalized_gains = self.scale_to_b.read(snapshots.scale) - snapshots.B;

            // Scale down further coll gains by a power of `SCALE_FACTOR` depending on how many
            // scale changes they span
            for i in 1..=SCALE_SPAN {
                normalized_gains += self.scale_to_b.read(snapshots.scale + i)
                    / fast_power(SCALE_FACTOR, i);
            }

            // Pending gains
            let active_pool = IActivePoolDispatcher {
                contract_address: self.liquity_base.active_pool.read(),
            };
            let pending_s_p_yield = active_pool.calc_pending_SP_yield();
            new_yield_gains_owed += pending_s_p_yield;

            let current_scale = self.current_scale.read();
            let total_bitusd_deposits = self.total_bitusd_deposits.read();
            let p = self.P.read();
            if (current_scale <= snapshots.scale + SCALE_SPAN) {
                normalized_gains += p
                    * pending_s_p_yield
                    / total_bitusd_deposits
                    / fast_power(SCALE_FACTOR, current_scale - snapshots.scale);
            }

            return core::cmp::min(
                initial_deposit * normalized_gains / snapshots.P, new_yield_gains_owed,
            );
        }

        fn get_compounded_bitusd_deposit(self: @ContractState, depositor: ContractAddress) -> u256 {
            let initial_deposit = self.deposits.read(depositor).initial_value;
            if (initial_deposit == 0) {
                return 0;
            }

            let snapshots = self.deposit_snapshots.read(depositor);

            let scale_diff = self.current_scale.read() - snapshots.scale;

            // Compute the compounded deposit. If one or more scale changes in `P` were made during
            // the deposit's lifetime, account for them.
            // If more than `MAX_SCALE_FACTOR_EXPONENT` scale changes were made, then the divisor is
            // greater than 2^256 so any deposit amount would be rounded down to zero.
            assert(snapshots.P != 0, 'SCOTT4');
            if (scale_diff <= MAX_SCALE_FACTOR_EXPONENT) {
                return initial_deposit
                    * self.P.read()
                    / snapshots.P
                    / fast_power(SCALE_FACTOR, scale_diff);
            } else {
                return 0;
            }
        }

        fn provide_to_sp(ref self: ContractState, top_up: u256, do_claim: bool) {
            InternalImpl::_require_non_zero_amount(top_up);

            let active_pool = IActivePoolDispatcher {
                contract_address: self.liquity_base.active_pool.read(),
            };
            active_pool.mint_agg_interest();

            let depositor = get_caller_address();
            let initial_deposit = self.deposits.read(depositor).initial_value;

            let current_coll_gain = self.get_depositor_coll_gain(depositor);
            let current_yield_gain = self.get_depositor_yield_gain(depositor);
            let compounded_bitusd_deposit = self.get_compounded_bitusd_deposit(depositor);
            let (kept_yield_gain, yield_gain_to_send) = InternalImpl::_get_yield_to_keep_or_send(
                current_yield_gain, do_claim,
            );
            let new_deposit = compounded_bitusd_deposit + top_up + kept_yield_gain;
            let (new_stashed_coll, coll_to_send) = self
                ._get_new_stashed_coll_and_coll_to_send(depositor, current_coll_gain, do_claim);

            self
                .emit(
                    Event::DepositOperation(
                        DepositOperation {
                            depositor: depositor,
                            operation: Operation::provide_to_sp,
                            deposit_loss_since_last_operation: initial_deposit
                                - compounded_bitusd_deposit,
                            top_up_or_withdrawal: (top_up.try_into().unwrap()),
                            yield_gain_since_last_operation: current_yield_gain,
                            yield_gain_claimed: yield_gain_to_send,
                            eth_gain_since_last_operation: current_coll_gain,
                            eth_gain_claimed: coll_to_send,
                        },
                    ),
                );

            self._update_deposit_and_snapshots(depositor, new_deposit, new_stashed_coll);
            // missing
            let bitusd_token = IBitUSDDispatcher { contract_address: self.bitusd_token.read() };
            bitusd_token.send_to_pool(depositor, get_contract_address(), top_up);
            self._update_total_bitusd_deposits(top_up + kept_yield_gain, 0);
            self._decrease_yield_gains_owed(current_yield_gain);
            self._send_bitusd_to_depositor(depositor, yield_gain_to_send);
            self._send_coll_gain_to_depositor(coll_to_send);

            // If there were pending yield and with the new deposit we are reaching the threshold,
            // let's move the yield to owed
            self._update_yield_rewards_sum(0);
        }

        fn withdraw_from_sp(ref self: ContractState, amount: u256, do_claim: bool) {
            let depositor = get_caller_address();
            let initial_deposit = self.deposits.read(depositor).initial_value;
            InternalTrait::_require_user_has_deposit(initial_deposit);

            let active_pool = IActivePoolDispatcher {
                contract_address: self.liquity_base.active_pool.read(),
            };
            active_pool.mint_agg_interest();

            let current_coll_gain = self.get_depositor_coll_gain(depositor);
            let current_yield_gain = self.get_depositor_yield_gain(depositor);
            let compounded_bitusd_deposit = self.get_compounded_bitusd_deposit(depositor);
            let bitusd_to_withdraw = core::cmp::min(amount, compounded_bitusd_deposit);
            let (kept_yield_gain, yield_gain_to_send) = InternalImpl::_get_yield_to_keep_or_send(
                current_yield_gain, do_claim,
            );
            let new_deposit = compounded_bitusd_deposit - bitusd_to_withdraw + kept_yield_gain;
            let (new_stashed_coll, coll_to_send) = self
                ._get_new_stashed_coll_and_coll_to_send(depositor, current_coll_gain, do_claim);

            self
                .emit(
                    Event::DepositOperation(
                        DepositOperation {
                            depositor: depositor,
                            operation: Operation::withdraw_from_sp,
                            deposit_loss_since_last_operation: initial_deposit
                                - compounded_bitusd_deposit,
                            top_up_or_withdrawal: I257Trait::new(bitusd_to_withdraw, true),
                            yield_gain_since_last_operation: current_yield_gain,
                            yield_gain_claimed: yield_gain_to_send,
                            eth_gain_since_last_operation: current_coll_gain,
                            eth_gain_claimed: coll_to_send,
                        },
                    ),
                );

            self._update_deposit_and_snapshots(depositor, new_deposit, new_stashed_coll);
            self._decrease_yield_gains_owed(current_yield_gain);
            let new_total_bitusd_deposits = self
                ._update_total_bitusd_deposits(kept_yield_gain, bitusd_to_withdraw);
            self._send_bitusd_to_depositor(depositor, bitusd_to_withdraw + yield_gain_to_send);
            self._send_coll_gain_to_depositor(coll_to_send);

            assert(new_total_bitusd_deposits >= MIN_BITUSD_IN_SP, 'SP: Total deposits <= minimum');
        }

        fn claim_all_coll_gains(ref self: ContractState) {
            let depositor = get_caller_address();
            self._require_user_has_no_deposit(depositor);

            let active_pool = IActivePoolDispatcher {
                contract_address: self.liquity_base.active_pool.read(),
            };
            active_pool.mint_agg_interest();

            let coll_to_send = self.stashed_coll.read(depositor);
            InternalTrait::_require_non_zero_amount(coll_to_send);
            self.stashed_coll.write(depositor, 0);

            self
                .emit(
                    Event::DepositOperation(
                        DepositOperation {
                            depositor: depositor,
                            operation: Operation::claim_all_coll_gains,
                            deposit_loss_since_last_operation: 0,
                            top_up_or_withdrawal: I257Trait::new(0, false),
                            yield_gain_since_last_operation: 0,
                            yield_gain_claimed: 0,
                            eth_gain_since_last_operation: 0,
                            eth_gain_claimed: coll_to_send,
                        },
                    ),
                );
            self
                .emit(
                    Event::DepositUpdated(
                        DepositUpdated {
                            depositor: depositor,
                            new_deposit: 0,
                            stashed_coll: 0,
                            snapshot_p: 0,
                            snapshot_s: 0,
                            snapshot_b: 0,
                            snapshot_scale: 0,
                        },
                    ),
                );

            self._send_coll_gain_to_depositor(coll_to_send);
        }

        fn trigger_bitusd_rewards(ref self: ContractState, bold_yield: u256) {
            self._require_caller_is_active_pool();
            self._update_yield_rewards_sum(bold_yield);
        }

        fn offset(ref self: ContractState, debt_to_offset: u256, coll_to_add: u256) {
            self._require_caller_is_trove_manager();

            let current_scale = self.current_scale.read();
            let new_s = self.scale_to_s.read(current_scale)
                + self.P.read() * coll_to_add / self.total_bitusd_deposits.read();
            self.scale_to_s.write(current_scale, new_s);
            self.emit(Event::S_Updated(S_Updated { S: new_s, scale: current_scale }));

            let mut numerator = self.P.read()
                * (self.total_bitusd_deposits.read() - debt_to_offset);
            let mut new_p = numerator / self.total_bitusd_deposits.read();

            // For `P` to turn zero, `totalBoldDeposits` has to be greater than `P *
            // (totalBoldDeposits - _debtToOffset)`.
            // - As the offset must leave at least 1 BOLD in the SP (MIN_BOLD_IN_SP),
            //   the minimum value of `totalBoldDeposits - _debtToOffset` is `1e18`
            // - It can be shown that `P` is always in range (1e27, 1e36].
            // Thus, to turn `P` zero, `totalBoldDeposits` has to be greater than `(1e27 + 1) *
            // 1e18`, and the offset has to be (near) maximal.
            // In other words, there needs to be octillions of BOLD in the SP, which is unlikely to
            // happen in practice.
            assert(new_p > 0, 'P must never decrease to 0');

            // Overflow analyisis of scaling up P:
            // We know that the resulting P is <= 1e36, and it's the result of dividing numerator by
            // totalBoldDeposits.
            // Thus, numerator <= 1e36 * totalBoldDeposits, so unless totalBoldDeposits is
            // septillions of BOLD, it won’t overflow.
            // That holds on every iteration as an upper bound. We multiply numerator by
            // SCALE_FACTOR, but numerator is by definition smaller than 1e36 * totalBoldDeposits /
            // SCALE_FACTOR.
            let mut current_scale = self.current_scale.read();
            let total_bitusd_deposits = self.total_bitusd_deposits.read();
            while (new_p < P_PRECISION / SCALE_FACTOR) {
                numerator *= SCALE_FACTOR;
                new_p = new_p / total_bitusd_deposits;
                current_scale += 1;
                self.emit(Event::ScaleUpdated(ScaleUpdated { current_scale }));
            }
            self.current_scale.write(current_scale);

            self.emit(Event::P_Updated(P_Updated { P: new_p }));
            self.P.write(new_p);

            self._move_offset_coll_and_debt(coll_to_add, debt_to_offset);
        }

        fn get_depositor_coll_gain(self: @ContractState, depositor: ContractAddress) -> u256 {
            let initial_deposit = self.deposits.read(depositor).initial_value;
            if (initial_deposit == 0) {
                return 0;
            }

            let snapshots = self.deposit_snapshots.read(depositor);

            // Coll gains from the same scale in which the deposit was made need no scaling
            let mut normalized_gains = (self.scale_to_s.read(snapshots.scale)) - snapshots.S;

            // Scale down further coll gains by a power of `SCALE_FACTOR` depending on how many
            // scale changes they span
            for i in 1..=SCALE_SPAN {
                normalized_gains += self.scale_to_s.read(snapshots.scale + i)
                    / fast_power(SCALE_FACTOR, i);
            }

            return core::cmp::min(
                initial_deposit * normalized_gains / snapshots.P, self.coll_balance.read(),
            );
        }

        fn get_depositor_yield_gain(self: @ContractState, depositor: ContractAddress) -> u256 {
            let initial_deposit = self.deposits.read(depositor).initial_value;
            if (initial_deposit == 0) {
                return 0;
            }

            let snapshots = self.deposit_snapshots.read(depositor);

            let mut normalized_gains = self.scale_to_b.read(snapshots.scale) - snapshots.B;

            for i in 1..=SCALE_SPAN {
                normalized_gains += self.scale_to_b.read(snapshots.scale + i)
                    / fast_power(SCALE_FACTOR, i);
            }

            return core::cmp::min(
                initial_deposit * normalized_gains / snapshots.P, self.yield_gains_owed.read(),
            );
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn _require_non_zero_amount(amount: u256) {
            assert(amount > 0, 'SP: Amount must be non-zero');
        }

        fn _require_user_has_deposit(initial_deposit: u256) {
            assert(initial_deposit > 0, 'SP: User has no deposit');
        }

        fn _require_user_has_no_deposit(self: @ContractState, address: ContractAddress) {
            let initial_deposit = self.deposits.read(address).initial_value;
            assert(initial_deposit == 0, 'SP: User has a deposit');
        }

        fn _require_caller_is_active_pool(self: @ContractState) {
            assert(
                get_caller_address() == self.liquity_base.active_pool.read(),
                'SP: Caller not active pool',
            );
        }

        fn _require_caller_is_trove_manager(self: @ContractState) {
            assert(
                get_caller_address() == self.trove_manager.read(), 'SP: Caller not trove manager',
            );
        }

        fn _get_yield_to_keep_or_send(current_yield_gain: u256, do_claim: bool) -> (u256, u256) {
            if (do_claim) {
                return (0, current_yield_gain);
            } else {
                return (current_yield_gain, 0);
            }
        }

        fn _get_new_stashed_coll_and_coll_to_send(
            self: @ContractState,
            depositor: ContractAddress,
            current_coll_gain: u256,
            do_claim: bool,
        ) -> (u256, u256) {
            if (do_claim) {
                return (0, self.stashed_coll.read(depositor) + current_coll_gain);
            } else {
                return (self.stashed_coll.read(depositor) + current_coll_gain, 0);
            }
        }

        fn _update_deposit_and_snapshots(
            ref self: ContractState,
            depositor: ContractAddress,
            new_deposit: u256,
            new_stashed_coll: u256,
        ) {
            self.deposits.write(depositor, Deposit { initial_value: new_deposit });
            self.stashed_coll.write(depositor, new_stashed_coll);

            if new_deposit == 0 {
                // We can't delete the deposit snapshots mapping entry, so we set it to the default
                self.deposit_snapshots.write(depositor, Default::default());
                self
                    .emit(
                        Event::DepositUpdated(
                            DepositUpdated {
                                depositor: depositor,
                                new_deposit: 0,
                                stashed_coll: new_stashed_coll,
                                snapshot_p: 0,
                                snapshot_s: 0,
                                snapshot_b: 0,
                                snapshot_scale: 0,
                            },
                        ),
                    );
                return;
            }

            let current_scale_cached = self.current_scale.read();
            let current_P = self.P.read();

            // Get S for the current scale
            let current_S = self.scale_to_s.read(current_scale_cached);
            let current_B = self.scale_to_b.read(current_scale_cached);

            // Record new snapshots of the latest running product P and sum S for the depositor
            let new_snapshots = Snapshots {
                S: current_S, P: current_P, B: current_B, scale: current_scale_cached,
            };
            self.deposit_snapshots.write(depositor, new_snapshots);

            self
                .emit(
                    Event::DepositUpdated(
                        DepositUpdated {
                            depositor: depositor,
                            new_deposit: new_deposit,
                            stashed_coll: new_stashed_coll,
                            snapshot_p: current_P,
                            snapshot_s: current_S,
                            snapshot_b: current_B,
                            snapshot_scale: current_scale_cached,
                        },
                    ),
                );
        }

        fn _update_total_bitusd_deposits(
            ref self: ContractState, deposit_increase: u256, deposit_decrease: u256,
        ) -> u256 {
            if (deposit_increase == 0 && deposit_decrease == 0) {
                return self.total_bitusd_deposits.read();
            }

            let new_total_bitusd_deposits = self.total_bitusd_deposits.read()
                + deposit_increase
                - deposit_decrease;
            self.total_bitusd_deposits.write(new_total_bitusd_deposits);
            // emit StabilityPoolBitUSDBalanceUpdated
            self
                .emit(
                    Event::StabilityPoolBitUSDBalanceUpdated(
                        StabilityPoolBitUSDBalanceUpdated {
                            new_balance: new_total_bitusd_deposits,
                        },
                    ),
                );
            return new_total_bitusd_deposits;
        }

        fn _move_offset_coll_and_debt(
            ref self: ContractState, coll_to_add: u256, debt_to_offset: u256,
        ) {
            // Cancel the liquidated Bold debt with the Bold in the stability pool
            self._update_total_bitusd_deposits(0, debt_to_offset);

            // Burn the debt that was successfully offset
            let bold_token = IBitUSDDispatcher { contract_address: self.bitusd_token.read() };
            bold_token.burn(get_contract_address(), debt_to_offset);

            // Update internal Coll balance tracker
            let new_coll_balance = self.coll_balance.read() + coll_to_add;
            self.coll_balance.write(new_coll_balance);

            // Pull Coll from Active Pool
            let active_pool = IActivePoolDispatcher {
                contract_address: self.liquity_base.active_pool.read(),
            };
            active_pool.send_coll(get_contract_address(), coll_to_add);

            self
                .emit(
                    Event::StabilityPoolCollBalanceUpdated(
                        StabilityPoolCollBalanceUpdated { new_balance: new_coll_balance },
                    ),
                );
        }

        fn _decrease_yield_gains_owed(ref self: ContractState, amount: u256) {
            if amount == 0 {
                return;
            }
            let new_yield_gains_owed = self.yield_gains_owed.read() - amount;
            self.yield_gains_owed.write(new_yield_gains_owed);
        }

        // --- Sender functions for BitUSD deposit and Coll gains ---
        fn _send_coll_gain_to_depositor(ref self: ContractState, coll_amount: u256) {
            if (coll_amount == 0) {
                return;
            }

            let new_coll_balance = self.coll_balance.read() - coll_amount;
            self.coll_balance.write(new_coll_balance);

            // emit StabilityPoolCollBalanceUpdated
            self
                .emit(
                    Event::StabilityPoolCollBalanceUpdated(
                        StabilityPoolCollBalanceUpdated { new_balance: new_coll_balance },
                    ),
                );
            let coll_token = IERC20Dispatcher { contract_address: self.coll_token.read() };
            coll_token.transfer(get_caller_address(), coll_amount);
        }

        // Send BitUSD to user and decrease BitUSD in Pool
        fn _send_bitusd_to_depositor(
            self: @ContractState, depositor: ContractAddress, bitusd_to_send: u256,
        ) {
            if (bitusd_to_send == 0) {
                return;
            }

            let bitusd_token = IBitUSDDispatcher { contract_address: self.bitusd_token.read() };
            bitusd_token.return_from_pool(get_contract_address(), depositor, bitusd_to_send);
        }

        fn _update_yield_rewards_sum(ref self: ContractState, new_yield: u256) {
            let accumulated_yield_gains = self.yield_gains_pending.read() + new_yield;
            if accumulated_yield_gains == 0 {
                return;
            }

            // When total deposits is very small, B is not updated. In this case, the BOLD issued is
            // held until the total deposits reach 1 BOLD (remains in the balance of the SP).
            if (self.total_bitusd_deposits.read() < MIN_BITUSD_IN_SP) {
                self.yield_gains_pending.write(accumulated_yield_gains);
                return;
            }

            self.yield_gains_owed.write(self.yield_gains_owed.read() + accumulated_yield_gains);
            self.yield_gains_pending.write(0);

            let current_scale = self.current_scale.read();
            let scale_to_b = self.scale_to_b.read(current_scale)
                + self.P.read() * accumulated_yield_gains / self.total_bitusd_deposits.read();
            self.scale_to_b.write(current_scale, scale_to_b);

            self.emit(Event::B_Updated(B_Updated { B: scale_to_b, scale: current_scale }));
        }
    }
}
