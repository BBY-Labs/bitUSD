use core::num::traits::Zero;
use starknet::ContractAddress;
use crate::BorrowerOperations::BorrowerOperations::{
    InterestIndividualDelegate, OpenTroveAndJoinInterestBatchManagerParams,
};

#[starknet::interface]
pub trait IBorrowerOperations<TContractState> {
    fn open_trove(
        ref self: TContractState,
        owner: ContractAddress,
        owner_index: u256,
        coll_amount: u256,
        bitusd_amount: u256,
        upper_hint: u256,
        lower_hint: u256,
        annual_interest_rate: u256,
        max_upfront_fee: u256,
        add_manager: ContractAddress,
        remove_manager: ContractAddress,
        receiver: ContractAddress,
    ) -> u256;
    fn open_trove_and_join_interest_batch_manager(
        ref self: TContractState, params: OpenTroveAndJoinInterestBatchManagerParams,
    ) -> u256;
    fn add_coll(ref self: TContractState, trove_id: u256, coll_amount: u256);
    fn withdraw_coll(ref self: TContractState, trove_id: u256, coll_withdrawal: u256);
    fn withdraw_bitusd(
        ref self: TContractState, trove_id: u256, bitusd_amount: u256, max_upfront_fee: u256,
    );
    fn repay_bitusd(ref self: TContractState, trove_id: u256, bitusd_amount: u256);
    fn close_trove(ref self: TContractState, trove_id: u256);
    fn adjust_trove(
        ref self: TContractState,
        trove_id: u256,
        coll_change: u256,
        is_coll_increase: bool,
        debt_change: u256,
        is_debt_increase: bool,
        max_upfront_fee: u256,
    );

    fn adjust_zombie_trove(
        ref self: TContractState,
        trove_id: u256,
        coll_change: u256,
        is_coll_increase: bool,
        debt_change: u256,
        is_debt_increase: bool,
        upper_hint: u256,
        lower_hint: u256,
        max_upfront_fee: u256,
    );
    fn adjust_trove_interest_rate(
        ref self: TContractState,
        trove_id: u256,
        new_annual_interest_rate: u256,
        upper_hint: u256,
        lower_hint: u256,
        max_upfront_fee: u256,
    );

    fn apply_pending_debt(
        ref self: TContractState, trove_id: u256, lower_hint: u256, upper_hint: u256,
    );

    fn on_liquidate_trove(ref self: TContractState, trove_id: u256);

    fn claim_collateral(ref self: TContractState);
    fn has_been_shutdown(self: @TContractState) -> bool;
    fn shutdown(ref self: TContractState);
    fn shutdown_from_oracle_failure(ref self: TContractState);
    fn check_batch_manager_exists(self: @TContractState, batch_manager: ContractAddress) -> bool;

    fn get_interest_individual_delegate_of(
        ref self: TContractState, trove_id: u256,
    ) -> InterestIndividualDelegate;

    fn set_interest_individual_delegate(
        ref self: TContractState,
        trove_id: u256,
        delegate: ContractAddress,
        min_interest_rate: u128,
        max_interest_rate: u128,
        new_annual_interest_rate: u256,
        upper_hint: u256,
        lower_hint: u256,
        max_upfront_fee: u256,
        min_interest_rate_change_period: u256,
    );

    fn set_interest_batch_manager(
        ref self: TContractState,
        trove_id: u256,
        new_batch_manager: ContractAddress,
        upper_hint: u256,
        lower_hint: u256,
        max_upfront_fee: u256,
    );

    fn remove_from_batch(
        ref self: TContractState,
        trove_id: u256,
        new_annual_interest_rate: u256,
        upper_hint: u256,
        lower_hint: u256,
        max_upfront_fee: u256,
    );
    fn switch_batch_manager(
        ref self: TContractState,
        trove_id: u256,
        remove_upper_hint: u256,
        remove_lower_hint: u256,
        new_batch_manager: ContractAddress,
        add_upper_hint: u256,
        add_lower_hint: u256,
        max_upfront_fee: u256,
    );
}

// Needed for
impl ContractAddressDefault of Default<ContractAddress> {
    fn default() -> ContractAddress {
        Zero::zero()
    }
}

#[starknet::contract]
pub mod BorrowerOperations {
    use core::hash::{HashStateExTrait, HashStateTrait};
    use core::poseidon::PoseidonTrait;
    use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };
    use starknet::{ContractAddress, get_block_timestamp, get_caller_address};
    use crate::ActivePool::{IActivePoolDispatcher, IActivePoolDispatcherTrait};
    use crate::AddressesRegistry::{IAddressesRegistryDispatcher, IAddressesRegistryDispatcherTrait};
    use crate::BitUSD::{IBitUSDDispatcher, IBitUSDDispatcherTrait};
    use crate::CollSurplusPool::{ICollSurplusPoolDispatcher, ICollSurplusPoolDispatcherTrait};
    use crate::SortedTroves::{ISortedTrovesDispatcher, ISortedTrovesDispatcherTrait};
    use crate::TroveManager::{
        ITroveManagerDispatcher, ITroveManagerDispatcherTrait, LatestBatchData, LatestTroveData,
        OnSetInterestBatchManagerParams, Status, TroveChange,
    };
    use crate::dependencies::Constants::Constants::{
        DECIMAL_PRECISION, ETH_GAS_COMPENSATION, INTEREST_RATE_ADJ_COOLDOWN,
        MAX_ANNUAL_INTEREST_RATE, MAX_BATCH_SHARES_RATIO, MIN_ANNUAL_INTEREST_RATE, MIN_DEBT,
        ONE_YEAR, UPFRONT_INTEREST_PERIOD,
    };
    use crate::dependencies::LiquityBase::LiquityBaseComponent;
    use crate::dependencies::MathLib::math_lib;
    use crate::mocks::PriceFeedMock::{IPriceFeedMockDispatcher, IPriceFeedMockDispatcherTrait};
    use super::{ContractAddressDefault, IBorrowerOperations};
    // use crate::dependencies::AddRemoveManagers; // TODO addRemoveManagers

    component!(path: LiquityBaseComponent, storage: liquity_base, event: LiquityBaseEvent);

    #[derive(Copy, Drop, Default, Serde, starknet::Store)]
    pub struct InterestIndividualDelegate {
        pub account: ContractAddress,
        pub min_interest_rate: u128, // TODO check this is safe? (instead of u256)
        pub max_interest_rate: u128, // TODO check this is safe? (instead of u256)
        pub min_interest_rate_change_period: u256,
    }

    #[derive(Copy, Drop, Default, Serde, starknet::Store)]
    pub struct InterestBatchManager {
        pub min_interest_rate: u128,
        pub max_interest_rate: u128,
        pub min_interest_rate_change_period: u256,
    }

    #[storage]
    struct Storage {
        coll_token: ContractAddress,
        trove_manager: ContractAddress,
        gas_pool_address: ContractAddress,
        coll_surplus_pool: ContractAddress,
        bitusd_token: ContractAddress,
        sorted_troves: ContractAddress, // A doubly linked list of Troves, sorted by their collateral ratio
        eth: ContractAddress, // TODO: change Wrapped ETH for liquidation reserve (gas compenstaion) TODO
        ccr: u256, // Critical system collateral ratio. If the system's total collateral ratio (TCR) falls below the CCR, some borrowing operation restrictions are applied.
        scr: u256, // Shutdown system collateral ratio. If the system's total collateral ratio (TCR) for a given collateral falls below the SCR, the protocol triggers the shutdown of the borrow market and permanently disables all borrowing operations except for closing Troves.
        has_been_shutdown: bool,
        mcr: u256, // Minimum collateral ratio for individual troves
        bcr: u256, // Extra buffer of collateral ratio to join a batch or adjust a trove inside a batch (on top of MCR)
        // Mapping of TroveId to individual delegate for interest rate setting.
        // This address then has the ability to update the borrower's interest rate, but not change
        // its debt or collateral.
        // Useful for instance for cold / hot wallet setups.
        interest_individual_delegate_of: Map<u256, InterestIndividualDelegate>,
        // Mapping from TroveId to granted address for interest rate setting (batch manager).
        // Batch managers set the interest rate for every Trove in the batch. The interest rate it
        // the same for all Troves in the batch.
        interest_batch_manager_of: Map<u256, ContractAddress>,
        // List of registered Interest Batch Managers
        interest_batch_managers: Map<ContractAddress, InterestBatchManager>,
        #[substorage(v0)]
        liquity_base: LiquityBaseComponent::Storage,
        // TODO addRemoveManagers
    }

    // --- Variable container structs  --- TODO
    // Used to hold, return and assign variables inside a function, in order to avoid the error:
    // "CompilerError: Stack too deep".
    #[derive(Copy, Drop, Serde, Default)]
    struct OpenTroveVars {
        trove_manager: ContractAddress,
        trove_id: u256,
        change: TroveChange,
        batch: LatestBatchData,
    }

    #[derive(Copy, Drop, Serde, Default)]
    pub struct OpenTroveAndJoinInterestBatchManagerParams {
        owner: ContractAddress,
        owner_index: u256,
        coll_amount: u256,
        bitusd_amount: u256,
        upper_hint: u256,
        lower_hint: u256,
        interest_batch_manager: ContractAddress,
        max_upfront_fee: u256,
        add_manager: ContractAddress,
        remove_manager: ContractAddress,
        receiver: ContractAddress,
    }


    #[derive(Copy, Drop, Serde, Default)]
    struct LocalVariables_openTrove {
        trove_manager: ContractAddress,
        active_pool: ContractAddress,
        bitusd_token: ContractAddress,
        trove_id: u256,
        price: u256,
        avg_interest_rate: u256,
        entire_debt: u256,
        ICR: u256,
        new_TCR: u256,
        new_oracle_failure_detected: bool,
    }

    #[derive(Copy, Drop, Serde, Default)]
    struct LocalVariables_adjustTrove {
        active_pool: ContractAddress,
        bitusd_token: ContractAddress,
        trove: LatestTroveData,
        price: u256,
        is_below_critical_threshold: bool,
        new_ICR: u256,
        new_debt: u256,
        new_coll: u256,
        new_oracle_failure_detected: bool,
    }

    #[derive(Copy, Drop, Serde, Default)]
    struct LocalVariables_setInterestBatchManager {
        trove_manager: ContractAddress,
        active_pool: ContractAddress,
        sorted_troves: ContractAddress,
        old_batch_manager: ContractAddress,
        trove: LatestTroveData,
        old_batch: LatestBatchData,
        new_batch: LatestBatchData,
    }

    #[derive(Copy, Drop, Serde, Default)]
    struct LocalVariables_removeFromBatch {
        trove_manager: ContractAddress,
        sorted_troves: ContractAddress,
        batch_manager: ContractAddress,
        trove: LatestTroveData,
        batch: LatestBatchData,
        batch_future_debt: u256,
        batch_change: TroveChange,
    }


    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        TroveManagerAddressChanged: TroveManagerAddressChanged,
        GasPoolAddressChanged: GasPoolAddressChanged,
        CollSurplusPoolAddressChanged: CollSurplusPoolAddressChanged,
        SortedTrovesAddressChanged: SortedTrovesAddressChanged,
        BitUSDTokenAddressChanged: BitUSDTokenAddressChanged,
        ShutDown: ShutDown,
        #[flat]
        LiquityBaseEvent: LiquityBaseComponent::Event,
    }

    #[derive(Drop, starknet::Event)]
    pub struct TroveManagerAddressChanged {
        pub new_trove_manager_address: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    pub struct GasPoolAddressChanged {
        pub gas_pool_address: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    pub struct CollSurplusPoolAddressChanged {
        pub coll_surplus_pool_address: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    pub struct SortedTrovesAddressChanged {
        pub sorted_troves_address: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    pub struct BitUSDTokenAddressChanged {
        pub bitusd_token_address: ContractAddress,
    }


    #[derive(Drop, starknet::Event)]
    pub struct ShutDown {
        pub tcr: u256,
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
        // TOOD addRemoveManagers
        self.liquity_base.initializer(addresses_registry);

        assert(MIN_DEBT != 0, 'MIN_DEBT is 0');

        let addresses_registry_contract = IAddressesRegistryDispatcher {
            contract_address: addresses_registry,
        };

        self.coll_token.write(addresses_registry_contract.get_coll_token());
        self.eth.write(addresses_registry_contract.get_eth());
        self.ccr.write(addresses_registry_contract.get_CCR());
        self.scr.write(addresses_registry_contract.get_SCR());
        self.mcr.write(addresses_registry_contract.get_MCR());
        self.bcr.write(addresses_registry_contract.get_BCR());

        self.trove_manager.write(addresses_registry_contract.get_trove_manager());
        self.gas_pool_address.write(addresses_registry_contract.get_gas_pool());
        self.coll_surplus_pool.write(addresses_registry_contract.get_coll_surplus_pool());
        self.sorted_troves.write(addresses_registry_contract.get_sorted_troves());
        self.bitusd_token.write(addresses_registry_contract.get_bitusd_token());

        self
            .emit(
                event: TroveManagerAddressChanged {
                    new_trove_manager_address: self.trove_manager.read(),
                },
            );

        self.emit(event: GasPoolAddressChanged { gas_pool_address: self.gas_pool_address.read() });

        self
            .emit(
                event: CollSurplusPoolAddressChanged {
                    coll_surplus_pool_address: self.coll_surplus_pool.read(),
                },
            );
        self
            .emit(
                event: SortedTrovesAddressChanged {
                    sorted_troves_address: self.sorted_troves.read(),
                },
            );
        self
            .emit(
                event: BitUSDTokenAddressChanged { bitusd_token_address: self.bitusd_token.read() },
            );

        let coll_token_contract = IERC20Dispatcher { contract_address: self.coll_token.read() };

        coll_token_contract
            .approve(self.liquity_base.active_pool.read(), core::num::traits::Bounded::MAX);
    }

    ////////////////////////////////////////////////////////////////
    //                     EXTERNAL FUNCTIONS                     //
    ////////////////////////////////////////////////////////////////
    #[abi(embed_v0)]
    impl BorrowerOperationsImpl of IBorrowerOperations<ContractState> {
        // Claim remaining collateral from a liquidation with ICR exceeding the liquidation penalty
        fn claim_collateral(ref self: ContractState) {
            let coll_surplus_pool = ICollSurplusPoolDispatcher {
                contract_address: self.coll_surplus_pool.read(),
            };
            // send coll from CollSurplus Pool to owner
            coll_surplus_pool.claim_coll(get_caller_address());
        }

        fn shutdown(ref self: ContractState) {
            assert(!self.has_been_shutdown.read(), 'BO: already shutdown');

            let total_coll = self.liquity_base.get_entire_branch_coll();
            let total_debt = self.liquity_base.get_entire_branch_debt();

            let price_feed = IPriceFeedMockDispatcher {
                contract_address: self.liquity_base.price_feed.read(),
            };
            let (price, new_oracle_failure_detected) = price_feed.fetch_price();

            // If the oracle failed, the above call to PriceFeed will have shut this branch down
            if new_oracle_failure_detected {
                return;
            }

            // Otherwise, proceed with the TCR check:
            let tcr = math_lib::compute_cr(total_coll, total_debt, price);
            assert(tcr < self.scr.read(), 'BO: tcr not below scr');

            self._apply_shutdown();

            self.emit(event: ShutDown { tcr });
        }

        fn shutdown_from_oracle_failure(ref self: ContractState) {
            self._require_caller_is_price_feed();

            // No-op rather than revert here, so that the outre function call which fetches the
            // price does not revert if the system is already shutdown
            if self.has_been_shutdown.read() {
                return;
            }

            self._apply_shutdown();

            self.emit(event: ShutDown { tcr: 0 });
        }

        fn check_batch_manager_exists(
            self: @ContractState, batch_manager: ContractAddress,
        ) -> bool {
            self.interest_batch_managers.read(batch_manager).max_interest_rate != 0
        }

        fn has_been_shutdown(self: @ContractState) -> bool {
            self.has_been_shutdown.read()
        }

        fn open_trove(
            ref self: ContractState,
            owner: ContractAddress,
            owner_index: u256,
            coll_amount: u256,
            bitusd_amount: u256,
            upper_hint: u256,
            lower_hint: u256,
            annual_interest_rate: u256,
            max_upfront_fee: u256,
            add_manager: ContractAddress,
            remove_manager: ContractAddress,
            receiver: ContractAddress,
        ) -> u256 {
            InternalTrait::_require_valid_annual_interest_rate(annual_interest_rate);

            // let trove_id =
            let mut vars: OpenTroveVars = Default::default();

            vars
                .trove_id = self
                ._open_trove(
                    owner,
                    owner_index,
                    coll_amount,
                    bitusd_amount,
                    annual_interest_rate,
                    Default::default(),
                    0,
                    0,
                    max_upfront_fee,
                    add_manager,
                    remove_manager,
                    receiver,
                    ref vars.change,
                );

            // Set the stored Trove properties and mint the NFT
            let trove_manager = ITroveManagerDispatcher {
                contract_address: self.trove_manager.read(),
            };
            trove_manager.on_open_trove(owner, vars.trove_id, vars.change, annual_interest_rate);

            let sorted_troves = ISortedTrovesDispatcher {
                contract_address: self.sorted_troves.read(),
            };
            sorted_troves.insert(vars.trove_id, annual_interest_rate, upper_hint, lower_hint);

            return vars.trove_id;
        }

        fn open_trove_and_join_interest_batch_manager(
            ref self: ContractState, params: OpenTroveAndJoinInterestBatchManagerParams,
        ) -> u256 {
            self._require_valid_interest_batch_manager(params.interest_batch_manager);

            let mut vars: OpenTroveVars = Default::default();
            vars.trove_manager = self.trove_manager.read();

            let trove_manager = ITroveManagerDispatcher { contract_address: vars.trove_manager };
            vars.batch = trove_manager.get_latest_batch_data(params.interest_batch_manager);

            // We set old weighted values here, as it's only necessary for abtches, so we don't need
            // ot pass them to _openTrove func
            vars.change.batch_accrued_management_fee = vars.batch.accrued_management_fee;
            vars.change.old_weighted_recorded_debt = vars.batch.weighted_recorded_debt;
            vars
                .change
                .old_weighted_recorded_batch_management_fee = vars
                .batch
                .weighted_recorded_batch_management_fee;
            vars
                .trove_id = self
                ._open_trove(
                    params.owner,
                    params.owner_index,
                    params.coll_amount,
                    params.bitusd_amount,
                    vars.batch.annual_interest_rate,
                    params.interest_batch_manager,
                    vars.batch.entire_debt_without_redistribution,
                    vars.batch.annual_management_fee,
                    params.max_upfront_fee,
                    params.add_manager,
                    params.remove_manager,
                    params.receiver,
                    ref vars.change,
                );

            self.interest_batch_manager_of.write(vars.trove_id, params.interest_batch_manager);

            // Set the stored Trove properties and mint the NFT
            trove_manager
                .on_open_trove_and_join_batch(
                    params.owner,
                    vars.trove_id,
                    vars.change,
                    params.interest_batch_manager,
                    vars.batch.entire_coll_without_redistribution,
                    vars.batch.entire_debt_without_redistribution,
                );

            let sorted_troves = ISortedTrovesDispatcher {
                contract_address: self.sorted_troves.read(),
            };
            sorted_troves
                .insert_into_batch(
                    vars.trove_id,
                    params.interest_batch_manager,
                    vars.batch.annual_interest_rate,
                    params.upper_hint,
                    params.lower_hint,
                ); // TODO BatchId.wrap

            return vars.trove_id;
        }

        // Call from TM to clean state here
        fn on_liquidate_trove(ref self: ContractState, trove_id: u256) {
            self._require_caller_is_trove_manager();

            self._wipe_trove_mappings(trove_id);
        }

        fn add_coll(ref self: ContractState, trove_id: u256, coll_amount: u256) {
            let trove_manager_cached = self.trove_manager.read();
            InternalTrait::_require_trove_is_active(trove_manager_cached, trove_id);

            let mut trove_change: TroveChange = Default::default();
            trove_change.coll_increase = coll_amount;

            self
                ._adjust_trove(
                    trove_manager_cached, trove_id, ref trove_change, 0 // maxUpfrontFee
                );
        }

        // Withdraw collateral from a trove
        fn withdraw_coll(ref self: ContractState, trove_id: u256, coll_withdrawal: u256) {
            let trove_manager_cached = self.trove_manager.read();
            InternalTrait::_require_trove_is_active(trove_manager_cached, trove_id);

            let mut trove_change: TroveChange = Default::default();
            trove_change.coll_decrease = coll_withdrawal;

            self
                ._adjust_trove(
                    trove_manager_cached, trove_id, ref trove_change, 0 // maxUpfrontFee
                );
        }

        fn withdraw_bitusd(
            ref self: ContractState, trove_id: u256, bitusd_amount: u256, max_upfront_fee: u256,
        ) {
            let trove_manager_cached = self.trove_manager.read();
            InternalTrait::_require_trove_is_active(trove_manager_cached, trove_id);

            let mut trove_change: TroveChange = Default::default();
            trove_change.debt_increase = bitusd_amount;

            self._adjust_trove(trove_manager_cached, trove_id, ref trove_change, max_upfront_fee);
        }

        // Repay Bold tokens to a Trove: Burn the repaid Bold tokens, and reduce the trove's debt
        // accordingly
        fn repay_bitusd(ref self: ContractState, trove_id: u256, bitusd_amount: u256) {
            let trove_manager_cached = self.trove_manager.read();
            InternalTrait::_require_trove_is_active(trove_manager_cached, trove_id);

            let mut trove_change: TroveChange = Default::default();
            trove_change.debt_decrease = bitusd_amount;

            self
                ._adjust_trove(
                    trove_manager_cached, trove_id, ref trove_change, 0,
                ); // _maxUpfrontFee
        }

        fn adjust_trove(
            ref self: ContractState,
            trove_id: u256,
            coll_change: u256,
            is_coll_increase: bool,
            debt_change: u256,
            is_debt_increase: bool,
            max_upfront_fee: u256,
        ) {
            let trove_manager_cached = self.trove_manager.read();
            InternalTrait::_require_trove_is_active(trove_manager_cached, trove_id);

            let mut trove_change: TroveChange = Default::default();
            self
                ._init_trove_change(
                    ref trove_change, coll_change, is_coll_increase, debt_change, is_debt_increase,
                );
            self._adjust_trove(trove_manager_cached, trove_id, ref trove_change, max_upfront_fee);
        }

        fn adjust_zombie_trove(
            ref self: ContractState,
            trove_id: u256,
            coll_change: u256,
            is_coll_increase: bool,
            debt_change: u256,
            is_debt_increase: bool,
            upper_hint: u256,
            lower_hint: u256,
            max_upfront_fee: u256,
        ) {
            let trove_manager_cached = self.trove_manager.read();
            InternalTrait::_require_trove_is_zombie(trove_manager_cached, trove_id);

            let mut trove_change: TroveChange = Default::default();
            self
                ._init_trove_change(
                    ref trove_change, coll_change, is_coll_increase, debt_change, is_debt_increase,
                );
            self._adjust_trove(trove_manager_cached, trove_id, ref trove_change, max_upfront_fee);

            let trove_manager_contract = ITroveManagerDispatcher {
                contract_address: self.trove_manager.read(),
            };
            trove_manager_contract.set_trove_status_to_active(trove_id);

            let batch_manager = self.interest_batch_manager_of.read(trove_id);
            let mut batch_annual_interest_rate = 0;
            if batch_manager != Default::default() {
                let batch = trove_manager_contract.get_latest_batch_data(batch_manager);
                batch_annual_interest_rate = batch.annual_interest_rate;
            }

            let trove_manager_contract = ITroveManagerDispatcher {
                contract_address: trove_manager_cached,
            };

            self
                ._re_insert_into_sorted_troves(
                    trove_id,
                    trove_manager_contract.get_trove_annual_interest_rate(trove_id),
                    upper_hint,
                    lower_hint,
                    batch_manager,
                    batch_annual_interest_rate,
                );
        }

        fn adjust_trove_interest_rate(
            ref self: ContractState,
            trove_id: u256,
            new_annual_interest_rate: u256,
            upper_hint: u256,
            lower_hint: u256,
            max_upfront_fee: u256,
        ) {
            self._require_is_not_shutdown();

            let trove_manager_cached = ITroveManagerDispatcher {
                contract_address: self.trove_manager.read(),
            };

            InternalTrait::_require_valid_annual_interest_rate(new_annual_interest_rate);
            self._require_is_not_in_batch(trove_id);
            self._require_sender_is_owner_or_interest_manager(trove_id);
            InternalTrait::_require_trove_is_active(
                trove_manager_cached.contract_address, trove_id,
            );

            let trove = trove_manager_cached.get_latest_trove_data(trove_id);
            self
                ._require_valid_delegate_adjustment(
                    trove_id, trove.last_interest_rate_adj_time, new_annual_interest_rate,
                );
            InternalTrait::_require_annual_interest_rate_is_new(
                trove.annual_interest_rate, new_annual_interest_rate,
            );

            let mut new_debt = trove.entire_debt;

            let mut trove_change: TroveChange = Default::default();
            trove_change.applied_redist_bit_usd_debt_gain = trove.redist_bit_usd_debt_gain;
            trove_change.applied_redist_coll_gain = trove.redist_coll_gain;
            trove_change.new_weighted_recorded_debt = new_debt * new_annual_interest_rate;
            trove_change.old_weighted_recorded_debt = trove.weighted_recorded_debt;

            // Apply upfront fee on premature adjustments. It checks the resulting ICR
            if get_block_timestamp() < (trove.last_interest_rate_adj_time.try_into().unwrap()
                + INTEREST_RATE_ADJ_COOLDOWN) {
                new_debt = self
                    ._apply_upfront_fee(
                        trove.entire_coll, new_debt, ref trove_change, max_upfront_fee, false,
                    );
            }

            // Recalculate new_weighted_recorded_debt, now taking into account the upfront fee
            trove_change.new_weighted_recorded_debt = new_debt * new_annual_interest_rate;

            let active_pool = IActivePoolDispatcher {
                contract_address: self.liquity_base.active_pool.read(),
            };
            active_pool
                .mint_agg_interest_and_account_for_trove_change(trove_change, Default::default());

            let sorted_troves = ISortedTrovesDispatcher {
                contract_address: self.sorted_troves.read(),
            };

            sorted_troves.re_insert(trove_id, new_annual_interest_rate, upper_hint, lower_hint);
            trove_manager_cached
                .on_adjust_trove_interest_rate(
                    trove_id, trove.entire_coll, new_debt, new_annual_interest_rate, trove_change,
                );
        }

        fn close_trove(ref self: ContractState, trove_id: u256) {
            let trove_manager_cached = ITroveManagerDispatcher {
                contract_address: self.trove_manager.read(),
            };

            let active_pool_cached = IActivePoolDispatcher {
                contract_address: self.liquity_base.active_pool.read(),
            };

            let bitusd_token_cached = IBitUSDDispatcher {
                contract_address: self.bitusd_token.read(),
            };

            // --- Checks ---

            let owner = get_caller_address(); // TODO troveNFT.ownerOf(trove_id)
            let receiver =
                get_caller_address(); // TODO: require_sender_is_owner_or_remove_manager_and_get_receiver(trove_id, owner)
            InternalTrait::_require_trove_is_open(trove_manager_cached.contract_address, trove_id);

            let trove = trove_manager_cached.get_latest_trove_data(trove_id);

            // The borrower must repay their entire debt including accrues interest, batch fee and
            // redist. gains
            InternalTrait::_require_sufficient_bitusd_balance(
                bitusd_token_cached.contract_address, get_caller_address(), trove.entire_debt,
            );

            let mut trove_change: TroveChange = Default::default();

            trove_change.applied_redist_bit_usd_debt_gain = trove.redist_bit_usd_debt_gain;
            trove_change.applied_redist_coll_gain = trove.redist_coll_gain;
            trove_change.coll_decrease = trove.entire_coll;
            trove_change.debt_decrease = trove.entire_debt;

            let batch_manager = self.interest_batch_manager_of.read(trove_id);
            let mut batch: LatestBatchData = Default::default();
            if batch_manager != Default::default() {
                batch = trove_manager_cached.get_latest_batch_data(batch_manager);
                let batch_future_debt = batch.entire_debt_without_redistribution
                    - (trove.entire_debt - trove.redist_bit_usd_debt_gain);
                trove_change.batch_accrued_management_fee = batch.accrued_management_fee;
                trove_change.old_weighted_recorded_debt = batch.weighted_recorded_debt;
                trove_change.new_weighted_recorded_debt = batch_future_debt
                    * batch.annual_interest_rate;
                trove_change
                    .old_weighted_recorded_batch_management_fee = batch
                    .weighted_recorded_batch_management_fee;
                trove_change.new_weighted_recorded_batch_management_fee = batch_future_debt
                    * batch.annual_management_fee;
            } else {
                trove_change.old_weighted_recorded_debt = trove.weighted_recorded_debt;
                // trove_change.new_weighted_recorded_debt = 0; // TODO: this is commented in the
            // code, check git blame?
            }

            let price_feed = IPriceFeedMockDispatcher {
                contract_address: self.liquity_base.price_feed.read(),
            };
            let (price, _) = price_feed.fetch_price();
            let new_tcr = self._get_new_TCR_from_trove_change(trove_change, price);
            if !self.has_been_shutdown.read() {
                self._require_new_tcr_is_above_ccr(new_tcr);
            }

            trove_manager_cached
                .on_close_trove(
                    trove_id,
                    trove_change,
                    batch_manager,
                    batch.entire_coll_without_redistribution,
                    batch.entire_debt_without_redistribution,
                );

            // If trove is in batch
            if batch_manager != Default::default() {
                // Unlink here in BorrowerOperations
                self.interest_batch_manager_of.write(trove_id, Default::default());
            }
            active_pool_cached
                .mint_agg_interest_and_account_for_trove_change(trove_change, batch_manager);

            // Return ETH gas compensation // TODO change this
            let weth = IERC20Dispatcher { contract_address: self.eth.read() };
            weth.transfer_from(self.gas_pool_address.read(), receiver, ETH_GAS_COMPENSATION);
            // Burn the remainder of the Trove's entire debt from the user
            bitusd_token_cached.burn(get_caller_address(), trove.entire_debt);

            // Sned the collateral back to the user
            active_pool_cached.send_coll(receiver, trove.entire_coll);

            self._wipe_trove_mappings(trove_id);
        }

        fn apply_pending_debt(
            ref self: ContractState, trove_id: u256, lower_hint: u256, upper_hint: u256,
        ) {
            self._require_is_not_shutdown();

            let trove_manager_cached = ITroveManagerDispatcher {
                contract_address: self.trove_manager.read(),
            };

            InternalTrait::_require_trove_is_open(trove_manager_cached.contract_address, trove_id);

            let trove = trove_manager_cached.get_latest_trove_data(trove_id);
            InternalTrait::_require_non_zero_debt(trove.entire_debt);

            let mut change: TroveChange = Default::default();
            change.applied_redist_bit_usd_debt_gain = trove.redist_bit_usd_debt_gain;
            change.applied_redist_coll_gain = trove.redist_coll_gain;

            let batch_manager = self.interest_batch_manager_of.read(trove_id);
            let mut batch: LatestBatchData = Default::default();

            if batch_manager == Default::default() {
                change.old_weighted_recorded_debt = trove.weighted_recorded_debt;
                change.new_weighted_recorded_debt = trove.entire_debt * trove.annual_interest_rate;
            } else {
                batch = trove_manager_cached.get_latest_batch_data(batch_manager);
                change.batch_accrued_management_fee = batch.accrued_management_fee;
                change.old_weighted_recorded_debt = batch.weighted_recorded_debt;
                change
                    .new_weighted_recorded_debt =
                        (batch.entire_debt_without_redistribution + trove.redist_bit_usd_debt_gain)
                    * batch.annual_interest_rate;
                change
                    .old_weighted_recorded_batch_management_fee = batch
                    .weighted_recorded_batch_management_fee;
                change
                    .new_weighted_recorded_batch_management_fee =
                        (batch.entire_debt_without_redistribution + trove.redist_bit_usd_debt_gain)
                    * batch.annual_management_fee;
            }

            trove_manager_cached
                .on_apply_trove_interest(
                    trove_id,
                    trove.entire_coll,
                    trove.entire_debt,
                    batch_manager,
                    batch.entire_coll_without_redistribution,
                    batch.entire_debt_without_redistribution,
                    change,
                );

            let active_pool = IActivePoolDispatcher {
                contract_address: self.liquity_base.active_pool.read(),
            };
            active_pool.mint_agg_interest_and_account_for_trove_change(change, batch_manager);

            // If the trove was zombie, and now it's not anymore, put it back on the list
            if InternalTrait::_check_trove_is_zombie(
                trove_manager_cached.contract_address, trove_id,
            )
                && (trove.entire_debt >= MIN_DEBT) {
                trove_manager_cached.set_trove_status_to_active(trove_id);
                self
                    ._re_insert_into_sorted_troves(
                        trove_id,
                        trove.annual_interest_rate,
                        upper_hint,
                        lower_hint,
                        batch_manager,
                        batch.annual_interest_rate,
                    )
            }
        }

        fn get_interest_individual_delegate_of(
            ref self: ContractState, trove_id: u256,
        ) -> InterestIndividualDelegate {
            self.interest_individual_delegate_of.read(trove_id)
        }

        fn set_interest_individual_delegate(
            ref self: ContractState,
            trove_id: u256,
            delegate: ContractAddress,
            min_interest_rate: u128,
            max_interest_rate: u128,
            new_annual_interest_rate: u256,
            upper_hint: u256,
            lower_hint: u256,
            max_upfront_fee: u256,
            min_interest_rate_change_period: u256,
        ) {
            self._require_is_not_shutdown();
            InternalTrait::_require_trove_is_active(self.trove_manager.read(), trove_id);
            // _require_caller_is_borrower(trove_id);// TODO add remove manager
            InternalTrait::_require_valid_annual_interest_rate(min_interest_rate.into());
            InternalTrait::_require_valid_annual_interest_rate(max_interest_rate.into());
            // With the check below, it could only be ==
            InternalTrait::_require_ordered_range(min_interest_rate, max_interest_rate);

            self
                .interest_individual_delegate_of
                .write(
                    trove_id,
                    InterestIndividualDelegate {
                        account: delegate,
                        min_interest_rate,
                        max_interest_rate,
                        min_interest_rate_change_period,
                    },
                );

            // Can't have both individual delegation and batch manager
            if self.interest_batch_manager_of.read(trove_id) != Default::default() {
                // Not needed, implicitly checked in remove_from_batch
                // _require_valid_annual_interest_rate(new_annual_interest_rate);
                self
                    .remove_from_batch(
                        trove_id, new_annual_interest_rate, upper_hint, lower_hint, max_upfront_fee,
                    );
            }
        }

        fn remove_from_batch(
            ref self: ContractState,
            trove_id: u256,
            new_annual_interest_rate: u256,
            upper_hint: u256,
            lower_hint: u256,
            max_upfront_fee: u256,
        ) {
            self
                ._remove_from_batch(
                    trove_id,
                    new_annual_interest_rate,
                    upper_hint,
                    lower_hint,
                    max_upfront_fee,
                    false,
                );
        }

        fn switch_batch_manager(
            ref self: ContractState,
            trove_id: u256,
            remove_upper_hint: u256,
            remove_lower_hint: u256,
            new_batch_manager: ContractAddress,
            add_upper_hint: u256,
            add_lower_hint: u256,
            max_upfront_fee: u256,
        ) {
            let old_batch_manager = self._require_is_in_batch(trove_id);

            InternalTrait::_require_new_interest_batch_manager(
                old_batch_manager, new_batch_manager,
            );

            let trove_manager = ITroveManagerDispatcher {
                contract_address: self.trove_manager.read(),
            };
            let old_batch = trove_manager.get_latest_batch_data(old_batch_manager);

            Self::remove_from_batch(
                ref self,
                trove_id,
                old_batch.annual_interest_rate,
                remove_upper_hint,
                remove_lower_hint,
                0,
            );
            Self::set_interest_batch_manager(
                ref self,
                trove_id,
                new_batch_manager,
                add_upper_hint,
                add_lower_hint,
                max_upfront_fee,
            );
        }

        fn set_interest_batch_manager(
            ref self: ContractState,
            trove_id: u256,
            new_batch_manager: ContractAddress,
            upper_hint: u256,
            lower_hint: u256,
            max_upfront_fee: u256,
        ) {
            self._require_is_not_shutdown();

            let mut vars: LocalVariables_setInterestBatchManager = Default::default();
            vars.trove_manager = self.trove_manager.read();
            vars.active_pool = self.liquity_base.active_pool.read();
            vars.sorted_troves = self.sorted_troves.read();

            InternalTrait::_require_trove_is_active(vars.trove_manager, trove_id);
            // _requireCallerIsBorrower(_troveId); TODO addremove
            self._require_valid_interest_batch_manager(new_batch_manager);
            self._require_is_not_in_batch(trove_id);

            self.interest_batch_manager_of.write(trove_id, new_batch_manager);
            // Can’t have both individual delegation and batch manager
            if self.interest_individual_delegate_of.read(trove_id).account != Default::default() {
                self.interest_individual_delegate_of.write(trove_id, Default::default());
            }

            let trove_manager = ITroveManagerDispatcher { contract_address: vars.trove_manager };
            vars.trove = trove_manager.get_latest_trove_data(trove_id);
            vars.new_batch = trove_manager.get_latest_batch_data(new_batch_manager);

            let mut new_batch_trove_change: TroveChange = Default::default();
            new_batch_trove_change
                .applied_redist_bit_usd_debt_gain = vars
                .trove
                .redist_bit_usd_debt_gain;
            new_batch_trove_change.applied_redist_coll_gain = vars.trove.redist_coll_gain;
            new_batch_trove_change
                .batch_accrued_management_fee = vars
                .new_batch
                .accrued_management_fee;
            new_batch_trove_change
                .old_weighted_recorded_debt = vars
                .new_batch
                .weighted_recorded_debt
                + vars.trove.weighted_recorded_debt;
            new_batch_trove_change
                .new_weighted_recorded_debt =
                    (vars.new_batch.entire_debt_without_redistribution + vars.trove.entire_debt)
                * vars.new_batch.annual_interest_rate;

            // An upfront fee is always charged upon joining a batch to ensure that borrowers can
            // not game the fee logic and gain free interest rate updates (e.g. if they also manage
            // the batch they joined)
            // It checks the resulting ICR
            vars
                .trove
                .entire_debt = self
                ._apply_upfront_fee(
                    vars.trove.entire_coll,
                    vars.trove.entire_debt,
                    ref new_batch_trove_change,
                    max_upfront_fee,
                    true,
                );

            // Recalculate newWeightedRecordedDebt, now taking into account the upfront fee
            new_batch_trove_change
                .new_weighted_recorded_debt =
                    (vars.new_batch.entire_debt_without_redistribution + vars.trove.entire_debt)
                * vars.new_batch.annual_interest_rate;

            // Add batch fees
            new_batch_trove_change
                .old_weighted_recorded_batch_management_fee = vars
                .new_batch
                .weighted_recorded_batch_management_fee;
            new_batch_trove_change
                .new_weighted_recorded_batch_management_fee =
                    (vars.new_batch.entire_debt_without_redistribution + vars.trove.entire_debt)
                * vars.new_batch.annual_management_fee;

            let active_pool = IActivePoolDispatcher { contract_address: vars.active_pool };
            active_pool
                .mint_agg_interest_and_account_for_trove_change(
                    new_batch_trove_change, new_batch_manager,
                );

            let trove_manager = ITroveManagerDispatcher { contract_address: vars.trove_manager };
            trove_manager
                .on_set_interest_batch_manager(
                    OnSetInterestBatchManagerParams {
                        trove_id,
                        trove_coll: vars.trove.entire_coll,
                        trove_debt: vars.trove.entire_debt,
                        trove_change: new_batch_trove_change,
                        new_batch_address: new_batch_manager,
                        new_batch_coll: vars.new_batch.entire_coll_without_redistribution,
                        new_batch_debt: vars.new_batch.entire_debt_without_redistribution,
                    },
                );

            let sorted_troves = ISortedTrovesDispatcher { contract_address: vars.sorted_troves };
            sorted_troves.remove(trove_id);
            sorted_troves
                .insert_into_batch(
                    trove_id,
                    new_batch_manager,
                    vars.new_batch.annual_interest_rate,
                    upper_hint,
                    lower_hint,
                ); // TODO BatchId.wrap
        }
    }

    ////////////////////////////////////////////////////////////////
    //                     INTERNAL FUNCTIONS                     //
    ////////////////////////////////////////////////////////////////
    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn _require_caller_is_trove_manager(self: @ContractState) {
            assert(
                get_caller_address() == self.trove_manager.read(), 'BO: Caller not trove manager',
            );
        }

        fn _require_valid_interest_batch_manager(
            self: @ContractState, interest_batch_manager_address: ContractAddress,
        ) {
            assert(
                self
                    .interest_batch_managers
                    .read(interest_batch_manager_address)
                    .max_interest_rate != 0,
                'BO: Invalid interest BM',
            );
        }

        fn _require_new_interest_batch_manager(
            old_batch_manager_address: ContractAddress, new_batch_manager_address: ContractAddress,
        ) {
            assert(old_batch_manager_address != new_batch_manager_address, 'BO: BM not new');
        }
        fn _require_is_in_batch(self: @ContractState, trove_id: u256) -> ContractAddress {
            let batch_manager = self.interest_batch_manager_of.read(trove_id);
            assert(batch_manager != Default::default(), 'BO: Trove is not in batch');

            batch_manager
        }

        fn _require_ordered_range(min_interest_rate: u128, max_interest_rate: u128) {
            assert(min_interest_rate < max_interest_rate, 'BO: Interest rate not ordered');
        }

        fn _require_non_zero_debt(debt: u256) {
            assert(debt != 0, 'BO: Debt is 0');
        }

        fn _require_annual_interest_rate_is_new(
            old_annual_interest_rate: u256, new_annual_interest_rate: u256,
        ) {
            assert(
                old_annual_interest_rate != new_annual_interest_rate, 'BO: Interest rate not new',
            );
        }

        fn _require_valid_delegate_adjustment(
            self: @ContractState,
            trove_id: u256,
            last_interest_rate_adj_time: u256,
            annual_interest_rate: u256,
        ) {
            let individual_delegate = self.interest_individual_delegate_of.read(trove_id);
            // We have previously checked that sender is either owner or delegate
            // If it's owner, this restriction doesn't apply
            if individual_delegate.account == get_caller_address() {
                Self::_require_interest_rate_in_range(
                    annual_interest_rate.try_into().unwrap(), // TODO check
                    individual_delegate.min_interest_rate,
                    individual_delegate.max_interest_rate,
                );
                Self::_require_delegate_interest_rate_change_period_passed(
                    last_interest_rate_adj_time,
                    individual_delegate.min_interest_rate_change_period,
                )
            }
        }

        fn _require_interest_rate_in_range(
            annual_interest_rate: u128, min_interest_rate: u128, max_interest_rate: u128,
        ) {
            let in_range = min_interest_rate <= annual_interest_rate
                && annual_interest_rate <= max_interest_rate;
            assert(in_range, 'BO: Interest rate out of range');
        }

        fn _require_delegate_interest_rate_change_period_passed(
            last_interest_rate_adj_time: u256, min_interest_rate_change_period: u256,
        ) {
            let passed = get_block_timestamp()
                .into() >= (last_interest_rate_adj_time + min_interest_rate_change_period);
            assert(passed, 'BO: Not enough time has passed');
        }

        fn _require_is_not_in_batch(self: @ContractState, trove_id: u256) {
            assert(
                self.interest_batch_manager_of.read(trove_id) == Default::default(),
                'BO: Trove in batch',
            );
        }

        fn _require_sender_is_owner_or_interest_manager(self: @ContractState, trove_id: u256) {
            // TODO: add removemanager troveNFT
            let owner = get_caller_address();
            let msg_sender = get_caller_address();
            let owner_or_interest_manager = msg_sender == owner
                || msg_sender == self.interest_individual_delegate_of.read(trove_id).account;
            assert(owner_or_interest_manager, 'BO: Not owner or interest manag');
        }

        fn _require_valid_annual_interest_rate(annual_interest_rate: u256) {
            assert(annual_interest_rate >= MIN_ANNUAL_INTEREST_RATE, 'BO: Interest Rate too low');
            assert(annual_interest_rate <= MAX_ANNUAL_INTEREST_RATE, 'BO: Interest Rate too high');
        }

        fn _require_is_not_shutdown(self: @ContractState) {
            assert(!self.has_been_shutdown.read(), 'BO: System is shutdown');
        }

        fn _require_oracles_live(self: @ContractState) -> u256 {
            let price_feed = IPriceFeedMockDispatcher {
                contract_address: self.liquity_base.price_feed.read(),
            };
            let (price, new_oracle_failure_detected) = price_feed.fetch_price();
            assert(!new_oracle_failure_detected, 'BO: New Oracle Failure Detected');
            return price;
        }

        fn _require_caller_is_price_feed(self: @ContractState) {
            assert(
                get_caller_address() == self.liquity_base.price_feed.read(),
                'BO: Caller not price feed',
            );
        }

        fn _require_trove_does_not_exist(trove_manager_address: ContractAddress, trove_id: u256) {
            let trove_manager = ITroveManagerDispatcher { contract_address: trove_manager_address };
            let status = trove_manager.get_trove_status(trove_id);
            assert(status == Status::NonExistent, 'BO: Trove exists');
        }

        fn _require_user_accepts_upfront_fee(fee: u256, max_fee: u256) {
            assert(fee <= max_fee, 'BO: Upfront fee too high');
        }

        fn _require_at_leaset_min_debt(debt: u256) {
            assert(debt >= MIN_DEBT, 'BO: Debt is less than MIN_DEBT');
        }

        fn _require_icr_is_above_mcr(self: @ContractState, new_icr: u256) {
            assert(new_icr >= self.mcr.read(), 'BO: ICR is below MCR');
        }

        fn _require_icr_is_above_mcr_plus_bcr(self: @ContractState, new_icr: u256) {
            assert(new_icr >= self.mcr.read() + self.bcr.read(), 'BO: ICR is below MCR + BCR');
        }

        fn _require_new_tcr_is_above_ccr(self: @ContractState, new_tcr: u256) {
            assert(new_tcr >= self.ccr.read(), 'BO: TCR is below CCR');
        }

        fn _require_no_borrowing_unless_new_tcr_is_above_ccr(
            self: @ContractState, debt_increase: u256, new_tcr: u256,
        ) {
            assert(debt_increase == 0 || new_tcr >= self.ccr.read(), 'BO: TCR is below CCR');
        }

        fn _require_debt_repayment_ge_coll_withdrawal(
            self: @ContractState, trove_change: TroveChange, price: u256,
        ) {
            assert(
                trove_change.debt_decrease
                    * DECIMAL_PRECISION >= trove_change.coll_decrease
                    * price,
                'BO: Repayment != coll withdraw',
            );
        }

        fn _require_trove_is_active(trove_manager: ContractAddress, trove_id: u256) {
            let trove_manager = ITroveManagerDispatcher { contract_address: trove_manager };
            let status = trove_manager.get_trove_status(trove_id);
            assert(status == Status::Active, 'BO: Trove is not active');
        }

        fn _require_trove_is_zombie(trove_manager_address: ContractAddress, trove_id: u256) {
            assert(
                Self::_check_trove_is_zombie(trove_manager_address, trove_id),
                'BO: Trove is not zombie',
            );
        }

        fn _check_trove_is_zombie(trove_manager_address: ContractAddress, trove_id: u256) -> bool {
            let trove_manager = ITroveManagerDispatcher { contract_address: trove_manager_address };
            let status = trove_manager.get_trove_status(trove_id);
            return status == Status::Zombie;
        }

        fn _check_below_critical_threshold(self: @ContractState, price: u256, ccr: u256) -> bool {
            let tcr = self.liquity_base._get_TCR(price);

            return tcr < ccr;
        }

        fn _require_trove_is_open(trove_manager_address: ContractAddress, trove_id: u256) {
            let trove_manager = ITroveManagerDispatcher { contract_address: trove_manager_address };
            let status = trove_manager.get_trove_status(trove_id);
            let is_open = (status == Status::Active || status == Status::Zombie);
            assert(is_open, 'BO: Trove is not open');
        }

        fn _require_sufficient_bitusd_balance(
            bitusd_token_address: ContractAddress, borrower: ContractAddress, debt_repayment: u256,
        ) {
            let bitusd_token = IERC20Dispatcher { contract_address: bitusd_token_address };
            assert(
                bitusd_token.balance_of(borrower) >= debt_repayment,
                'BO: Insufficient bitusd balance',
            );
        }

        fn _require_non_zero_adjustment(trove_change: TroveChange) {
            assert(
                trove_change.coll_increase != 0
                    || trove_change.coll_decrease != 0
                    || trove_change.debt_increase != 0
                    || trove_change.debt_decrease != 0,
                'BO: Zero adjustment',
            );
        }

        fn _require_valid_coll_withdrawal(current_coll: u256, coll_withdrawal: u256) {
            assert(coll_withdrawal <= current_coll, 'BO: Coll withdrawal too high');
        }

        fn _require_valid_adjustment_in_current_mode(
            self: @ContractState,
            trove_change: TroveChange,
            vars: LocalVariables_adjustTrove,
            is_trove_in_batch: bool,
        ) {
            // Below Critical Threshold, it is not permitted:
            // - Borrowing, unless it brings TCR up to CCR again
            // - Collateral withdrawal except accompanied by a debt repayment of at least the same
            // value In Normal Mode, ensure:
            // - The adjustment won't pull the TCR below CCR
            // In Both cases:
            // - The new ICR is above MCR, or MCR+BCR if a batched trove
            if is_trove_in_batch {
                self._require_icr_is_above_mcr_plus_bcr(vars.new_ICR);
            } else {
                self._require_icr_is_above_mcr(vars.new_ICR);
            }

            let new_tcr = self._get_new_TCR_from_trove_change(trove_change, vars.price);
            if vars.is_below_critical_threshold {
                self
                    ._require_no_borrowing_unless_new_tcr_is_above_ccr(
                        trove_change.debt_increase, new_tcr,
                    );
                self._require_debt_repayment_ge_coll_withdrawal(trove_change, vars.price);
            } else {
                // if Normal Mode
                self._require_new_tcr_is_above_ccr(new_tcr);
            }
        }

        fn _apply_shutdown(ref self: ContractState) {
            let active_pool = IActivePoolDispatcher {
                contract_address: self.liquity_base.active_pool.read(),
            };
            active_pool.mint_agg_interest();

            self.has_been_shutdown.write(true);

            let trove_manager = ITroveManagerDispatcher {
                contract_address: self.trove_manager.read(),
            };
            trove_manager.shutdown();
        }

        fn _open_trove(
            ref self: ContractState,
            owner: ContractAddress,
            owner_index: u256,
            coll_amount: u256,
            bitusd_amount: u256,
            annual_interest_rate: u256,
            interest_batch_manager: ContractAddress,
            batch_entire_debt: u256,
            batch_management_annual_fee: u256,
            max_upfront_fee: u256,
            add_manager: ContractAddress,
            remove_manager: ContractAddress,
            receiver: ContractAddress,
            ref change: TroveChange,
        ) -> u256 {
            self._require_is_not_shutdown();

            let msg_sender = get_caller_address();

            // TODO
            // stack too deep not allowing to reuse troveManager from outer functions
            let mut vars = LocalVariables_openTrove {
                active_pool: self.liquity_base.active_pool.read(),
                bitusd_token: self.bitusd_token.read(),
                trove_manager: self.trove_manager.read(),
                ..Default::default(),
            };

            vars.price = self._require_oracles_live();

            // Checks TODO better to use a struct maybe
            let mut hash_state = PoseidonTrait::new();
            hash_state = hash_state.update_with(msg_sender);
            hash_state = hash_state.update_with(owner);
            hash_state = hash_state.update_with(owner_index);
            let hash_felt = hash_state.finalize();
            vars.trove_id = hash_felt.into();

            Self::_require_trove_does_not_exist(vars.trove_manager, vars.trove_id);

            change.coll_increase = coll_amount;
            change.debt_increase = bitusd_amount;

            // For simplicity, we ignore the fee when calculating the approx. interest rate
            change.new_weighted_recorded_debt = (batch_entire_debt + change.debt_increase)
                * annual_interest_rate;

            let active_pool = IActivePoolDispatcher { contract_address: vars.active_pool };
            vars
                .avg_interest_rate = active_pool
                .get_new_approx_avg_interest_rate_from_trove_change(change);
            change
                .upfront_fee =
                    Self::_calc_upfront_fee(change.debt_increase, vars.avg_interest_rate);
            Self::_require_user_accepts_upfront_fee(change.upfront_fee, max_upfront_fee);

            vars.entire_debt = change.debt_increase + change.upfront_fee;
            Self::_require_at_leaset_min_debt(vars.entire_debt);

            vars.ICR = math_lib::compute_cr(coll_amount, vars.entire_debt, vars.price);

            // Recalculate new_weighted_recorded_debt, now taking into account the upfront fee, and
            // the batch fee if needed
            if interest_batch_manager == Default::default() {
                change.new_weighted_recorded_debt = vars.entire_debt * annual_interest_rate;

                // ICR is based on the requested bitUSD amount + upfront fee
                self._require_icr_is_above_mcr(vars.ICR);
            } else {
                // old values have been set outside, before calling this function
                change.new_weighted_recorded_debt = (batch_entire_debt + vars.entire_debt)
                    * annual_interest_rate;
                change
                    .new_weighted_recorded_batch_management_fee =
                        (batch_entire_debt + vars.entire_debt)
                    * batch_management_annual_fee;

                // ICR is based on the requested bitUSD amount + upfront fee.
                // Troves in a batch have a strong requirement (MCR + BCR)
                self._require_icr_is_above_mcr_plus_bcr(vars.ICR);
            }

            vars.new_TCR = self._get_new_TCR_from_trove_change(change, vars.price);
            self._require_new_tcr_is_above_ccr(vars.new_TCR);

            // --- Effects & interactions ---

            // Set add/remove managers
            // TODO _setAddManager(vars.troveId, _addManager);
            //TODO _setRemoveManagerAndReceiver(vars.troveId, _removeManager, _receiver);

            active_pool
                .mint_agg_interest_and_account_for_trove_change(change, interest_batch_manager);

            // Pull coll tokens from sender and move them to the Active Pool
            self._pull_coll_and_send_to_active_pool(active_pool, coll_amount);

            // Mint the requested bitusd_amount to the borrowed and mint the gas comp to the Gas
            // Pool
            let bitusd_token = IBitUSDDispatcher { contract_address: vars.bitusd_token };
            bitusd_token.mint(msg_sender, bitusd_amount);

            // TODO: change WETH
            let weth = IERC20Dispatcher { contract_address: self.eth.read() };
            weth.transfer_from(msg_sender, self.gas_pool_address.read(), ETH_GAS_COMPENSATION);

            return vars.trove_id;
        }

        fn _pull_coll_and_send_to_active_pool(
            self: @ContractState, active_pool: IActivePoolDispatcher, amount: u256,
        ) {
            let coll_token = IERC20Dispatcher { contract_address: self.coll_token.read() };
            // Send Coll tokens from sender to active pool
            coll_token.transfer_from(get_caller_address(), active_pool.contract_address, amount);
            // Make sure Active Pool accountancy is right
            active_pool.account_for_received_coll(amount);
        }

        // --- Helper functions ----
        fn _re_insert_into_sorted_troves(
            self: @ContractState,
            trove_id: u256,
            trove_annual_interest_rate: u256,
            upper_hint: u256,
            lower_hint: u256,
            batch_manager: ContractAddress,
            batch_annual_interest_rate: u256,
        ) {
            let sorted_troves = ISortedTrovesDispatcher {
                contract_address: self.sorted_troves.read(),
            };
            // If it was in a batch, we need to put it back, otherwise we insert it normally
            if batch_manager != Default::default() {
                sorted_troves.insert(trove_id, trove_annual_interest_rate, upper_hint, lower_hint);
            } else {
                sorted_troves
                    .insert_into_batch(
                        trove_id,
                        batch_manager, // TODO: BatchId.wrap(batch_manager),
                        batch_annual_interest_rate,
                        upper_hint,
                        lower_hint,
                    );
            }
        }

        // This function mints the BitUSD corresponding to the borrower's chosen debt increase
        // (it does not mint the accrued interest)
        fn _move_tokens_from_adjustment(
            self: @ContractState,
            withdrawal_receiver: ContractAddress,
            trove_change: TroveChange,
            bitusd_token_address: ContractAddress,
            active_pool: IActivePoolDispatcher,
        ) {
            let bitusd_token = IBitUSDDispatcher { contract_address: bitusd_token_address };
            if (trove_change.debt_increase > 0) {
                bitusd_token.mint(withdrawal_receiver, trove_change.debt_increase);
            } else if (trove_change.debt_decrease > 0) {
                bitusd_token.burn(get_caller_address(), trove_change.debt_decrease);
            }

            if trove_change.coll_increase > 0 {
                // Pull coll tokens from sender and move them to the Active Pool
                self._pull_coll_and_send_to_active_pool(active_pool, trove_change.coll_increase);
            } else if trove_change.coll_decrease > 0 {
                // Pull Coll from Active Pool and decrease its recorded Coll balance
                active_pool.send_coll(withdrawal_receiver, trove_change.coll_decrease);
            }
        }

        fn _init_trove_change(
            ref self: ContractState,
            ref trove_change: TroveChange,
            coll_change: u256,
            is_coll_increase: bool,
            debt_change: u256,
            is_debt_increase: bool,
        ) {
            if is_coll_increase {
                trove_change.coll_increase = coll_change;
            } else {
                trove_change.coll_decrease = coll_change;
            }

            if is_debt_increase {
                trove_change.debt_increase = debt_change;
            } else {
                trove_change.debt_decrease = debt_change;
            }
        }

        // _adjust_trove(): Alongside a debt change, this function can perform either a collateral
        // top-up or a collateral withdrawal.
        fn _adjust_trove(
            ref self: ContractState,
            trove_manager_address: ContractAddress,
            trove_id: u256,
            ref trove_change: TroveChange,
            max_upfront_fee: u256,
        ) {
            self._require_is_not_shutdown();

            let trove_manager = ITroveManagerDispatcher { contract_address: trove_manager_address };

            let price = self._require_oracles_live();
            let mut vars = LocalVariables_adjustTrove {
                active_pool: self.liquity_base.active_pool.read(),
                bitusd_token: self.bitusd_token.read(),
                price,
                is_below_critical_threshold: self
                    ._check_below_critical_threshold(price, self.ccr.read()),
                ..Default::default(),
            };

            // --- Checks ---

            Self::_require_trove_is_open(trove_manager.contract_address, trove_id);

            let owner = get_caller_address(); // TODO replace by below
            // let owner = trove_nft.read().ownerOf(trove_id) // TODO
            let mut receiver =
                owner; // If it's a withdrawal, and remove manager privilege is set, a different receiver can be defined

            if (trove_change.coll_decrease > 0 || trove_change.debt_increase > 0) {
                // TODO remove manager
                receiver = get_caller_address(); // TODO wrong
                // receiver = self
            // .add_manager
            // ._require_sender_is_owner_or_remove_manager_and_get_receiver(trove_id, owner);
            } else { // RemoveManager assumes AddManager, so if the formet is set, there's no need to
            // check the latter
            // TODO
            // self.add_manager._require_sender_is_owner_or_add_manager(trove_id, owner);
            // No need to check the type of trove change for two reasons:
            // - If the check above fails, it means sender is not owner, nor AddManager, nor
            // RemoveManager.
            //   An independent 3rd party should not be allowed here.
            // - If it's not collIncrease or debtDecrease, _requireNonZeroAdjustment would
            // revert
            }

            vars.trove = trove_manager.get_latest_trove_data(trove_id);

            // When the adjustment is a debt repayment, check it's a valid amount and that the
            // caller has enough bitusd
            if trove_change.debt_decrease > 0 {
                let max_repayment = if vars.trove.entire_debt > MIN_DEBT {
                    vars.trove.entire_debt - MIN_DEBT
                } else {
                    0
                };

                if trove_change.debt_decrease > max_repayment {
                    trove_change.debt_decrease = max_repayment;
                }

                Self::_require_sufficient_bitusd_balance(
                    vars.bitusd_token, get_caller_address(), trove_change.debt_decrease,
                );
            }

            Self::_require_non_zero_adjustment(trove_change);

            // When the adjustment is a collateral withdrawal, check that it's no more than the
            // Trove's entire collateral
            if (trove_change.coll_decrease > 0) {
                Self::_require_valid_coll_withdrawal(
                    vars.trove.entire_coll, trove_change.coll_decrease,
                );
            }

            vars.new_coll = vars.trove.entire_coll
                + trove_change.coll_increase
                - trove_change.coll_decrease;
            vars.new_debt = vars.trove.entire_debt
                + trove_change.debt_increase
                - trove_change.debt_decrease;

            let batch_manager = self.interest_batch_manager_of.read(trove_id);
            let is_trove_in_batch = batch_manager != Default::default();

            let mut batch: LatestBatchData = Default::default();
            let mut batch_future_debt: u256 = 0;

            if is_trove_in_batch {
                batch = trove_manager.get_latest_batch_data(batch_manager);

                batch_future_debt = batch.entire_debt_without_redistribution
                    + vars.trove.redist_bit_usd_debt_gain
                    + trove_change.debt_increase
                    - trove_change.debt_decrease;

                trove_change.applied_redist_bit_usd_debt_gain = vars.trove.redist_bit_usd_debt_gain;
                trove_change.applied_redist_coll_gain = vars.trove.redist_coll_gain;
                trove_change.batch_accrued_management_fee = batch.accrued_management_fee;
                trove_change.old_weighted_recorded_debt = batch.weighted_recorded_debt;
                trove_change.new_weighted_recorded_debt = batch_future_debt
                    * batch.annual_interest_rate;
                trove_change
                    .old_weighted_recorded_batch_management_fee = batch
                    .weighted_recorded_batch_management_fee;
                trove_change.new_weighted_recorded_batch_management_fee = batch_future_debt
                    * batch.annual_management_fee;
            } else {
                trove_change.applied_redist_bit_usd_debt_gain = vars.trove.redist_bit_usd_debt_gain;
                trove_change.applied_redist_coll_gain = vars.trove.redist_coll_gain;
                trove_change.old_weighted_recorded_debt = vars.trove.weighted_recorded_debt;
                trove_change.new_weighted_recorded_debt = vars.new_debt
                    * vars.trove.annual_interest_rate;
            }

            // Pay an upfront fee on debt increases
            if trove_change.debt_increase > 0 {
                let active_pool = IActivePoolDispatcher { contract_address: vars.active_pool };

                let avg_interest_rate = active_pool
                    .get_new_approx_avg_interest_rate_from_trove_change(trove_change);
                trove_change
                    .upfront_fee =
                        Self::_calc_upfront_fee(trove_change.debt_increase, avg_interest_rate);
                Self::_require_user_accepts_upfront_fee(trove_change.upfront_fee, max_upfront_fee);

                vars.new_debt += trove_change.upfront_fee;
                if (is_trove_in_batch) {
                    batch_future_debt += trove_change.upfront_fee;
                    // Recalculate new_weighted_recorded_debt, now taking into acount the upfront
                    // fee
                    trove_change.new_weighted_recorded_debt = batch_future_debt
                        * batch.annual_interest_rate;
                    trove_change.new_weighted_recorded_batch_management_fee = batch_future_debt
                        * batch.annual_management_fee;
                } else {
                    trove_change.new_weighted_recorded_debt = vars.new_debt
                        * vars.trove.annual_interest_rate;
                }
            }

            // Make sure the Trove doesn't end up zombie
            // Now the max repayment is capped to stay above MIN_DEBT, so this only applies to
            // adjustZombieTrove
            Self::_require_at_leaset_min_debt(vars.new_debt);

            vars.new_ICR = math_lib::compute_cr(vars.new_coll, vars.new_debt, vars.price);

            // Check the adjustment satisfies all conditions for the current system mode
            self._require_valid_adjustment_in_current_mode(trove_change, vars, is_trove_in_batch);

            // --- Effects and interactions ---
            if (is_trove_in_batch) {
                trove_manager
                    .on_adjust_trove_inside_batch(
                        trove_id,
                        vars.new_coll,
                        vars.new_debt,
                        trove_change,
                        batch_manager,
                        batch.entire_coll_without_redistribution,
                        batch.entire_debt_without_redistribution,
                    );
            } else {
                trove_manager.on_adjust_trove(trove_id, vars.new_coll, vars.new_debt, trove_change);
            }

            let active_pool = IActivePoolDispatcher { contract_address: vars.active_pool };
            active_pool.mint_agg_interest_and_account_for_trove_change(trove_change, batch_manager);
            self
                ._move_tokens_from_adjustment(
                    receiver, trove_change, vars.bitusd_token, active_pool,
                );
        }

        fn _apply_upfront_fee(
            self: @ContractState,
            trove_entire_coll: u256,
            mut trove_entire_debt: u256, // TODO check if the mut here won't mut caller value
            ref trove_change: TroveChange,
            max_upfront_fee: u256,
            is_trove_in_batch: bool,
        ) -> u256 {
            let price = self._require_oracles_live();

            let active_pool = IActivePoolDispatcher {
                contract_address: self.liquity_base.active_pool.read(),
            };
            let avg_interest_rate = active_pool
                .get_new_approx_avg_interest_rate_from_trove_change(trove_change);
            trove_change
                .upfront_fee = Self::_calc_upfront_fee(trove_entire_debt, avg_interest_rate);
            Self::_require_user_accepts_upfront_fee(trove_change.upfront_fee, max_upfront_fee);

            trove_entire_debt += trove_change.upfront_fee;

            // ICR is based on the requested bitUSD amount + upfront fee
            let new_icr = math_lib::compute_cr(trove_entire_coll, trove_entire_debt, price);
            if is_trove_in_batch {
                self._require_icr_is_above_mcr_plus_bcr(new_icr);
            } else {
                self._require_icr_is_above_mcr(new_icr);
            }

            // Disallow a premature adjustment if it would result in TCR < CCR
            // (which includes the case when TCR is already below CCR before the adjustment)
            let new_tcr = self._get_new_TCR_from_trove_change(trove_change, price);
            self._require_new_tcr_is_above_ccr(new_tcr);

            return trove_entire_debt;
        }

        fn _calc_upfront_fee(debt: u256, avg_interest_rate: u256) -> u256 {
            return Self::_calc_interest(debt * avg_interest_rate, UPFRONT_INTEREST_PERIOD.into());
        }

        fn _calc_interest(weighted_debt: u256, period: u256) -> u256 {
            return weighted_debt * period / ONE_YEAR.into() / DECIMAL_PRECISION;
        }

        fn _wipe_trove_mappings(ref self: ContractState, trove_id: u256) {
            self.interest_individual_delegate_of.write(trove_id, Default::default());
            self.interest_batch_manager_of.write(trove_id, Default::default());
            // self._wipe_add_remove_managers(trove_id); // TODO: add remove manager
        }

        fn _remove_from_batch(
            ref self: ContractState,
            trove_id: u256,
            mut new_annual_interest_rate: u256,
            upper_hint: u256,
            lower_hint: u256,
            max_upfront_fee: u256,
            kick: bool,
        ) {
            self._require_is_not_shutdown();

            let mut vars: LocalVariables_removeFromBatch = Default::default();
            vars.trove_manager = self.trove_manager.read();
            vars.sorted_troves = self.sorted_troves.read();

            if kick {
                Self::_require_trove_is_open(vars.trove_manager, trove_id);
            } else {
                Self::_require_trove_is_active(vars.trove_manager, trove_id);
                // TODO: require_caller_is_borrower from AddRemoveManagers
                Self::_require_valid_annual_interest_rate(new_annual_interest_rate);
            }

            vars.batch_manager = self._require_is_in_batch(trove_id);
            let trove_manager = ITroveManagerDispatcher { contract_address: vars.trove_manager };
            vars.trove = trove_manager.get_latest_trove_data(trove_id);
            vars.batch = trove_manager.get_latest_batch_data(vars.batch_manager);

            if kick {
                assert(
                    vars.batch.total_debt_shares
                        * MAX_BATCH_SHARES_RATIO < vars.batch.entire_debt_without_redistribution,
                    'BO: Batch Ratio too low',
                );
                new_annual_interest_rate = vars.batch.annual_interest_rate;
            }

            self.interest_batch_manager_of.write(trove_id, Default::default());

            if !Self::_check_trove_is_zombie(vars.trove_manager, trove_id) {
                // Remove trove from Batch in SortedTroves
                let sorted_troves = ISortedTrovesDispatcher {
                    contract_address: vars.sorted_troves,
                };
                sorted_troves.remove_from_batch(trove_id);
                // Reinsert as single trove
                sorted_troves.insert(trove_id, new_annual_interest_rate, upper_hint, lower_hint);
            }

            vars.batch_future_debt = vars.batch.entire_debt_without_redistribution
                - (vars.trove.entire_debt - vars.trove.redist_bit_usd_debt_gain);

            vars
                .batch_change
                .applied_redist_bit_usd_debt_gain = vars
                .trove
                .redist_bit_usd_debt_gain;
            vars.batch_change.applied_redist_coll_gain = vars.trove.redist_coll_gain;
            vars.batch_change.batch_accrued_management_fee = vars.batch.accrued_management_fee;
            vars.batch_change.old_weighted_recorded_debt = vars.batch.weighted_recorded_debt;
            vars.batch_change.new_weighted_recorded_debt = vars.batch_future_debt
                * vars.batch.annual_interest_rate
                + vars.trove.entire_debt * new_annual_interest_rate;

            // Apply upfront fee on premature adjustments. It checks the resulting TCR
            if vars.batch.annual_interest_rate != new_annual_interest_rate
                && get_block_timestamp()
                    .into() < (vars.trove.last_interest_rate_adj_time
                        + INTEREST_RATE_ADJ_COOLDOWN.into()) {
                vars
                    .trove
                    .entire_debt = self
                    ._apply_upfront_fee(
                        vars.trove.entire_coll,
                        vars.trove.entire_debt,
                        ref vars.batch_change,
                        max_upfront_fee,
                        false,
                    );
            }

            // Recalculate newWeightedRecordedDebt, now taking into account the upfront fee
            vars.batch_change.new_weighted_recorded_debt = vars.batch_future_debt
                * vars.batch.annual_interest_rate
                + vars.trove.entire_debt * new_annual_interest_rate;
            // Add batch fees
            vars
                .batch_change
                .old_weighted_recorded_batch_management_fee = vars
                .batch
                .weighted_recorded_batch_management_fee;
            vars.batch_change.new_weighted_recorded_batch_management_fee = vars.batch_future_debt
                * vars.batch.annual_management_fee;

            let active_pool = IActivePoolDispatcher {
                contract_address: self.liquity_base.active_pool.read(),
            };
            active_pool
                .mint_agg_interest_and_account_for_trove_change(
                    vars.batch_change, vars.batch_manager,
                );

            let trove_manager = ITroveManagerDispatcher { contract_address: vars.trove_manager };
            trove_manager
                .on_remove_from_batch(
                    trove_id,
                    vars.trove.entire_coll,
                    vars.trove.entire_debt,
                    vars.batch_change,
                    vars.batch_manager,
                    vars.batch.entire_coll_without_redistribution,
                    vars.batch.entire_debt_without_redistribution,
                    new_annual_interest_rate,
                );
        }

        // --- ICR and TCR getters ---
        fn _get_new_TCR_from_trove_change(
            self: @ContractState, trove_change: TroveChange, price: u256,
        ) -> u256 {
            let mut total_coll = self.liquity_base.get_entire_branch_coll();
            total_coll += trove_change.coll_increase;
            total_coll -= trove_change.coll_decrease;

            let mut total_debt = self.liquity_base.get_entire_branch_debt();
            total_debt += trove_change.debt_increase;
            total_debt += trove_change.upfront_fee;
            total_debt -= trove_change.debt_decrease;

            return math_lib::compute_cr(total_coll, total_debt, price);
        }
    }
}

