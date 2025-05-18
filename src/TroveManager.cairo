use starknet::ContractAddress;
use crate::i257::i257;

#[starknet::interface]
pub trait ITroveNFT<TContractState> {
    fn get_trove_owner(self: @TContractState, trove_id: u256) -> ContractAddress;
}

#[starknet::interface]
pub trait ITroveManager<TContractState> {
    // View functions
    fn get_unbacked_portion_price_and_redeemability(self: @TContractState) -> (u256, u256, bool);
    fn get_batch_ids(self: @TContractState, index: u64) -> ContractAddress;
    fn get_trove_ids_count(self: @TContractState) -> u64;
    fn get_trove_from_trove_ids_array(self: @TContractState, index: u256) -> u256;
    fn get_trove_annual_interest_rate(self: @TContractState, trove_id: u256) -> u256;
    fn get_trove_status(self: @TContractState, trove_id: u256) -> Status;
    fn get_trove_nft(self: @TContractState) -> ContractAddress;
    fn get_borrower_operations(self: @TContractState) -> ContractAddress;
    fn get_stability_pool(self: @TContractState) -> ContractAddress;
    fn get_sorted_troves(self: @TContractState) -> ContractAddress;
    fn get_CCR(self: @TContractState) -> u256;
    fn get_troves(self: @TContractState, index: u256) -> Trove;
    fn get_reward_snapshots(self: @TContractState, index: u256) -> RewardSnapshots;
    fn get_latest_batch_data(
        self: @TContractState, batch_address: ContractAddress,
    ) -> LatestBatchData;
    fn get_current_ICR(self: @TContractState, trove_id: u256, price: u256) -> u256;
    fn get_last_zombie_trove_id(self: @TContractState) -> u256;
    fn get_shutdown_time(self: @TContractState) -> u256;

    // External functions
    fn redeem_collateral(
        ref self: TContractState,
        msg_sender: ContractAddress,
        redeem_amount: u256,
        price: u256,
        redemption_rate: u256,
        max_iterations: u256,
    ) -> u256;
    fn batch_liquidate_troves(ref self: TContractState, trove_array: Span<u256>);
    fn on_remove_from_batch(
        ref self: TContractState,
        trove_id: u256,
        new_trove_coll: u256,
        new_trove_debt: u256,
        trove_change: TroveChange,
        batch_address: ContractAddress,
        new_batch_coll: u256,
        new_batch_debt: u256,
        new_annual_interest_rate: u256,
    );
    fn on_set_interest_batch_manager(
        ref self: TContractState, params: OnSetInterestBatchManagerParams,
    );
    fn on_lower_batch_manager_annual_fee(
        ref self: TContractState,
        batch_address: ContractAddress,
        new_coll: u256,
        new_debt: u256,
        new_annual_management_fee: u256,
    );
    fn urgent_redemption(
        ref self: TContractState, bit_usd_amount: u256, trove_ids: Span<u256>, min_collateral: u256,
    );
    fn on_open_trove_and_join_batch(
        ref self: TContractState,
        owner: ContractAddress,
        trove_id: u256,
        trove_change: TroveChange,
        batch_address: ContractAddress,
        batch_coll: u256,
        batch_debt: u256,
    );
    fn set_trove_status_to_active(ref self: TContractState, trove_id: u256);
    fn on_adjust_trove_interest_rate(
        ref self: TContractState,
        trove_id: u256,
        new_coll: u256,
        new_debt: u256,
        new_annual_interest_rate: u256,
        trove_change: TroveChange,
    );
    fn on_adjust_trove(
        ref self: TContractState,
        trove_id: u256,
        new_coll: u256,
        new_debt: u256,
        trove_change: TroveChange,
    );
    fn on_close_trove(
        ref self: TContractState,
        trove_id: u256,
        trove_change: TroveChange,
        batch_address: ContractAddress,
        new_batch_coll: u256,
        new_batch_debt: u256,
    );
    fn on_open_trove(
        ref self: TContractState,
        owner: ContractAddress,
        trove_id: u256,
        trove_change: TroveChange,
        annual_interest_rate: u256,
    );
    fn on_adjust_trove_inside_batch(
        ref self: TContractState,
        trove_id: u256,
        new_trove_coll: u256,
        new_trove_debt: u256,
        trove_change: TroveChange,
        batch_address: ContractAddress,
        new_batch_coll: u256,
        new_batch_debt: u256,
    );
    fn on_apply_trove_interest(
        ref self: TContractState,
        trove_id: u256,
        new_trove_coll: u256,
        new_trove_debt: u256,
        batch_address: ContractAddress,
        new_batch_coll: u256,
        new_batch_debt: u256,
        trove_change: TroveChange,
    );
    fn on_register_batch_manager(
        ref self: TContractState,
        account: ContractAddress,
        annual_interest_rate: u256,
        annual_management_fee: u256,
    );
    fn on_set_batch_manager_annual_interest_rate(
        ref self: TContractState,
        batch_address: ContractAddress,
        new_coll: u256,
        new_debt: u256,
        new_annual_interest_rate: u256,
        upfront_fee: u256,
    );
}

#[derive(Copy, Drop, Serde, starknet::Store, Default)]
struct RewardSnapshots {
    coll: u256,
    bit_usd_debt: u256,
}

#[derive(Copy, Drop, Serde, starknet::Store)]
struct OnSetInterestBatchManagerParams {
    trove_id: u256,
    trove_coll: u256,
    trove_debt: u256,
    trove_change: TroveChange,
    new_batch_address: ContractAddress,
    new_batch_coll: u256,
    new_batch_debt: u256,
}

#[derive(Copy, Drop, Serde, starknet::Store)]
struct Trove {
    debt: u256,
    coll: u256,
    stake: u256,
    status: Status,
    array_index: u64,
    last_debt_update_time: u64,
    last_interest_rate_adj_time: u64,
    annual_interest_rate: u256,
    interest_batch_manager: ContractAddress,
    batch_debt_shares: u256,
}

#[derive(Copy, Drop, Serde, starknet::Store, Default)]
pub struct TroveChange {
    pub applied_redist_bit_usd_debt_gain: u256,
    pub applied_redist_coll_gain: u256,
    pub coll_increase: u256,
    pub coll_decrease: u256,
    pub debt_increase: u256,
    pub debt_decrease: u256,
    pub new_weighted_recorded_debt: u256,
    pub old_weighted_recorded_debt: u256,
    pub upfront_fee: u256,
    pub batch_accrued_management_fee: u256,
    pub new_weighted_recorded_batch_management_fee: u256,
    pub old_weighted_recorded_batch_management_fee: u256,
}

#[derive(Copy, Drop, PartialEq, Serde, starknet::Store)]
enum Status {
    #[default]
    NonExistent,
    Active,
    ClosedByOwner,
    ClosedByLiquidation,
    Zombie,
}

#[derive(Copy, Drop, Serde, starknet::Store, Default)]
struct LatestTroveData {
    entire_debt: u256,
    entire_coll: u256,
    redist_bit_usd_debt_gain: u256,
    redist_coll_gain: u256,
    accrued_interest: u256,
    recorded_debt: u256,
    annual_interest_rate: u256,
    weighted_recorded_debt: u256,
    accrued_batch_management_fee: u256,
    last_interest_rate_adj_time: u256,
}

#[derive(Copy, Drop, Serde, starknet::Store, Default)]
struct LatestBatchData {
    total_debt_shares: u256,
    entire_debt_without_redistribution: u256,
    entire_coll_without_redistribution: u256,
    accrued_interest: u256,
    recorded_debt: u256,
    annual_interest_rate: u256,
    weighted_recorded_debt: u256,
    annual_management_fee: u256,
    accrued_management_fee: u256,
    weighted_recorded_batch_management_fee: u256,
    last_debt_update_time: u256,
    last_interest_rate_adj_time: u256,
}

#[derive(Drop, starknet::Event)]
pub struct TroveUpdated {
    trove_id: u256,
    debt: u256,
    coll: u256,
    stake: u256,
    annual_interest_rate: u256,
    snapshot_of_total_coll_redist: u256,
    snapshot_of_total_debt_redist: u256,
}

#[derive(Drop, starknet::Event)]
pub struct Liquidation {
    debt_offset_by_SP: u256,
    debt_redistributed: u256,
    bit_usd_gas_compensation: u256,
    coll_gas_compensation: u256,
    coll_sent_to_SP: u256,
    coll_redistributed: u256,
    coll_surplus: u256,
    l_coll: u256,
    l_bit_usd_debt: u256,
    price: u256,
}

#[derive(Drop, starknet::Event)]
pub struct TroveOperation {
    trove_id: u256,
    operation: Operation,
    annual_interest_rate: u256,
    debt_increase_from_redist: u256,
    debt_increase_from_upfront_fee: u256,
    debt_change_from_operation: i257,
    coll_increase_from_redist: u256,
    coll_change_from_operation: i257,
}

#[derive(Drop, starknet::Event)]
pub struct Redemption {
    attempted_bit_usd_amount: u256,
    actual_bit_usd_amount: u256,
    coll_sent: u256,
    coll_fee: u256,
    price: u256,
    redemption_price: u256,
}

#[derive(Drop, starknet::Event)]
pub struct BatchUpdated {
    interest_batch_manager: ContractAddress,
    operation: BatchOperation,
    debt: u256,
    coll: u256,
    annual_interest_rate: u256,
    annual_management_fee: u256,
    total_debt_shares: u256,
    debt_increase_from_upfront_fee: u256,
}

#[derive(Drop, starknet::Event)]
pub struct BatchedTroveUpdated {
    trove_id: u256,
    interest_batch_manager: ContractAddress,
    batch_debt_shares: u256,
    coll: u256,
    stake: u256,
    snapshot_of_total_coll_redist: u256,
    snapshot_of_total_debt_redist: u256,
}

#[derive(Drop, starknet::Event)]
pub struct RedemptionFeePaidToTrove {
    trove_id: u256,
    eth_fee: u256,
}

#[allow(starknet::store_no_default_variant)]
#[derive(Copy, Drop, PartialEq, Serde, starknet::Store)]
enum Operation {
    OpenTrove,
    CloseTrove,
    AdjustTrove,
    AdjustTroveInterestRate,
    ApplyPendingDebt,
    Liquidate,
    RedeemCollateral,
    // batch management
    OpenTroveAndJoinBatch,
    SetInterestBatchManager,
    RemoveFromBatch,
}

#[allow(starknet::store_no_default_variant)]
#[derive(Copy, Drop, PartialEq, Serde, starknet::Store)]
enum BatchOperation {
    RegisterBatchManager,
    LowerBatchManagerAnnualFee,
    SetBatchManagerAnnualInterestRate,
    ApplyBatchInterestAndFee,
    JoinBatch,
    ExitBatch,
    // used when the batch is updated as a result of a Trove change inside the batch
    TroveChange,
}

#[starknet::contract]
pub mod TroveManager {
    use core::array::ArrayTrait;
    use core::cmp::{max, min};
    use core::traits::TryInto;
    use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use starknet::storage::{
        Map, MutableVecTrait, StorageMapReadAccess, StoragePathEntry, StoragePointerReadAccess,
        StoragePointerWriteAccess, Vec, VecTrait,
    };
    use starknet::{ContractAddress, get_block_timestamp, get_caller_address};
    use crate::ActivePool::{IActivePoolDispatcher, IActivePoolDispatcherTrait};
    use crate::AddressesRegistry::{IAddressesRegistryDispatcher, IAddressesRegistryDispatcherTrait};
    use crate::BorrowerOperations::{
        IBorrowerOperationsDispatcher, IBorrowerOperationsDispatcherTrait,
    };
    use crate::CollSurplusPool::{ICollSurplusPoolDispatcher, ICollSurplusPoolDispatcherTrait};
    use crate::DefaultPool::{IDefaultPoolDispatcher, IDefaultPoolDispatcherTrait};
    use crate::SortedTroves::{ISortedTrovesDispatcher, ISortedTrovesDispatcherTrait};
    use crate::StabilityPool::{IStabilityPoolDispatcher, IStabilityPoolDispatcherTrait};
    use crate::TroveNFT::{ITroveNFTDispatcher, ITroveNFTDispatcherTrait};
    use crate::dependencies::Constants::Constants::{
        COLL_GAS_COMPENSATION_CAP, COLL_GAS_COMPENSATION_DIVISOR, DECIMAL_PRECISION,
        ETH_GAS_COMPENSATION, MAX_BATCH_SHARES_RATIO, MAX_UINT256, MIN_BITUSD_IN_SP, MIN_DEBT,
        URGENT_REDEMPTION_BONUS, _100PCT,
    };
    use crate::dependencies::ConversionLib::conversion_lib;
    use crate::dependencies::LiquityBase::LiquityBaseComponent;
    use crate::dependencies::MathLib::math_lib;
    use crate::i257::{I257Trait, i257Add, i257Neg, i257Sub};
    // TODO: Add valid price feed.
    use crate::mocks::PriceFeedMock::{IPriceFeedMockDispatcher, IPriceFeedMockDispatcherTrait};
    use super::{
        BatchOperation, BatchUpdated, BatchedTroveUpdated, ITroveManager, LatestBatchData,
        LatestTroveData, Liquidation, OnSetInterestBatchManagerParams, Operation, Redemption,
        RedemptionFeePaidToTrove, RewardSnapshots, Status, Trove, TroveChange, TroveOperation,
        TroveUpdated,
    };

    component!(path: LiquityBaseComponent, storage: liquity_base, event: LiquityBaseEvent);

    //////////////////////////////////////////////////////////////
    //                          STORAGE                         //
    //////////////////////////////////////////////////////////////

    #[storage]
    struct Storage {
        trove_nft: ContractAddress,
        borrower_operations: ContractAddress,
        stability_pool: ContractAddress,
        gas_pool: ContractAddress,
        coll_surplus_pool: ContractAddress,
        bit_usd_token: ContractAddress,
        sorted_troves: ContractAddress,
        collateral_registry: ContractAddress,
        ETH: ContractAddress,
        CCR: u256,
        SCR: u256,
        MCR: u256,
        BCR: u256,
        liquidation_penalty_SP: u256,
        liquidation_penalty_redistribution: u256,
        troves: Map<u256, Trove>,
        batches: Map<ContractAddress, Batch>,
        total_stakes: u256,
        // Snapshot of the value of totalStakes, taken immediately after the latest liquidation
        total_stakes_snapshot: u256,
        // Snapshot of the total collateral across the ActivePool and DefaultPool, immediately after
        // the latest liquidation.
        total_collateral_snapshot: u256,
        // L_coll and L_bit_usd Debt track the sums of accumulated liquidation rewards per unit
        // staked.
        // During its lifetime, each stake earns:
        // An Coll gain of ( stake * [L_coll - L_coll(0)] )
        // A bit_usd Debt increase  of ( stake * [L_bit_usd Debt - L_bit_usd Debt(0)] )
        // Where L_coll(0) and L_bit_usd Debt(0) are snapshots of L_coll and L_bit_usd Debt for the
        // active Trove taken at the instant the stake was made.
        l_coll: u256,
        l_bit_usd_debt: u256,
        reward_snapshots: Map<u256, RewardSnapshots>,
        trove_ids: Vec<u256>,
        batch_ids: Vec<ContractAddress>,
        last_zombie_trove_id: u256,
        // Error trackers for the trove redistribution calculation
        last_coll_error_redistribution: u256,
        last_bit_usd_debt_error_redistribution: u256,
        shutdown_time: u256,
        #[substorage(v0)]
        liquity_base: LiquityBaseComponent::Storage,
    }

    //////////////////////////////////////////////////////////////
    //                          STRUCTS                         //
    //////////////////////////////////////////////////////////////

    #[derive(Copy, Drop, Serde, starknet::Store, Default)]
    struct Batch {
        debt: u256,
        coll: u256,
        array_index: u64,
        last_debt_update_time: u64,
        last_interest_rate_adj_time: u64,
        annual_interest_rate: u256,
        annual_management_fee: u256,
        total_debt_shares: u256,
    }

    #[derive(Copy, Drop, Serde, starknet::Store, Default)]
    struct LiquidationValues {
        coll_gas_compensation: u256,
        debt_to_offset: u256,
        coll_to_send_to_SP: u256,
        debt_to_redistribute: u256,
        coll_to_redistribute: u256,
        coll_surplus: u256,
        eth_gas_compensation: u256,
        old_weighted_recorded_debt: u256,
        new_weighted_recorded_debt: u256,
    }

    #[derive(Copy, Drop, Serde, starknet::Store)]
    struct RedeemCollateralValues {
        total_coll_fee: u256,
        remaining_bit_usd: u256,
        last_batch_updated_interest: ContractAddress,
        next_user_to_check: u256,
    }

    #[derive(Copy, Drop, Serde, starknet::Store)]
    struct SingleRedemptionValues {
        trove_id: u256,
        batch_address: ContractAddress,
        bit_usd_lot: u256,
        coll_lot: u256,
        coll_fee: u256,
        applied_redist_bit_usd_debt_gain: u256,
        old_weighted_recorded_debt: u256,
        new_weighted_recorded_debt: u256,
        new_stake: u256,
        is_zombie_trove: bool,
        trove: LatestTroveData,
        batch: LatestBatchData,
    }

    //////////////////////////////////////////////////////////////
    //                          EVENTS                          //
    //////////////////////////////////////////////////////////////

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        TroveNFTAddressChanged: TroveNFTAddressChanged,
        BorrowerOperationsAddressChanged: BorrowerOperationsAddressChanged,
        BitUSDTokenAddressChanged: BitUSDTokenAddressChanged,
        StabilityPoolAddressChanged: StabilityPoolAddressChanged,
        GasPoolAddressChanged: GasPoolAddressChanged,
        CollSurplusPoolAddressChanged: CollSurplusPoolAddressChanged,
        SortedTrovesAddressChanged: SortedTrovesAddressChanged,
        CollateralRegistryAddressChanged: CollateralRegistryAddressChanged,
        TroveUpdated: TroveUpdated,
        TroveOperation: TroveOperation,
        BatchUpdated: BatchUpdated,
        BatchedTroveUpdated: BatchedTroveUpdated,
        Liquidation: Liquidation,
        RedemptionFeePaidToTrove: RedemptionFeePaidToTrove,
        Redemption: Redemption,
        #[flat]
        LiquityBaseEvent: LiquityBaseComponent::Event,
    }

    #[derive(Drop, starknet::Event)]
    pub struct TroveNFTAddressChanged {
        pub new_trove_nft_address: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    pub struct BorrowerOperationsAddressChanged {
        pub new_borrower_operations_address: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    pub struct BitUSDTokenAddressChanged {
        pub new_bit_usd_token_address: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    pub struct StabilityPoolAddressChanged {
        pub new_stability_pool_address: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    pub struct GasPoolAddressChanged {
        pub new_gas_pool_address: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    pub struct CollSurplusPoolAddressChanged {
        pub new_coll_surplus_pool_address: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    pub struct SortedTrovesAddressChanged {
        pub new_sorted_troves_address: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    pub struct CollateralRegistryAddressChanged {
        pub new_collateral_registry_address: ContractAddress,
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
        self.liquity_base.initializer(addresses_registry);

        let addresses_registry = IAddressesRegistryDispatcher {
            contract_address: addresses_registry,
        };

        self.trove_nft.write(addresses_registry.get_trove_nft());
        self.borrower_operations.write(addresses_registry.get_borrower_operations());
        self.stability_pool.write(addresses_registry.get_stability_pool());
        self.gas_pool.write(addresses_registry.get_gas_pool());
        self.coll_surplus_pool.write(addresses_registry.get_coll_surplus_pool());
        self.sorted_troves.write(addresses_registry.get_sorted_troves());
        self.collateral_registry.write(addresses_registry.get_collateral_registry());
        self.bit_usd_token.write(addresses_registry.get_bitusd_token());
        self.ETH.write(addresses_registry.get_eth());

        self
            .emit(
                event: TroveNFTAddressChanged {
                    new_trove_nft_address: addresses_registry.get_trove_nft(),
                },
            );

        self
            .emit(
                event: BorrowerOperationsAddressChanged {
                    new_borrower_operations_address: addresses_registry.get_borrower_operations(),
                },
            );

        self
            .emit(
                event: BitUSDTokenAddressChanged {
                    new_bit_usd_token_address: addresses_registry.get_bitusd_token(),
                },
            );

        self
            .emit(
                event: StabilityPoolAddressChanged {
                    new_stability_pool_address: addresses_registry.get_stability_pool(),
                },
            );

        self
            .emit(
                event: GasPoolAddressChanged {
                    new_gas_pool_address: addresses_registry.get_gas_pool(),
                },
            );

        self
            .emit(
                event: CollSurplusPoolAddressChanged {
                    new_coll_surplus_pool_address: addresses_registry.get_coll_surplus_pool(),
                },
            );

        self
            .emit(
                event: SortedTrovesAddressChanged {
                    new_sorted_troves_address: addresses_registry.get_sorted_troves(),
                },
            );

        self
            .emit(
                event: CollateralRegistryAddressChanged {
                    new_collateral_registry_address: addresses_registry.get_collateral_registry(),
                },
            );
    }

    ////////////////////////////////////////////////////////////////
    //                     EXTERNAL FUNCTIONS                     //
    ////////////////////////////////////////////////////////////////

    impl ITroveManagerImpl of ITroveManager<ContractState> {
        // VIEW FUNCTIONS
        fn get_trove_ids_count(self: @ContractState) -> u64 {
            self.trove_ids.len()
        }

        fn get_trove_from_trove_ids_array(self: @ContractState, index: u256) -> u256 {
            self.trove_ids.at(index.try_into().unwrap()).read()
        }

        fn get_trove_status(self: @ContractState, trove_id: u256) -> Status {
            self.troves.entry(trove_id).status.read()
        }

        fn get_trove_nft(self: @ContractState) -> ContractAddress {
            self.trove_nft.read()
        }

        fn get_batch_ids(self: @ContractState, index: u64) -> ContractAddress {
            self.batch_ids.at(index.try_into().unwrap()).read()
        }

        fn get_borrower_operations(self: @ContractState) -> ContractAddress {
            self.borrower_operations.read()
        }

        fn get_stability_pool(self: @ContractState) -> ContractAddress {
            self.stability_pool.read()
        }

        fn get_sorted_troves(self: @ContractState) -> ContractAddress {
            self.sorted_troves.read()
        }

        fn get_CCR(self: @ContractState) -> u256 {
            self.CCR.read()
        }

        fn get_shutdown_time(self: @ContractState) -> u256 {
            self.shutdown_time.read()
        }

        fn get_last_zombie_trove_id(self: @ContractState) -> u256 {
            self.last_zombie_trove_id.read()
        }

        fn get_troves(self: @ContractState, index: u256) -> Trove {
            self.troves.entry(index.try_into().unwrap()).read()
        }

        fn get_reward_snapshots(self: @ContractState, index: u256) -> RewardSnapshots {
            self.reward_snapshots.entry(index.try_into().unwrap()).read()
        }

        fn get_latest_batch_data(
            self: @ContractState, batch_address: ContractAddress,
        ) -> LatestBatchData {
            let mut batch: LatestBatchData = Default::default();

            _get_latest_batch_data(self, batch_address, ref batch);
            batch
        }

        fn get_current_ICR(self: @ContractState, trove_id: u256, price: u256) -> u256 {
            _get_current_ICR(self, trove_id, price)
        }

        fn get_unbacked_portion_price_and_redeemability(
            self: @ContractState,
        ) -> (u256, u256, bool) {
            let total_debt = self.liquity_base.get_entire_branch_debt();
            let stability_pool = IStabilityPoolDispatcher {
                contract_address: self.stability_pool.read(),
            };
            let spSize = stability_pool.get_total_bitusd_deposits();
            let mut unbacked_portion = 0;
            if (total_debt > spSize) {
                unbacked_portion = total_debt - spSize;
            }

            let price_feed = IPriceFeedMockDispatcher {
                contract_address: self.liquity_base.price_feed.read(),
            };
            let price = price_feed.fetch_price();

            // It's redeemable if the TCR is above the shutdown threshold, and branch has not been
            // shut down.
            // Use the normal price for the TCR check.
            let redeemable = self.liquity_base._get_TCR(price) >= self.SCR.read()
                && self.shutdown_time.read() == 0;
            (unbacked_portion, price, redeemable)
        }

        fn get_trove_annual_interest_rate(self: @ContractState, trove_id: u256) -> u256 {
            let trove: Trove = self.troves.entry(trove_id).read();
            let batch_address = trove.interest_batch_manager;
            if (batch_address != 0.try_into().unwrap()) {
                return self.batches.entry(batch_address).annual_interest_rate.read();
            }
            return trove.annual_interest_rate;
        }

        // STATE MODIFYING FUNCTIONS
        fn batch_liquidate_troves(ref self: ContractState, trove_array: Span<u256>) {
            assert(trove_array.len() > 0, 'TM: blt: empty data');
            let active_pool_address = self.liquity_base.active_pool.read();
            let active_pool = IActivePoolDispatcher { contract_address: active_pool_address };
            let default_pool_address = self.liquity_base.default_pool.read();
            let stability_pool = IStabilityPoolDispatcher {
                contract_address: self.stability_pool.read(),
            };

            let mut trove_change: TroveChange = Default::default();
            let mut totals: LiquidationValues = Default::default();

            // TODO: Add price feed
            let price_feed = IPriceFeedMockDispatcher {
                contract_address: self.liquity_base.price_feed.read(),
            };
            let price = price_feed.fetch_price();

            // - If the SP has total deposits >= 1e18, we leave 1e18 in it untouched.
            // - If it has 0 < x < 1e18 total deposits, we leave x in it.
            let total_bit_usd_deposits = stability_pool.get_total_bitusd_deposits();
            let bit_usd_to_leave_in_SP = min(MIN_BITUSD_IN_SP, total_bit_usd_deposits);
            let bit_usd_in_SP_for_offsets = total_bit_usd_deposits - bit_usd_to_leave_in_SP;

            // Perform the appropriate liquidation sequence - tally values and obtain their totals.
            _batch_liquidate_troves(
                ref self,
                default_pool_address,
                price,
                bit_usd_in_SP_for_offsets,
                trove_array,
                ref totals,
                ref trove_change,
            );

            assert(trove_change.debt_decrease > 0, 'TM: Nothing to liquidate');

            active_pool
                .mint_agg_interest_and_account_for_trove_change(
                    trove_change, 0.try_into().unwrap(),
                );
            // Move liquidated Coll and Bold to the appropriate pools
            if (totals.debt_to_offset > 0 || totals.coll_to_send_to_SP > 0) {
                stability_pool.offset(totals.debt_to_offset, totals.coll_to_send_to_SP);
            }

            // we check amount is not zero inside
            _redistribute_debt_and_coll(
                ref self,
                active_pool_address,
                default_pool_address,
                totals.debt_to_redistribute,
                totals.coll_to_redistribute,
            );

            if (totals.coll_surplus > 0) {
                active_pool.send_coll(self.coll_surplus_pool.read(), totals.coll_surplus);
            }

            // Update system snapshots
            _update_system_snapshots_exclude_coll_remainder(
                ref self, active_pool_address, totals.coll_gas_compensation,
            );

            self
                .emit(
                    event: Liquidation {
                        debt_offset_by_SP: totals.debt_to_offset,
                        debt_redistributed: totals.debt_to_redistribute,
                        bit_usd_gas_compensation: totals.eth_gas_compensation,
                        coll_gas_compensation: totals.coll_gas_compensation,
                        coll_sent_to_SP: totals.coll_to_send_to_SP,
                        coll_redistributed: totals.coll_to_redistribute,
                        coll_surplus: totals.coll_surplus,
                        l_coll: self.l_coll.read(),
                        l_bit_usd_debt: self.l_bit_usd_debt.read(),
                        price: price,
                    },
                );

            // Send gas compensation to caller
            _send_gas_compensation(
                ref self,
                active_pool_address,
                get_caller_address(),
                totals.eth_gas_compensation,
                totals.coll_gas_compensation,
            );
        }

        fn on_remove_from_batch(
            ref self: ContractState,
            trove_id: u256,
            new_trove_coll: u256,
            new_trove_debt: u256,
            trove_change: TroveChange,
            batch_address: ContractAddress,
            new_batch_coll: u256,
            new_batch_debt: u256,
            new_annual_interest_rate: u256,
        ) {
            _require_caller_is_borrower_operations(@self);
            // assert(batchIds[batches[_batchAddress].arrayIndex] == _batchAddress);

            // Subtract from batch
            _remove_trove_shares_from_batch(
                ref self,
                trove_id,
                new_trove_coll,
                new_trove_debt,
                trove_change,
                batch_address,
                new_batch_coll,
                new_batch_debt,
            );

            // Restore Trove state
            self.troves.entry(trove_id).debt.write(new_trove_debt);
            self.troves.entry(trove_id).coll.write(new_trove_coll);
            self.troves.entry(trove_id).last_debt_update_time.write(get_block_timestamp());
            self.troves.entry(trove_id).annual_interest_rate.write(new_annual_interest_rate);
            self.troves.entry(trove_id).last_interest_rate_adj_time.write(get_block_timestamp());

            _update_trove_reward_snapshots(ref self, trove_id);
            _move_pending_trove_rewards_to_active_pool(
                ref self,
                self.liquity_base.default_pool.read(),
                trove_change.applied_redist_bit_usd_debt_gain,
                trove_change.applied_redist_coll_gain,
            );

            self
                .emit(
                    event: TroveUpdated {
                        trove_id: trove_id,
                        debt: new_trove_debt,
                        coll: new_trove_coll,
                        stake: self.troves.entry(trove_id).stake.read(),
                        annual_interest_rate: new_annual_interest_rate,
                        snapshot_of_total_coll_redist: self.l_coll.read(),
                        snapshot_of_total_debt_redist: self.l_bit_usd_debt.read(),
                    },
                );

            self
                .emit(
                    event: TroveOperation {
                        trove_id: trove_id,
                        operation: Operation::RemoveFromBatch,
                        annual_interest_rate: new_annual_interest_rate,
                        debt_increase_from_redist: trove_change.applied_redist_bit_usd_debt_gain,
                        debt_increase_from_upfront_fee: trove_change.upfront_fee,
                        debt_change_from_operation: I257Trait::new(0, false),
                        coll_increase_from_redist: trove_change.applied_redist_coll_gain,
                        coll_change_from_operation: I257Trait::new(0, false),
                    },
                );

            self
                .emit(
                    event: BatchUpdated {
                        interest_batch_manager: batch_address,
                        operation: BatchOperation::ExitBatch,
                        debt: self.batches.entry(batch_address).debt.read(),
                        coll: self.batches.entry(batch_address).coll.read(),
                        annual_interest_rate: self
                            .batches
                            .entry(batch_address)
                            .annual_interest_rate
                            .read(),
                        annual_management_fee: self
                            .batches
                            .entry(batch_address)
                            .annual_management_fee
                            .read(),
                        total_debt_shares: self
                            .batches
                            .entry(batch_address)
                            .total_debt_shares
                            .read(),
                        // Although the Trove leaving the batch may pay an upfront fee,
                        // it is an individual fee, so we don't include it here
                        debt_increase_from_upfront_fee: 0,
                    },
                );
        }

        fn on_open_trove(
            ref self: ContractState,
            owner: ContractAddress,
            trove_id: u256,
            trove_change: TroveChange,
            annual_interest_rate: u256,
        ) {
            _require_caller_is_borrower_operations(@self);
            let new_stake = _compute_new_stake(@self, trove_change.coll_increase);

            self
                .troves
                .entry(trove_id)
                .debt
                .write(trove_change.debt_increase + trove_change.upfront_fee);
            self.troves.entry(trove_id).coll.write(trove_change.coll_increase);
            self.troves.entry(trove_id).stake.write(new_stake);
            self.troves.entry(trove_id).status.write(Status::Active);
            self.troves.entry(trove_id).array_index.write(self.trove_ids.len().try_into().unwrap());
            self.troves.entry(trove_id).last_debt_update_time.write(get_block_timestamp());
            self.troves.entry(trove_id).last_interest_rate_adj_time.write(get_block_timestamp());
            self.troves.entry(trove_id).annual_interest_rate.write(annual_interest_rate);

            // Push the trove's id to the Trove list
            self.trove_ids.push(trove_id);

            let new_total_stakes = self.total_stakes.read() + new_stake;
            self.total_stakes.write(new_total_stakes);

            // Mint ERC721
            let trove_nft = ITroveNFTDispatcher { contract_address: self.trove_nft.read() };
            trove_nft.mint(owner, trove_id);

            _update_trove_reward_snapshots(ref self, trove_id);

            self
                .emit(
                    event: TroveUpdated {
                        trove_id: trove_id,
                        debt: trove_change.debt_increase + trove_change.upfront_fee,
                        coll: trove_change.coll_increase,
                        stake: new_stake,
                        annual_interest_rate: annual_interest_rate,
                        snapshot_of_total_coll_redist: self.l_coll.read(),
                        snapshot_of_total_debt_redist: self.l_bit_usd_debt.read(),
                    },
                );

            self
                .emit(
                    event: TroveOperation {
                        trove_id: trove_id,
                        operation: Operation::OpenTrove,
                        annual_interest_rate: annual_interest_rate,
                        debt_increase_from_redist: 0,
                        debt_increase_from_upfront_fee: trove_change.upfront_fee,
                        debt_change_from_operation: I257Trait::new(
                            trove_change.debt_increase, false,
                        ),
                        coll_increase_from_redist: 0,
                        coll_change_from_operation: I257Trait::new(
                            trove_change.coll_increase, false,
                        ),
                    },
                );
        }

        fn on_set_interest_batch_manager(
            ref self: ContractState, params: OnSetInterestBatchManagerParams,
        ) {
            _require_caller_is_borrower_operations(@self);

            let mut trove_change: TroveChange = params.trove_change;
            // assert(batchIds[batches[_params.newBatchAddress].arrayIndex] ==
            // _params.newBatchAddress);
            _update_trove_reward_snapshots(ref self, params.trove_id);

            // Clean Trove state
            self.troves.entry(params.trove_id).debt.write(0);
            self.troves.entry(params.trove_id).annual_interest_rate.write(0);
            self.troves.entry(params.trove_id).last_debt_update_time.write(0);
            self.troves.entry(params.trove_id).coll.write(params.trove_coll);

            self
                .troves
                .entry(params.trove_id)
                .interest_batch_manager
                .write(params.new_batch_address);
            self
                .troves
                .entry(params.trove_id)
                .last_interest_rate_adj_time
                .write(get_block_timestamp());

            trove_change.coll_increase = params.trove_coll - trove_change.applied_redist_coll_gain;
            trove_change.debt_increase = params.trove_debt
                - trove_change.applied_redist_bit_usd_debt_gain
                - trove_change.upfront_fee;

            assert(params.trove_debt > 0, 'TM: trove debt is 0');
            _update_batch_shares(
                ref self,
                params.trove_id,
                params.new_batch_address,
                trove_change,
                params.trove_debt,
                params.new_batch_coll,
                params.new_batch_debt,
                true,
            );
            _move_pending_trove_rewards_to_active_pool(
                ref self,
                self.liquity_base.default_pool.read(),
                trove_change.applied_redist_bit_usd_debt_gain,
                trove_change.applied_redist_coll_gain,
            );

            self
                .emit(
                    event: BatchedTroveUpdated {
                        trove_id: params.trove_id,
                        interest_batch_manager: params.new_batch_address,
                        batch_debt_shares: self
                            .troves
                            .entry(params.trove_id)
                            .batch_debt_shares
                            .read(),
                        coll: params.trove_coll,
                        stake: self.troves.entry(params.trove_id).stake.read(),
                        snapshot_of_total_coll_redist: self.l_coll.read(),
                        snapshot_of_total_debt_redist: self.l_bit_usd_debt.read(),
                    },
                );

            self
                .emit(
                    event: TroveOperation {
                        trove_id: params.trove_id,
                        operation: Operation::SetInterestBatchManager,
                        annual_interest_rate: self
                            .batches
                            .entry(params.new_batch_address)
                            .annual_interest_rate
                            .read(),
                        debt_increase_from_redist: trove_change.applied_redist_bit_usd_debt_gain,
                        debt_increase_from_upfront_fee: trove_change.upfront_fee,
                        debt_change_from_operation: I257Trait::new(0, false),
                        coll_increase_from_redist: trove_change.applied_redist_coll_gain,
                        coll_change_from_operation: I257Trait::new(0, false),
                    },
                );

            self
                .emit(
                    event: BatchUpdated {
                        interest_batch_manager: params.new_batch_address,
                        operation: BatchOperation::JoinBatch,
                        debt: self.batches.entry(params.new_batch_address).debt.read(),
                        coll: self.batches.entry(params.new_batch_address).coll.read(),
                        annual_interest_rate: self
                            .batches
                            .entry(params.new_batch_address)
                            .annual_interest_rate
                            .read(),
                        annual_management_fee: self
                            .batches
                            .entry(params.new_batch_address)
                            .annual_management_fee
                            .read(),
                        total_debt_shares: self
                            .batches
                            .entry(params.new_batch_address)
                            .total_debt_shares
                            .read(),
                        // Although the Trove joining the batch may pay an upfront fee,
                        // it is an individual fee, so we don't include it here
                        debt_increase_from_upfront_fee: 0,
                    },
                );
        }

        fn on_apply_trove_interest(
            ref self: ContractState,
            trove_id: u256,
            new_trove_coll: u256,
            new_trove_debt: u256,
            batch_address: ContractAddress,
            new_batch_coll: u256,
            new_batch_debt: u256,
            trove_change: TroveChange,
        ) {
            _require_caller_is_borrower_operations(@self);

            self.troves.entry(trove_id).coll.write(new_trove_coll);

            if (batch_address != 0.try_into().unwrap()) {
                // TODO: Below assertion is marked as to remove before deployment
                // assert(new_trove_debt > 0, 'TM: trove debt is 0');
                _update_batch_shares(
                    ref self,
                    trove_id,
                    batch_address,
                    trove_change,
                    new_trove_debt,
                    new_batch_coll,
                    new_batch_debt,
                    true,
                );

                self
                    .emit(
                        event: BatchUpdated {
                            interest_batch_manager: batch_address,
                            operation: BatchOperation::ApplyBatchInterestAndFee,
                            debt: new_batch_debt,
                            coll: new_batch_coll,
                            annual_interest_rate: self
                                .batches
                                .entry(batch_address)
                                .annual_interest_rate
                                .read(),
                            annual_management_fee: self
                                .batches
                                .entry(batch_address)
                                .annual_management_fee
                                .read(),
                            total_debt_shares: self
                                .batches
                                .entry(batch_address)
                                .total_debt_shares
                                .read(),
                            debt_increase_from_upfront_fee: 0,
                        },
                    );
            } else {
                self.troves.entry(trove_id).debt.write(new_trove_debt);
                self.troves.entry(trove_id).last_debt_update_time.write(get_block_timestamp());
            }

            _move_pending_trove_rewards_to_active_pool(
                ref self,
                self.liquity_base.default_pool.read(),
                trove_change.applied_redist_bit_usd_debt_gain,
                trove_change.applied_redist_coll_gain,
            );

            _update_trove_reward_snapshots(ref self, trove_id);

            self
                .emit(
                    event: TroveUpdated {
                        trove_id: trove_id,
                        debt: new_trove_debt,
                        coll: new_trove_coll,
                        stake: self.troves.entry(trove_id).stake.read(),
                        annual_interest_rate: self
                            .troves
                            .entry(trove_id)
                            .annual_interest_rate
                            .read(),
                        snapshot_of_total_coll_redist: self.l_coll.read(),
                        snapshot_of_total_debt_redist: self.l_bit_usd_debt.read(),
                    },
                );

            let debt_increase_i257 = I257Trait::new(trove_change.debt_increase, false);
            let debt_decrease_i257 = I257Trait::new(trove_change.debt_decrease, false);
            let debt_change_from_operation = i257Sub::sub(debt_increase_i257, debt_decrease_i257);

            let coll_increase_i257 = I257Trait::new(trove_change.coll_increase, false);
            let coll_decrease_i257 = I257Trait::new(trove_change.coll_decrease, false);
            let coll_change_from_operation = i257Sub::sub(coll_increase_i257, coll_decrease_i257);

            self
                .emit(
                    event: TroveOperation {
                        trove_id: trove_id,
                        operation: Operation::ApplyPendingDebt,
                        annual_interest_rate: self
                            .troves
                            .entry(trove_id)
                            .annual_interest_rate
                            .read(),
                        debt_increase_from_redist: trove_change.applied_redist_bit_usd_debt_gain,
                        debt_increase_from_upfront_fee: trove_change.upfront_fee,
                        debt_change_from_operation: debt_change_from_operation,
                        coll_increase_from_redist: trove_change.applied_redist_coll_gain,
                        coll_change_from_operation: coll_change_from_operation,
                    },
                );
        }

        fn on_adjust_trove_inside_batch(
            ref self: ContractState,
            trove_id: u256,
            new_trove_coll: u256,
            new_trove_debt: u256,
            trove_change: TroveChange,
            batch_address: ContractAddress,
            new_batch_coll: u256,
            new_batch_debt: u256,
        ) {
            _require_caller_is_borrower_operations(@self);

            // Trove
            self.troves.entry(trove_id).coll.write(new_trove_coll);
            _update_trove_reward_snapshots(ref self, trove_id);
            let new_stake = _update_stake_and_total_stakes(ref self, trove_id, new_trove_coll);

            // Batch
            // TODO: Below assertion is marked as to remove before deployment
            //assert(new_trove_debt > 0, 'TM: trove debt is 0');

            _update_batch_shares(
                ref self,
                trove_id,
                batch_address,
                trove_change,
                new_trove_debt,
                new_batch_coll,
                new_batch_debt,
                true,
            );

            _move_pending_trove_rewards_to_active_pool(
                ref self,
                self.liquity_base.default_pool.read(),
                trove_change.applied_redist_bit_usd_debt_gain,
                trove_change.applied_redist_coll_gain,
            );

            self
                .emit(
                    event: BatchedTroveUpdated {
                        trove_id: trove_id,
                        interest_batch_manager: batch_address,
                        batch_debt_shares: self.troves.entry(trove_id).batch_debt_shares.read(),
                        coll: new_trove_coll,
                        stake: new_stake,
                        snapshot_of_total_coll_redist: self.l_coll.read(),
                        snapshot_of_total_debt_redist: self.l_bit_usd_debt.read(),
                    },
                );

            let debt_increase_i257 = I257Trait::new(trove_change.debt_increase, false);
            let debt_decrease_i257 = I257Trait::new(trove_change.debt_decrease, false);
            let debt_change_from_operation = i257Sub::sub(debt_increase_i257, debt_decrease_i257);

            let coll_increase_i257 = I257Trait::new(trove_change.coll_increase, false);
            let coll_decrease_i257 = I257Trait::new(trove_change.coll_decrease, false);
            let coll_change_from_operation = i257Sub::sub(coll_increase_i257, coll_decrease_i257);

            self
                .emit(
                    event: TroveOperation {
                        trove_id: trove_id,
                        operation: Operation::AdjustTrove,
                        annual_interest_rate: self
                            .batches
                            .entry(batch_address)
                            .annual_interest_rate
                            .read(),
                        debt_increase_from_redist: trove_change.applied_redist_bit_usd_debt_gain,
                        debt_increase_from_upfront_fee: trove_change.upfront_fee,
                        debt_change_from_operation: debt_change_from_operation,
                        coll_increase_from_redist: trove_change.applied_redist_coll_gain,
                        coll_change_from_operation: coll_change_from_operation,
                    },
                );

            self
                .emit(
                    event: BatchUpdated {
                        interest_batch_manager: batch_address,
                        operation: BatchOperation::TroveChange,
                        debt: self.batches.entry(batch_address).debt.read(),
                        coll: self.batches.entry(batch_address).coll.read(),
                        annual_interest_rate: self
                            .batches
                            .entry(batch_address)
                            .annual_interest_rate
                            .read(),
                        annual_management_fee: self
                            .batches
                            .entry(batch_address)
                            .annual_management_fee
                            .read(),
                        total_debt_shares: self
                            .batches
                            .entry(batch_address)
                            .total_debt_shares
                            .read(),
                        // Although the Trove being adjusted may pay an upfront fee,
                        // it is an individual fee, so we don't include it here
                        debt_increase_from_upfront_fee: 0,
                    },
                );
        }

        // Send _boldamount Bold to the system and redeem the corresponding amount of collateral
        // from as many Troves as are needed to fill the redemption request.  Applies redistribution
        // gains to a Trove before reducing its debt and coll.
        // Note that if _amount is very large, this function can run out of gas, specially if
        // traversed troves are small. This can be easily avoided by splitting the total _amount in
        // appropriate chunks and calling the function multiple times.
        //
        // Param `_maxIterations` can also be provided, so the loop through Troves is capped (if
        // it’s zero, it will be ignored).This makes it easier to avoid OOG for the frontend, as
        // only knowing approximately the average cost of an iteration is enough, without needing to
        // know the “topology”
        // of the trove list. It also avoids the need to set the cap in stone in the contract, nor
        // doing gas calculations, as both gas price and opcode costs can vary.
        //
        // All Troves that are redeemed from -- with the likely exception of the last one -- will
        // end up with no debt left, and therefore in “zombie” state
        fn redeem_collateral(
            ref self: ContractState,
            msg_sender: ContractAddress,
            redeem_amount: u256,
            price: u256,
            redemption_rate: u256,
            mut max_iterations: u256,
        ) -> u256 {
            _require_caller_is_collateral_registry(@self);

            let active_pool = IActivePoolDispatcher {
                contract_address: self.liquity_base.active_pool.read(),
            };
            let sorted_troves = ISortedTrovesDispatcher {
                contract_address: self.sorted_troves.read(),
            };

            let mut totals_trove_change: TroveChange = Default::default();
            let mut vars: RedeemCollateralValues = RedeemCollateralValues {
                total_coll_fee: 0,
                remaining_bit_usd: redeem_amount,
                last_batch_updated_interest: 0.try_into().unwrap(),
                next_user_to_check: 0,
            };

            vars.remaining_bit_usd = redeem_amount;
            let mut trove: LatestTroveData = Default::default();
            let mut batch: LatestBatchData = Default::default();
            let mut single_redemption: SingleRedemptionValues = SingleRedemptionValues {
                trove_id: 0,
                batch_address: 0.try_into().unwrap(),
                bit_usd_lot: 0,
                coll_lot: 0,
                coll_fee: 0,
                applied_redist_bit_usd_debt_gain: 0,
                old_weighted_recorded_debt: 0,
                new_weighted_recorded_debt: 0,
                new_stake: 0,
                is_zombie_trove: false,
                trove: trove,
                batch: batch,
            };

            // Let’s check if there’s a pending zombie trove from previous redemption
            if (self.last_zombie_trove_id.read() != 0) {
                single_redemption.trove_id = self.last_zombie_trove_id.read();
                single_redemption.is_zombie_trove = true;
            } else {
                single_redemption.trove_id = sorted_troves.get_last();
            }
            vars.last_batch_updated_interest = 0.try_into().unwrap();

            // Get the price to use for the redemption collateral calculations
            let price_feed = IPriceFeedMockDispatcher {
                contract_address: self.liquity_base.price_feed.read(),
            };
            // Get the price to use for the redemption collateral calculations
            let (redemption_price, _) = price_feed.fetch_redemption_price();

            // Loop through the Troves starting from the one with lowest interest rate until _amount
            // of bitUSD is exchanged for collateral
            if (max_iterations == 0) {
                max_iterations = MAX_UINT256;
            }

            while (single_redemption.trove_id != 0
                && vars.remaining_bit_usd > 0
                && max_iterations > 0) {
                max_iterations = max_iterations - 1;
                // Save the uint256 of the Trove preceding the current one
                if (single_redemption.is_zombie_trove) {
                    vars.next_user_to_check = sorted_troves.get_last();
                } else {
                    vars.next_user_to_check = sorted_troves.get_prev(single_redemption.trove_id);
                }

                // Skip if ICR < 100%, to make sure that redemptions don’t decrease the CR of hit
                // Troves.
                // Use the normal price for the ICR check.
                if (_get_current_ICR(@self, single_redemption.trove_id, price) < _100PCT) {
                    single_redemption.trove_id = vars.next_user_to_check;
                    single_redemption.is_zombie_trove = false;
                    continue;
                }

                // If it’s in a batch, we need to update interest first
                // We do it here outside, to avoid repeating for each trove in the same batch
                single_redemption
                    .batch_address = _get_batch_manager(@self, single_redemption.trove_id);
                if (single_redemption.batch_address != 0.try_into().unwrap()
                    && single_redemption.batch_address != vars.last_batch_updated_interest) {
                    _update_batch_interest_prior_to_redemption(
                        ref self,
                        self.liquity_base.active_pool.read(),
                        single_redemption.batch_address,
                    );
                    vars.last_batch_updated_interest = single_redemption.batch_address;
                }

                _redeem_collateral_from_trove(
                    ref self,
                    self.liquity_base.default_pool.read(),
                    ref single_redemption,
                    vars.remaining_bit_usd,
                    redemption_price,
                    redemption_rate,
                );

                totals_trove_change.coll_decrease += single_redemption.coll_lot;
                totals_trove_change.debt_decrease += single_redemption.bit_usd_lot;
                totals_trove_change
                    .applied_redist_bit_usd_debt_gain += single_redemption
                    .applied_redist_bit_usd_debt_gain;
                // For recorded and weighted recorded debt totals, we need to capture the increases
                // and decreases, since the net debt change for a given Trove could be positive or
                // negative: redemptions decrease a Trove's recorded (and weighted recorded) debt,
                // but the accrued interest increases it.
                totals_trove_change
                    .new_weighted_recorded_debt += single_redemption
                    .new_weighted_recorded_debt;
                totals_trove_change
                    .old_weighted_recorded_debt += single_redemption
                    .old_weighted_recorded_debt;
                vars.total_coll_fee += single_redemption.coll_fee;

                vars.remaining_bit_usd -= single_redemption.bit_usd_lot;
                single_redemption.trove_id = vars.next_user_to_check;
                single_redemption.is_zombie_trove = false;
            }

            // We are removing this condition to prevent blocking redemptions
            // assert(totals.total_coll_drawn > 0, "TM: Unable to redeem any amount");

            self
                .emit(
                    event: Redemption {
                        attempted_bit_usd_amount: redeem_amount,
                        actual_bit_usd_amount: totals_trove_change.debt_decrease,
                        coll_sent: totals_trove_change.coll_decrease,
                        coll_fee: vars.total_coll_fee,
                        price: price,
                        redemption_price: redemption_price,
                    },
                );

            active_pool
                .mint_agg_interest_and_account_for_trove_change(
                    totals_trove_change, 0.try_into().unwrap(),
                );

            // Send the redeemed coll to sender
            active_pool.send_coll(msg_sender, totals_trove_change.coll_decrease);
            // We'll burn all the bold together out in the CollateralRegistry, to save gas

            totals_trove_change.debt_decrease
        }

        fn on_lower_batch_manager_annual_fee(
            ref self: ContractState,
            batch_address: ContractAddress,
            new_coll: u256,
            new_debt: u256,
            new_annual_management_fee: u256,
        ) {
            _require_caller_is_borrower_operations(@self);

            self.batches.entry(batch_address).coll.write(new_coll);
            self.batches.entry(batch_address).debt.write(new_debt);
            self
                .batches
                .entry(batch_address)
                .annual_management_fee
                .write(new_annual_management_fee);
            self.batches.entry(batch_address).last_debt_update_time.write(get_block_timestamp());

            self
                .emit(
                    event: BatchUpdated {
                        interest_batch_manager: batch_address,
                        operation: BatchOperation::LowerBatchManagerAnnualFee,
                        debt: new_debt,
                        coll: new_coll,
                        annual_interest_rate: self
                            .batches
                            .entry(batch_address)
                            .annual_interest_rate
                            .read(),
                        annual_management_fee: new_annual_management_fee,
                        total_debt_shares: self
                            .batches
                            .entry(batch_address)
                            .total_debt_shares
                            .read(),
                        debt_increase_from_upfront_fee: 0,
                    },
                );
        }

        fn urgent_redemption(
            ref self: ContractState,
            bit_usd_amount: u256,
            trove_ids: Span<u256>,
            min_collateral: u256,
        ) {
            _require_is_shutdown(@self);
            _require_amount_greather_than_zero(@self, bit_usd_amount);
            _require_bit_usd_balance_covers_redemption(
                @self, self.bit_usd_token.read(), get_caller_address(), bit_usd_amount,
            );

            let mut totals_trove_change: TroveChange = Default::default();

            // Use the standard fetchPrice here, since if branch has shut down we don't worry about
            // small redemption arbs
            let price_feed = IPriceFeedMockDispatcher {
                contract_address: self.liquity_base.price_feed.read(),
            };
            let price = price_feed.fetch_price();

            let mut remaining_bit_usd = bit_usd_amount;
            let mut i = 0;
            while (i < trove_ids.len()) {
                if (remaining_bit_usd == 0) {
                    break;
                }

                let mut trove: LatestTroveData = Default::default();
                let mut batch: LatestBatchData = Default::default();
                let mut single_redemption: SingleRedemptionValues = SingleRedemptionValues {
                    trove_id: 0,
                    batch_address: 0.try_into().unwrap(),
                    bit_usd_lot: 0,
                    coll_lot: 0,
                    coll_fee: 0,
                    applied_redist_bit_usd_debt_gain: 0,
                    old_weighted_recorded_debt: 0,
                    new_weighted_recorded_debt: 0,
                    new_stake: 0,
                    is_zombie_trove: false,
                    trove: trove,
                    batch: batch,
                };

                single_redemption.trove_id = *trove_ids.at(i);
                _get_latest_trove_data(
                    @self, single_redemption.trove_id, ref single_redemption.trove,
                );

                if (!_is_active_or_zombie(
                    self.troves.entry(single_redemption.trove_id).read().status,
                )
                    || single_redemption.trove.entire_debt == 0) {
                    continue;
                }

                // If it’s in a batch, we need to update interest first
                // As we don’t have them ordered now, we cannot avoid repeating for each trove in
                // the same batch
                single_redemption
                    .batch_address = _get_batch_manager(@self, single_redemption.trove_id);
                if (single_redemption.batch_address != 0.try_into().unwrap()) {
                    _update_batch_interest_prior_to_redemption(
                        ref self,
                        self.liquity_base.active_pool.read(),
                        single_redemption.batch_address,
                    );
                }

                _urgent_redeem_collateral_from_trove(
                    ref self,
                    self.liquity_base.default_pool.read(),
                    remaining_bit_usd,
                    price,
                    ref single_redemption,
                );

                totals_trove_change.coll_decrease += single_redemption.coll_lot;
                totals_trove_change.debt_decrease += single_redemption.bit_usd_lot;
                totals_trove_change
                    .applied_redist_bit_usd_debt_gain += single_redemption
                    .applied_redist_bit_usd_debt_gain;
                // For recorded and weighted recorded debt totals, we need to capture the increases
                // and decreases, since the net debt change for a given Trove could be positive or
                // negative: redemptions decrease a Trove's recorded (and weighted recorded) debt,
                // but the accrued interest increases it.
                totals_trove_change
                    .new_weighted_recorded_debt += single_redemption
                    .new_weighted_recorded_debt;
                totals_trove_change
                    .old_weighted_recorded_debt += single_redemption
                    .old_weighted_recorded_debt;

                remaining_bit_usd -= single_redemption.bit_usd_lot;
            }
        }

        fn on_open_trove_and_join_batch(
            ref self: ContractState,
            owner: ContractAddress,
            trove_id: u256,
            trove_change: TroveChange,
            batch_address: ContractAddress,
            batch_coll: u256,
            batch_debt: u256,
        ) {
            _require_caller_is_borrower_operations(@self);
            // assert(batchIds[batches[_batchAddress].arrayIndex] == _batchAddress);

            let new_stake = _compute_new_stake(@self, trove_change.coll_increase);

            self.troves.entry(trove_id).coll.write(trove_change.coll_increase);
            self.troves.entry(trove_id).stake.write(new_stake);
            self.troves.entry(trove_id).status.write(Status::Active);
            self.troves.entry(trove_id).array_index.write(self.trove_ids.len().try_into().unwrap());
            self.troves.entry(trove_id).interest_batch_manager.write(batch_address);
            self.troves.entry(trove_id).last_interest_rate_adj_time.write(get_block_timestamp());

            _update_trove_reward_snapshots(ref self, trove_id);

            // Push the trove's id to the Trove list
            self.trove_ids.push(trove_id);

            // TODO: Remove before deployment (comment from Liquity code), about the below line ??
            //assert(trove_change.debt_increase > 0, 'TM: debt increase must be > 0');
            _update_batch_shares(
                ref self,
                trove_id,
                batch_address,
                trove_change,
                trove_change.debt_increase,
                batch_coll,
                batch_debt,
                true,
            );

            let new_total_stakes = self.total_stakes.read() + new_stake;
            self.total_stakes.write(new_total_stakes);

            // Mint ERC721
            let trove_nft = ITroveNFTDispatcher { contract_address: self.trove_nft.read() };
            trove_nft.mint(owner, trove_id);

            self
                .emit(
                    event: BatchedTroveUpdated {
                        trove_id: trove_id,
                        interest_batch_manager: batch_address,
                        batch_debt_shares: self.troves.entry(trove_id).read().batch_debt_shares,
                        coll: trove_change.coll_increase,
                        stake: new_stake,
                        snapshot_of_total_coll_redist: self.l_coll.read(),
                        snapshot_of_total_debt_redist: self.l_bit_usd_debt.read(),
                    },
                );

            self
                .emit(
                    event: TroveOperation {
                        trove_id: trove_id,
                        operation: Operation::OpenTroveAndJoinBatch,
                        annual_interest_rate: self
                            .batches
                            .entry(batch_address)
                            .annual_interest_rate
                            .read(),
                        debt_increase_from_redist: 0,
                        debt_increase_from_upfront_fee: trove_change.upfront_fee,
                        debt_change_from_operation: I257Trait::new(
                            trove_change.debt_increase, false,
                        ),
                        coll_increase_from_redist: 0,
                        coll_change_from_operation: I257Trait::new(
                            trove_change.coll_increase, false,
                        ),
                    },
                );

            self
                .emit(
                    event: BatchUpdated {
                        interest_batch_manager: batch_address,
                        operation: BatchOperation::JoinBatch,
                        debt: self.batches.entry(batch_address).debt.read(),
                        coll: self.batches.entry(batch_address).coll.read(),
                        annual_interest_rate: self
                            .batches
                            .entry(batch_address)
                            .annual_interest_rate
                            .read(),
                        annual_management_fee: self
                            .batches
                            .entry(batch_address)
                            .annual_management_fee
                            .read(),
                        total_debt_shares: self
                            .batches
                            .entry(batch_address)
                            .total_debt_shares
                            .read(),
                        // Although the Trove joining the batch pays an upfront fee,
                        // it is an individual fee, so we don't include it here
                        debt_increase_from_upfront_fee: 0,
                    },
                );
        }

        fn set_trove_status_to_active(ref self: ContractState, trove_id: u256) {
            _require_caller_is_borrower_operations(@self);
            self.troves.entry(trove_id).status.write(Status::Active);
            if (self.last_zombie_trove_id.read() == trove_id) {
                self.last_zombie_trove_id.write(0);
            }
        }

        fn on_adjust_trove_interest_rate(
            ref self: ContractState,
            trove_id: u256,
            new_coll: u256,
            new_debt: u256,
            new_annual_interest_rate: u256,
            trove_change: TroveChange,
        ) {
            _require_caller_is_borrower_operations(@self);
            self.troves.entry(trove_id).coll.write(new_coll);
            self.troves.entry(trove_id).debt.write(new_debt);
            self.troves.entry(trove_id).annual_interest_rate.write(new_annual_interest_rate);
            self.troves.entry(trove_id).last_debt_update_time.write(get_block_timestamp());
            self.troves.entry(trove_id).last_interest_rate_adj_time.write(get_block_timestamp());

            _move_pending_trove_rewards_to_active_pool(
                ref self,
                self.liquity_base.default_pool.read(),
                trove_change.applied_redist_bit_usd_debt_gain,
                trove_change.applied_redist_coll_gain,
            );
            _update_trove_reward_snapshots(ref self, trove_id);

            self
                .emit(
                    event: TroveUpdated {
                        trove_id: trove_id,
                        debt: new_debt,
                        coll: new_coll,
                        stake: self.troves.entry(trove_id).stake.read(),
                        annual_interest_rate: new_annual_interest_rate,
                        snapshot_of_total_coll_redist: self.l_coll.read(),
                        snapshot_of_total_debt_redist: self.l_bit_usd_debt.read(),
                    },
                );

            self
                .emit(
                    event: TroveOperation {
                        trove_id: trove_id,
                        operation: Operation::AdjustTroveInterestRate,
                        annual_interest_rate: new_annual_interest_rate,
                        debt_increase_from_redist: trove_change.applied_redist_bit_usd_debt_gain,
                        debt_increase_from_upfront_fee: trove_change.upfront_fee,
                        debt_change_from_operation: I257Trait::new(0, false),
                        coll_increase_from_redist: trove_change.applied_redist_coll_gain,
                        coll_change_from_operation: I257Trait::new(0, false),
                    },
                );
        }

        fn on_adjust_trove(
            ref self: ContractState,
            trove_id: u256,
            new_coll: u256,
            new_debt: u256,
            trove_change: TroveChange,
        ) {
            _require_caller_is_borrower_operations(@self);
            self.troves.entry(trove_id).coll.write(new_coll);
            self.troves.entry(trove_id).debt.write(new_debt);
            self.troves.entry(trove_id).last_debt_update_time.write(get_block_timestamp());

            _move_pending_trove_rewards_to_active_pool(
                ref self,
                self.liquity_base.default_pool.read(),
                trove_change.applied_redist_bit_usd_debt_gain,
                trove_change.applied_redist_coll_gain,
            );
            let new_stake = _update_stake_and_total_stakes(ref self, trove_id, new_coll);
            _update_trove_reward_snapshots(ref self, trove_id);

            self
                .emit(
                    event: TroveUpdated {
                        trove_id: trove_id,
                        debt: new_debt,
                        coll: new_coll,
                        stake: new_stake,
                        annual_interest_rate: self
                            .troves
                            .entry(trove_id)
                            .annual_interest_rate
                            .read(),
                        snapshot_of_total_coll_redist: self.l_coll.read(),
                        snapshot_of_total_debt_redist: self.l_bit_usd_debt.read(),
                    },
                );

            let debt_increase_i257 = I257Trait::new(trove_change.debt_increase, false);
            let debt_decrease_i257 = I257Trait::new(trove_change.debt_decrease, false);
            let debt_change_from_operation = i257Sub::sub(debt_increase_i257, debt_decrease_i257);

            let coll_increase_i257 = I257Trait::new(trove_change.coll_increase, false);
            let coll_decrease_i257 = I257Trait::new(trove_change.coll_decrease, false);
            let coll_change_from_operation = i257Sub::sub(coll_increase_i257, coll_decrease_i257);

            self
                .emit(
                    event: TroveOperation {
                        trove_id: trove_id,
                        operation: Operation::AdjustTrove,
                        annual_interest_rate: self
                            .troves
                            .entry(trove_id)
                            .annual_interest_rate
                            .read(),
                        debt_increase_from_redist: trove_change.applied_redist_bit_usd_debt_gain,
                        debt_increase_from_upfront_fee: trove_change.upfront_fee,
                        debt_change_from_operation: debt_change_from_operation,
                        coll_increase_from_redist: trove_change.applied_redist_coll_gain,
                        coll_change_from_operation: coll_change_from_operation,
                    },
                );
        }

        fn on_close_trove(
            ref self: ContractState,
            trove_id: u256,
            trove_change: TroveChange,
            batch_address: ContractAddress,
            new_batch_coll: u256,
            new_batch_debt: u256,
        ) {
            _require_caller_is_borrower_operations(@self);
            _close_trove(
                ref self,
                trove_id,
                trove_change,
                batch_address,
                new_batch_coll,
                new_batch_debt,
                Status::ClosedByOwner,
            );
            _move_pending_trove_rewards_to_active_pool(
                ref self,
                self.liquity_base.default_pool.read(),
                trove_change.applied_redist_bit_usd_debt_gain,
                trove_change.applied_redist_coll_gain,
            );

            self
                .emit(
                    event: TroveUpdated {
                        trove_id: trove_id,
                        debt: 0,
                        coll: 0,
                        stake: 0,
                        annual_interest_rate: 0,
                        snapshot_of_total_coll_redist: 0,
                        snapshot_of_total_debt_redist: 0,
                    },
                );

            let debt_increase_i257 = I257Trait::new(trove_change.debt_increase, false);
            let debt_decrease_i257 = I257Trait::new(trove_change.debt_decrease, false);
            let debt_change_from_operation = i257Sub::sub(debt_increase_i257, debt_decrease_i257);

            let coll_increase_i257 = I257Trait::new(trove_change.coll_increase, false);
            let coll_decrease_i257 = I257Trait::new(trove_change.coll_decrease, false);
            let coll_change_from_operation = i257Sub::sub(coll_increase_i257, coll_decrease_i257);

            self
                .emit(
                    event: TroveOperation {
                        trove_id: trove_id,
                        operation: Operation::CloseTrove,
                        annual_interest_rate: 0,
                        debt_increase_from_redist: trove_change.applied_redist_bit_usd_debt_gain,
                        debt_increase_from_upfront_fee: trove_change.upfront_fee,
                        debt_change_from_operation: debt_change_from_operation,
                        coll_increase_from_redist: trove_change.applied_redist_coll_gain,
                        coll_change_from_operation: coll_change_from_operation,
                    },
                );

            if (batch_address != 0.try_into().unwrap()) {
                self
                    .emit(
                        event: BatchUpdated {
                            interest_batch_manager: batch_address,
                            operation: BatchOperation::ExitBatch,
                            debt: self.batches.entry(batch_address).debt.read(),
                            coll: self.batches.entry(batch_address).coll.read(),
                            annual_interest_rate: self
                                .batches
                                .entry(batch_address)
                                .annual_interest_rate
                                .read(),
                            annual_management_fee: self
                                .batches
                                .entry(batch_address)
                                .annual_management_fee
                                .read(),
                            total_debt_shares: self
                                .batches
                                .entry(batch_address)
                                .total_debt_shares
                                .read(),
                            debt_increase_from_upfront_fee: 0,
                        },
                    );
            }
        }

        fn on_set_batch_manager_annual_interest_rate(
            ref self: ContractState,
            batch_address: ContractAddress,
            new_coll: u256,
            new_debt: u256,
            new_annual_interest_rate: u256,
            upfront_fee: u256,
        ) {
            _require_caller_is_borrower_operations(@self);

            self.batches.entry(batch_address).coll.write(new_coll);
            self.batches.entry(batch_address).debt.write(new_debt);
            self.batches.entry(batch_address).annual_interest_rate.write(new_annual_interest_rate);
            self.batches.entry(batch_address).last_debt_update_time.write(get_block_timestamp());
            self
                .batches
                .entry(batch_address)
                .last_interest_rate_adj_time
                .write(get_block_timestamp());

            self
                .emit(
                    event: BatchUpdated {
                        interest_batch_manager: batch_address,
                        operation: BatchOperation::SetBatchManagerAnnualInterestRate,
                        debt: new_debt,
                        coll: new_coll,
                        annual_interest_rate: new_annual_interest_rate,
                        annual_management_fee: self
                            .batches
                            .entry(batch_address)
                            .annual_management_fee
                            .read(),
                        total_debt_shares: self
                            .batches
                            .entry(batch_address)
                            .total_debt_shares
                            .read(),
                        debt_increase_from_upfront_fee: upfront_fee,
                    },
                );
        }

        fn on_register_batch_manager(
            ref self: ContractState,
            account: ContractAddress,
            annual_interest_rate: u256,
            annual_management_fee: u256,
        ) {
            _require_caller_is_borrower_operations(@self);

            self.batches.entry(account).array_index.write(self.batch_ids.len());
            self.batches.entry(account).annual_interest_rate.write(annual_interest_rate);
            self.batches.entry(account).annual_management_fee.write(annual_management_fee);
            self.batches.entry(account).last_interest_rate_adj_time.write(get_block_timestamp());

            self.batch_ids.push(account);

            self
                .emit(
                    event: BatchUpdated {
                        interest_batch_manager: account,
                        operation: BatchOperation::RegisterBatchManager,
                        debt: 0,
                        coll: 0,
                        annual_interest_rate: annual_interest_rate,
                        annual_management_fee: annual_management_fee,
                        total_debt_shares: 0,
                        debt_increase_from_upfront_fee: 0,
                    },
                );
        }
    }

    ////////////////////////////////////////////////////////////////
    //                     ACCESS FUNCTIONS                       //
    ////////////////////////////////////////////////////////////////

    fn _require_caller_is_borrower_operations(self: @ContractState) {
        assert(get_caller_address() == self.borrower_operations.read(), 'TM: caller is not BO');
    }

    fn _require_caller_is_collateral_registry(self: @ContractState) {
        assert(get_caller_address() == self.collateral_registry.read(), 'TM: caller is not CR');
    }

    fn _require_is_shutdown(self: @ContractState) {
        assert(self.shutdown_time.read() != 0, 'TM: not shutdown');
    }

    ////////////////////////////////////////////////////////////////
    //                     INTERNAL FUNCTIONS                     //
    ////////////////////////////////////////////////////////////////

    // Liquidate one Trove.
    fn _liquidate(
        ref self: ContractState,
        default_pool: ContractAddress,
        trove_id: u256,
        bit_usd_in_SP_for_offsets: u256,
        price: u256,
        ref trove: LatestTroveData,
        ref single_liquidation: LiquidationValues,
    ) {
        let trove_nft_address = self.trove_nft.read();
        let trove_nft = ITroveNFTDispatcher { contract_address: trove_nft_address };

        let trove_owner = trove_nft.get_trove_owner(trove_id);

        _get_latest_trove_data(@self, trove_id, ref trove);
        let batch_address = _get_batch_manager(@self, trove_id);
        let is_trove_in_batch = batch_address != 0.try_into().unwrap();

        let mut batch: LatestBatchData = Default::default();

        if (is_trove_in_batch) {
            _get_latest_batch_data(@self, batch_address, ref batch);
        }

        _move_pending_trove_rewards_to_active_pool(
            ref self, default_pool, trove.redist_bit_usd_debt_gain, trove.redist_coll_gain,
        );

        let (
            debt_to_offset,
            coll_to_send_so_SP,
            coll_gas_compensation,
            debt_to_redistribute,
            coll_to_redistribute,
            coll_surplus,
        ) =
            _get_offset_and_redistribution_vals(
            @self, trove.entire_debt, trove.entire_coll, bit_usd_in_SP_for_offsets, price,
        );
        single_liquidation.debt_to_offset = debt_to_offset;
        single_liquidation.coll_to_send_to_SP = coll_to_send_so_SP;
        single_liquidation.coll_gas_compensation = coll_gas_compensation;
        single_liquidation.debt_to_redistribute = debt_to_redistribute;
        single_liquidation.coll_to_redistribute = coll_to_redistribute;
        single_liquidation.coll_surplus = coll_surplus;

        let mut trove_change: TroveChange = Default::default();
        trove_change.coll_decrease = trove.entire_coll;
        trove_change.debt_decrease = trove.entire_debt;
        trove_change.applied_redist_coll_gain = trove.redist_coll_gain;
        trove_change.applied_redist_bit_usd_debt_gain = trove.redist_bit_usd_debt_gain;

        _close_trove(
            ref self,
            trove_id,
            trove_change,
            batch_address,
            batch.entire_coll_without_redistribution,
            batch.entire_debt_without_redistribution,
            Status::ClosedByLiquidation,
        );

        if (is_trove_in_batch) {
            single_liquidation.old_weighted_recorded_debt = batch.weighted_recorded_debt
                + (trove.entire_debt - trove.redist_bit_usd_debt_gain) * batch.annual_interest_rate;
            single_liquidation.new_weighted_recorded_debt = batch.entire_debt_without_redistribution
                * batch.annual_interest_rate;
            // Mint batch management fee
            trove_change.batch_accrued_management_fee = batch.accrued_management_fee;
            trove_change
                .old_weighted_recorded_batch_management_fee = batch
                .weighted_recorded_batch_management_fee
                + (trove.entire_debt - trove.redist_bit_usd_debt_gain)
                    * batch.annual_management_fee;
            trove_change
                .new_weighted_recorded_batch_management_fee = batch
                .entire_debt_without_redistribution
                * batch.annual_management_fee;
            let active_pool = IActivePoolDispatcher {
                contract_address: self.liquity_base.active_pool.read(),
            };
            active_pool
                .mint_batch_management_fee_and_account_for_change(trove_change, batch_address);
        } else {
            single_liquidation.old_weighted_recorded_debt = trove.weighted_recorded_debt;
        }

        // Differencen between liquidation penalty and liquidation threshold
        if (single_liquidation.coll_surplus > 0) {
            let coll_surplus_pool = ICollSurplusPoolDispatcher {
                contract_address: self.coll_surplus_pool.read(),
            };
            coll_surplus_pool.account_surplus(trove_owner, single_liquidation.coll_surplus);
        }

        // Wipe out state in BO
        let borrower_operations = IBorrowerOperationsDispatcher {
            contract_address: self.borrower_operations.read(),
        };
        borrower_operations.on_liquidate_trove(trove_id);

        self
            .emit(
                event: TroveUpdated {
                    trove_id: trove_id,
                    debt: 0,
                    coll: 0,
                    stake: 0,
                    annual_interest_rate: 0,
                    snapshot_of_total_coll_redist: 0,
                    snapshot_of_total_debt_redist: 0,
                },
            );

        self
            .emit(
                event: TroveOperation {
                    trove_id: trove_id,
                    operation: Operation::Liquidate,
                    annual_interest_rate: 0,
                    debt_increase_from_redist: trove.redist_bit_usd_debt_gain,
                    debt_increase_from_upfront_fee: 0,
                    debt_change_from_operation: i257Neg::neg(
                        I257Trait::new(trove.entire_debt, false),
                    ),
                    coll_increase_from_redist: trove.redist_coll_gain,
                    coll_change_from_operation: i257Neg::neg(
                        I257Trait::new(trove.entire_coll, false),
                    ),
                },
            );

        if (is_trove_in_batch) {
            self
                .emit(
                    event: BatchUpdated {
                        interest_batch_manager: batch_address,
                        operation: BatchOperation::ExitBatch,
                        debt: self.batches.entry(batch_address).read().debt,
                        coll: self.batches.entry(batch_address).read().coll,
                        annual_interest_rate: batch.annual_interest_rate,
                        annual_management_fee: batch.annual_management_fee,
                        total_debt_shares: self
                            .batches
                            .entry(batch_address)
                            .read()
                            .total_debt_shares,
                        debt_increase_from_upfront_fee: 0,
                    },
                );
        }
    }

    // Redeem as much collateral as possible from _borrower's Trove in exchange for bitUSD up to
    // _maxBitUSDamount
    fn _redeem_collateral_from_trove(
        ref self: ContractState,
        default_pool: ContractAddress,
        ref single_redemption: SingleRedemptionValues,
        max_bit_usd_amount: u256,
        redemption_price: u256,
        redemption_rate: u256,
    ) {
        _get_latest_trove_data(@self, single_redemption.trove_id, ref single_redemption.trove);
        // Determine the remaining amount (lot) to be redeemed, capped by the entire debt of the
        // Trove
        single_redemption
            .bit_usd_lot = min(max_bit_usd_amount, single_redemption.trove.entire_debt);
        // Get the amount of Coll equal in USD value to the boldLot redeemed
        let corresponding_coll = single_redemption.bit_usd_lot
            * DECIMAL_PRECISION
            / redemption_price;
        // Calculate the collFee separately (for events)
        single_redemption.coll_fee = corresponding_coll * redemption_rate / DECIMAL_PRECISION;
        // Get the final collLot to send to redeemer, leaving the fee in the Trove
        single_redemption.coll_lot = corresponding_coll - single_redemption.coll_fee;

        let ZERO_ADDRESS: ContractAddress = 0.try_into().unwrap();
        let is_trove_in_batch: bool = single_redemption.batch_address != ZERO_ADDRESS;
        let new_debt = _apply_single_redemption(
            ref self, default_pool, ref single_redemption, is_trove_in_batch,
        );

        // Make Trove zombie if it's tiny (and it wasn’t already), in order to prevent griefing
        // future (normal, sequential) redemptions
        let sorted_troves = ISortedTrovesDispatcher { contract_address: self.sorted_troves.read() };
        if (new_debt < MIN_DEBT) {
            if (!single_redemption.is_zombie_trove) {
                self.troves.entry(single_redemption.trove_id).status.write(Status::Zombie);
                if (is_trove_in_batch) {
                    sorted_troves.remove_from_batch(single_redemption.trove_id);
                } else {
                    sorted_troves.remove(single_redemption.trove_id);
                }
                // If it’s a partial redemption, let’s store a pointer to it so it’s used
                // first in the next one
                if (new_debt > 0) {
                    self.last_zombie_trove_id.write(single_redemption.trove_id);
                }
            } else if (new_debt == 0) {
                // Reset last zombie trove pointer if the previous one was fully redeemed now
                self.last_zombie_trove_id.write(0);
            }
        }
        // Note: technically, it could happen that the Trove pointed to by `lastZombieTroveId` ends
    // up with newDebt >= MIN_DEBT thanks to bitUSD debt redistribution, which means it _could_
    // be made active again, however we don't do that here, as it would require hints for
    // re-insertion into `SortedTroves`.
    }

    fn _update_batch_interest_prior_to_redemption(
        ref self: ContractState, active_pool: ContractAddress, batch_address: ContractAddress,
    ) {
        let mut batch: LatestBatchData = Default::default();
        _get_latest_batch_data(@self, batch_address, ref batch);
        self.batches.entry(batch_address).debt.write(batch.entire_debt_without_redistribution);
        self.batches.entry(batch_address).last_debt_update_time.write(get_block_timestamp());
        // As we are updating the batch, we update the ActivePool weighted sum too
        let mut batch_trove_change: TroveChange = Default::default();
        batch_trove_change.old_weighted_recorded_debt = batch.weighted_recorded_debt;
        batch_trove_change.new_weighted_recorded_debt = batch.entire_debt_without_redistribution
            * batch.annual_interest_rate;

        batch_trove_change.batch_accrued_management_fee = batch.accrued_management_fee;
        batch_trove_change
            .old_weighted_recorded_batch_management_fee = batch
            .weighted_recorded_batch_management_fee;
        batch_trove_change
            .new_weighted_recorded_batch_management_fee = batch
            .entire_debt_without_redistribution
            * batch.annual_management_fee;

        let active_pool = IActivePoolDispatcher { contract_address: active_pool };
        active_pool
            .mint_agg_interest_and_account_for_trove_change(batch_trove_change, batch_address);
    }

    // Updates snapshots of system total stakes and total collateral, excluding a given collateral
    // remainder from the calculation.
    // Used in a liquidation sequence.
    fn _update_system_snapshots_exclude_coll_remainder(
        ref self: ContractState, active_pool: ContractAddress, coll_remainder: u256,
    ) {
        self.total_stakes_snapshot.write(self.total_stakes.read());
        let active_pool = IActivePoolDispatcher { contract_address: active_pool };
        let default_pool = IDefaultPoolDispatcher {
            contract_address: self.liquity_base.default_pool.read(),
        };
        let active_coll = active_pool.get_coll_balance();
        let liquidated_coll = default_pool.get_coll_balance();
        self.total_collateral_snapshot.write(active_coll - coll_remainder + liquidated_coll);
    }

    fn _redistribute_debt_and_coll(
        ref self: ContractState,
        active_pool: ContractAddress,
        default_pool: ContractAddress,
        debt_to_redistribute: u256,
        coll_to_redistribute: u256,
    ) {
        if (debt_to_redistribute == 0) {
            return; // Otherwise _collToRedistribute > 0 too
        }

        // Add distributed coll and debt rewards-per-unit-staked to the running totals. Division
        // uses a "feedback"
        // error correction, to keep the cumulative error low in the running totals L_coll and
        // L_boldDebt:
        // 1) Form numerators which compensate for the floor division errors that occurred the last
        // time this function was called.
        // 2) Calculate "per-unit-staked" ratios.
        // 3) Multiply each ratio back by its denominator, to reveal the current floor division
        // error.
        // 4) Store these errors for use in the next correction when this function is called.
        // 5) Note: static analysis tools complain about this "division before multiplication",
        // however, it is intended.
        let coll_numerator = coll_to_redistribute * DECIMAL_PRECISION
            + self.last_coll_error_redistribution.read();
        let bit_usd_debt_numerator = debt_to_redistribute * DECIMAL_PRECISION
            + self.last_bit_usd_debt_error_redistribution.read();

        // Get the per-unit-staked terms
        let total_stakes = self.total_stakes.read();
        let coll_reward_per_unit_staked = coll_numerator / total_stakes;
        let bit_usd_debt_reward_per_unit_staked = bit_usd_debt_numerator / total_stakes;

        self
            .last_coll_error_redistribution
            .write(coll_numerator - coll_reward_per_unit_staked * total_stakes);
        self
            .last_bit_usd_debt_error_redistribution
            .write(bit_usd_debt_numerator - bit_usd_debt_reward_per_unit_staked * total_stakes);

        // Add per-unit-staked terms to the running totals
        self.l_coll.write(self.l_coll.read() + coll_reward_per_unit_staked);
        self.l_bit_usd_debt.write(self.l_bit_usd_debt.read() + bit_usd_debt_reward_per_unit_staked);

        let default_pool = IDefaultPoolDispatcher { contract_address: default_pool };
        let active_pool = IActivePoolDispatcher { contract_address: active_pool };
        default_pool.increase_bit_usd_debt(debt_to_redistribute);
        active_pool.send_coll_to_default_pool(coll_to_redistribute);
    }

    fn _update_trove_reward_snapshots(ref self: ContractState, trove_id: u256) {
        self.reward_snapshots.entry(trove_id).coll.write(self.l_coll.read());
        self.reward_snapshots.entry(trove_id).bit_usd_debt.write(self.l_bit_usd_debt.read());
    }

    fn _batch_liquidate_troves(
        ref self: ContractState,
        default_pool: ContractAddress,
        price: u256,
        bit_usd_in_SP_for_offsets: u256,
        trove_array: Span<u256>,
        ref totals: LiquidationValues,
        ref trove_change: TroveChange,
    ) {
        let mut remaining_bit_usd_in_SP_for_offsets = bit_usd_in_SP_for_offsets;

        let mut i = 0;
        let array_length = trove_array.len();
        while i < array_length {
            let trove_id = trove_array[i];
            let status: Status = self.troves.read(*trove_id).status;
            if (!_isActiveOrZombie(status)) {
                continue;
            }

            let ICR = _get_current_ICR(@self, *trove_id, price);

            if (ICR < self.MCR.read()) {
                let mut single_liquidation: LiquidationValues = Default::default();
                let mut trove: LatestTroveData = Default::default();

                _liquidate(
                    ref self,
                    default_pool,
                    *trove_id,
                    remaining_bit_usd_in_SP_for_offsets,
                    price,
                    ref trove,
                    ref single_liquidation,
                );
                remaining_bit_usd_in_SP_for_offsets -= single_liquidation.debt_to_offset;

                // Add liquidation values to their respective totals
                _add_liquidation_values_to_totals(
                    ref self, ref trove, single_liquidation, ref totals, ref trove_change,
                );
            }
        }
    }

    fn _send_gas_compensation(
        ref self: ContractState,
        active_pool: ContractAddress,
        liquidator: ContractAddress,
        eth: u256,
        coll: u256,
    ) {
        if (eth > 0) {
            let ETH = IERC20Dispatcher { contract_address: self.ETH.read() };
            ETH.transfer_from(self.gas_pool.read(), liquidator, eth);
        }
        if (coll > 0) {
            let active_pool = IActivePoolDispatcher { contract_address: active_pool };
            active_pool.send_coll(liquidator, coll);
        }
    }

    fn _add_liquidation_values_to_totals(
        ref self: ContractState,
        ref trove: LatestTroveData,
        single_liquidation: LiquidationValues,
        ref totals: LiquidationValues,
        ref trove_change: TroveChange,
    ) {
        // Tally all the values with their respective running totals
        totals.coll_gas_compensation += single_liquidation.coll_gas_compensation;
        totals.eth_gas_compensation += ETH_GAS_COMPENSATION;
        trove_change.debt_decrease += trove.entire_debt;
        trove_change.coll_decrease += trove.entire_coll;
        trove_change.applied_redist_bit_usd_debt_gain += trove.redist_bit_usd_debt_gain;
        trove_change.old_weighted_recorded_debt += single_liquidation.old_weighted_recorded_debt;
        trove_change.new_weighted_recorded_debt += single_liquidation.new_weighted_recorded_debt;
        totals.debt_to_offset += single_liquidation.debt_to_offset;
        totals.coll_to_send_to_SP += single_liquidation.coll_to_send_to_SP;
        totals.debt_to_redistribute += single_liquidation.debt_to_redistribute;
        totals.coll_to_redistribute += single_liquidation.coll_to_redistribute;
        totals.coll_surplus += single_liquidation.coll_surplus;
    }

    fn _isActiveOrZombie(status: Status) -> bool {
        match status {
            Status::Active => true,
            Status::Zombie => true,
            _ => false,
        }
    }

    // Return the current collateral ratio (ICR) of a given Trove. Takes a trove's pending coll and
    // debt rewards from redistributions into account.
    fn _get_current_ICR(self: @ContractState, trove_id: u256, price: u256) -> u256 {
        let mut trove: LatestTroveData = Default::default();
        _get_latest_trove_data(self, trove_id, ref trove);
        math_lib::compute_cr(trove.entire_coll, trove.entire_debt, price)
    }

    fn _close_trove(
        ref self: ContractState,
        trove_id: u256,
        trove_change: TroveChange,
        batch_address: ContractAddress,
        new_batch_coll: u256,
        new_batch_debt: u256,
        closed_status: Status,
    ) {
        // assert(closedStatus == Status.closedByLiquidation || closedStatus ==
        // Status.closedByOwner);
        let trove_ids_array_length = self.trove_ids.len();
        // If branch has not been shut down, or it's a liquidation,
        // require at least 1 trove in the system
        // TODO: Double check use of match here.
        let is_closed_by_liquidation = match closed_status {
            Status::ClosedByLiquidation => true,
            _ => false,
        };

        if (self.shutdown_time.read() == 0 || is_closed_by_liquidation) {
            _require_more_than_one_trove_in_system(trove_ids_array_length);
        }

        _remove_trove_id(ref self, trove_id, trove_ids_array_length);

        let trove: Trove = self.troves.read(trove_id);

        let sorted_troves = ISortedTrovesDispatcher { contract_address: self.sorted_troves.read() };

        // If trove belongs to a batch, remove from it
        if (batch_address != 0.try_into().unwrap()) {
            if (trove.status == Status::Active) {
                sorted_troves.remove_from_batch(trove_id);
            } else if (trove.status == Status::Zombie
                && self.last_zombie_trove_id.read() == trove_id) {
                self.last_zombie_trove_id.write(0);
            }
            _remove_trove_shares_from_batch(
                ref self,
                trove_id,
                trove_change.coll_decrease,
                trove_change.debt_decrease,
                trove_change,
                batch_address,
                new_batch_coll,
                new_batch_debt,
            );
        } else {
            if (trove.status == Status::Active) {
                sorted_troves.remove(trove_id);
            } else if (trove.status == Status::Zombie
                && self.last_zombie_trove_id.read() == trove_id) {
                self.last_zombie_trove_id.write(0);
            }
        }

        let new_total_stakes = self.total_stakes.read() - trove.stake;
        self.total_stakes.write(new_total_stakes);

        // Zero Trove properties
        let zero_trove: Trove = Trove {
            debt: 0,
            coll: 0,
            stake: 0,
            status: Status::NonExistent,
            array_index: 0,
            last_debt_update_time: 0,
            last_interest_rate_adj_time: 0,
            annual_interest_rate: 0,
            interest_batch_manager: 0.try_into().unwrap(),
            batch_debt_shares: 0,
        };
        self.troves.entry(trove_id).write(zero_trove);

        // Zero Trove snapshots
        let zero_snapshot: RewardSnapshots = Default::default();
        self.reward_snapshots.entry(trove_id).write(zero_snapshot);

        // Burn ERC721
        let trove_nft = ITroveNFTDispatcher { contract_address: self.trove_nft.read() };
        trove_nft.burn(trove_id);
    }

    // new_trove_coll : entire, with redistribution
    // new_trove_debt : entire, with interest, batch fee and redistribution
    // new_batch_coll : without trove_change
    // new_batch_debt : entire (with interest and batch fee), but without trove change
    fn _remove_trove_shares_from_batch(
        ref self: ContractState,
        trove_id: u256,
        new_trove_coll: u256,
        new_trove_debt: u256,
        trove_change: TroveChange,
        batch_address: ContractAddress,
        new_batch_coll: u256,
        new_batch_debt: u256,
    ) {
        // As we are removing:
        // assert(_newBatchDebt > 0 || _newBatchColl > 0);

        let mut trove: Trove = self.troves.read(trove_id);
        // We don’t need to increase the shares corresponding to redistribution first, because
        // they would be subtracted immediately after We don’t need to account for interest nor
        // batch fee because it’s proportional to debt shares
        let batch_debt_decrease = new_trove_debt
            - trove_change.upfront_fee
            - trove_change.applied_redist_bit_usd_debt_gain;
        let batch_coll_decrease = new_trove_coll - trove_change.applied_redist_coll_gain;

        let mut batch: Batch = self.batches.read(batch_address);
        batch.total_debt_shares -= trove.batch_debt_shares;
        batch.debt = new_batch_debt - batch_debt_decrease;
        batch.coll = new_batch_coll - batch_coll_decrease;
        batch.last_debt_update_time = get_block_timestamp();

        self.batches.entry(batch_address).write(batch);

        trove.interest_batch_manager = 0.try_into().unwrap();
        trove.batch_debt_shares = 0;

        self.troves.entry(trove_id).write(trove);
    }

    // In a full liquidation, returns the values for a trove's coll and debt to be offset, and coll
    // and debt to be redistributed to active troves.
    fn _get_offset_and_redistribution_vals(
        self: @ContractState,
        entire_trove_debt: u256,
        entire_trove_coll: u256,
        bit_usd_in_SP_for_offsets: u256,
        price: u256,
    ) -> (u256, u256, u256, u256, u256, u256) {
        let mut coll_SP_portion = 0;
        // Offset as much debt & collateral as possible against the Stability Pool, and redistribute
        // the remainder between all active troves.
        // If the trove's debt is larger than the deposited BitUSD in the Stability Pool:
        // - Offset an amount of the trove's debt equal to the Bold in the Stability Pool
        // - Send a fraction of the trove's collateral to the Stability Pool, equal to the fraction
        // of its offset debt

        let mut debt_to_offset: u256 = 0;
        let mut coll_to_send_to_SP: u256 = 0;
        let mut coll_gas_compensation: u256 = 0;
        let mut debt_to_redistribute: u256 = 0;
        let mut coll_to_redistribute: u256 = 0;
        let mut coll_surplus: u256 = 0;

        if (bit_usd_in_SP_for_offsets > 0) {
            debt_to_offset = min(entire_trove_debt, bit_usd_in_SP_for_offsets);
            coll_SP_portion = entire_trove_coll * debt_to_offset / entire_trove_debt;

            coll_gas_compensation = _get_coll_gas_compensation(self, coll_SP_portion);
            let coll_to_offset = coll_SP_portion - coll_gas_compensation;
            let (coll_to_send_to_SP_, coll_surplus_) = _get_coll_penalty_and_surplus(
                self, coll_to_offset, debt_to_offset, self.liquidation_penalty_SP.read(), price,
            );
            coll_to_send_to_SP = coll_to_send_to_SP_;
            coll_surplus = coll_surplus_;
        }

        // Redistribution
        debt_to_redistribute = entire_trove_debt - debt_to_offset;
        if (debt_to_redistribute > 0) {
            let coll_redistribution_portion = entire_trove_coll - coll_SP_portion;
            if (coll_redistribution_portion > 0) {
                let (coll_to_redistribute_, coll_surplus_) = _get_coll_penalty_and_surplus(
                    self,
                    coll_redistribution_portion + coll_surplus,
                    debt_to_redistribute,
                    self.liquidation_penalty_redistribution.read(),
                    price,
                );
                coll_to_redistribute = coll_to_redistribute_;
                coll_surplus = coll_surplus_ + coll_surplus_;
            }
        }
        // assert(_collToLiquidate == collToSendToSP + collToRedistribute + collSurplus);
        (
            debt_to_offset,
            coll_to_send_to_SP,
            coll_gas_compensation,
            debt_to_redistribute,
            coll_to_redistribute,
            coll_surplus,
        )
    }

    fn _apply_single_redemption(
        ref self: ContractState,
        default_pool_address: ContractAddress,
        ref single_redemption: SingleRedemptionValues,
        is_trove_in_batch: bool,
    ) -> u256 {
        // Decrease the debt and collateral of the current Trove according to the bit usd lot and
        // corresponding ETH to send
        let new_debt = single_redemption.trove.entire_debt - single_redemption.bit_usd_lot;
        let new_coll = single_redemption.trove.entire_coll - single_redemption.coll_lot;

        single_redemption
            .applied_redist_bit_usd_debt_gain = single_redemption
            .trove
            .redist_bit_usd_debt_gain;
        if (is_trove_in_batch) {
            _get_latest_batch_data(
                @self, single_redemption.batch_address, ref single_redemption.batch,
            );
            // We know bit usd lot <= trove entire debt, so this subtraction is safe
            let new_amount_for_weighted_debt = single_redemption
                .batch
                .entire_debt_without_redistribution
                + single_redemption.trove.redist_bit_usd_debt_gain
                - single_redemption.bit_usd_lot;
            single_redemption
                .old_weighted_recorded_debt = single_redemption
                .batch
                .weighted_recorded_debt;
            single_redemption.new_weighted_recorded_debt = new_amount_for_weighted_debt
                * single_redemption.trove.redist_coll_gain;

            let mut trove_change: TroveChange = Default::default();
            trove_change.debt_decrease = single_redemption.bit_usd_lot;
            trove_change.coll_decrease = single_redemption.coll_lot;
            trove_change
                .applied_redist_bit_usd_debt_gain = single_redemption
                .trove
                .redist_bit_usd_debt_gain;
            trove_change.applied_redist_coll_gain = single_redemption.trove.redist_coll_gain;

            // batchAccruedManagementFee is handled in the outer function
            trove_change
                .old_weighted_recorded_batch_management_fee = single_redemption
                .batch
                .weighted_recorded_batch_management_fee;
            trove_change.new_weighted_recorded_batch_management_fee = new_amount_for_weighted_debt
                * single_redemption.batch.annual_management_fee;

            let active_pool = IActivePoolDispatcher {
                contract_address: self.liquity_base.active_pool.read(),
            };
            active_pool
                .mint_batch_management_fee_and_account_for_change(
                    trove_change, single_redemption.batch_address,
                );

            self.troves.entry(single_redemption.trove_id).coll.write(new_coll);
            // interest and fee were updated in the outer function
            // This call could revert due to BatchSharesRatioTooHigh if trove.redistCollGain >
            // boldLot so we skip that check to avoid blocking redemptions
            _update_batch_shares(
                ref self,
                single_redemption.trove_id,
                single_redemption.batch_address,
                trove_change,
                new_debt,
                single_redemption.batch.entire_coll_without_redistribution,
                single_redemption.batch.entire_debt_without_redistribution,
                false,
            );
        } else {
            single_redemption
                .old_weighted_recorded_debt = single_redemption
                .trove
                .weighted_recorded_debt;
            single_redemption.new_weighted_recorded_debt = new_debt
                * single_redemption.trove.annual_interest_rate;
            self.troves.entry(single_redemption.trove_id).debt.write(new_debt);
            self.troves.entry(single_redemption.trove_id).coll.write(new_coll);
            self
                .troves
                .entry(single_redemption.trove_id)
                .last_debt_update_time
                .write(get_block_timestamp());
        }

        single_redemption
            .new_stake =
                _update_stake_and_total_stakes(ref self, single_redemption.trove_id, new_coll);

        _move_pending_trove_rewards_to_active_pool(
            ref self,
            default_pool_address,
            single_redemption.trove.redist_bit_usd_debt_gain,
            single_redemption.trove.redist_coll_gain,
        );
        _update_trove_reward_snapshots(ref self, single_redemption.trove_id);

        if (is_trove_in_batch) {
            self
                .emit(
                    event: BatchedTroveUpdated {
                        trove_id: single_redemption.trove_id,
                        interest_batch_manager: single_redemption.batch_address,
                        batch_debt_shares: self
                            .troves
                            .entry(single_redemption.trove_id)
                            .batch_debt_shares
                            .read(),
                        coll: new_coll,
                        stake: single_redemption.new_stake,
                        snapshot_of_total_coll_redist: self.l_coll.read(),
                        snapshot_of_total_debt_redist: self.l_bit_usd_debt.read(),
                    },
                );
        } else {
            self
                .emit(
                    event: TroveUpdated {
                        trove_id: single_redemption.trove_id,
                        debt: new_debt,
                        coll: new_coll,
                        stake: single_redemption.new_stake,
                        annual_interest_rate: single_redemption.trove.annual_interest_rate,
                        snapshot_of_total_coll_redist: self.l_coll.read(),
                        snapshot_of_total_debt_redist: self.l_bit_usd_debt.read(),
                    },
                );
        }

        self
            .emit(
                event: TroveOperation {
                    trove_id: single_redemption.trove_id,
                    operation: Operation::RedeemCollateral,
                    annual_interest_rate: single_redemption.trove.annual_interest_rate,
                    debt_increase_from_redist: single_redemption.trove.redist_bit_usd_debt_gain,
                    debt_increase_from_upfront_fee: 0,
                    debt_change_from_operation: i257Neg::neg(
                        I257Trait::new(single_redemption.bit_usd_lot, false),
                    ),
                    coll_increase_from_redist: single_redemption.trove.redist_coll_gain,
                    coll_change_from_operation: i257Neg::neg(
                        I257Trait::new(single_redemption.coll_lot, false),
                    ),
                },
            );

        if (is_trove_in_batch) {
            self
                .emit(
                    event: BatchUpdated {
                        interest_batch_manager: single_redemption.batch_address,
                        operation: BatchOperation::TroveChange,
                        debt: self.batches.entry(single_redemption.batch_address).debt.read(),
                        coll: self.batches.entry(single_redemption.batch_address).coll.read(),
                        annual_interest_rate: single_redemption.batch.annual_interest_rate,
                        annual_management_fee: single_redemption.batch.annual_management_fee,
                        total_debt_shares: self
                            .batches
                            .entry(single_redemption.batch_address)
                            .total_debt_shares
                            .read(),
                        debt_increase_from_upfront_fee: 0,
                    },
                );
        }

        self
            .emit(
                event: RedemptionFeePaidToTrove {
                    trove_id: single_redemption.trove_id, eth_fee: single_redemption.coll_fee,
                },
            );

        new_debt
    }

    // Update borrower's stake based on their latest collateral value
    fn _update_stake_and_total_stakes(ref self: ContractState, trove_id: u256, coll: u256) -> u256 {
        let new_stake = _compute_new_stake(@self, coll);
        let old_stake = self.troves.entry(trove_id).stake.read();
        self.troves.entry(trove_id).stake.write(new_stake);

        self.total_stakes.write(self.total_stakes.read() - old_stake + new_stake);
        new_stake
    }

    // Calculate a new stake based on the snapshots of the totalStakes and totalCollateral taken at
    // the last liquidation
    fn _compute_new_stake(self: @ContractState, coll: u256) -> u256 {
        let mut stake: u256 = 0;
        if (self.total_collateral_snapshot.read() == 0) {
            stake = coll;
        } else {
            //  The following assert() holds true because:
            //  - The system always contains >= 1 trove
            //  - When we close or liquidate a trove, we redistribute the redistribution gains, so
            //  if all troves were closed/liquidated, rewards would’ve been emptied and
            //  totalCollateralSnapshot would be zero too.

            // assert(totalStakesSnapshot > 0);
            stake = coll
                * self.total_stakes_snapshot.read()
                / self.total_collateral_snapshot.read();
        }
        stake
    }

    // This function will revert if there’s a total debt increase and the ratio debt / shares has
    // exceeded the max
    fn _update_batch_shares(
        ref self: ContractState,
        trove_id: u256,
        batch_address: ContractAddress,
        trove_change: TroveChange,
        new_trove_debt: u256,
        batch_coll: u256,
        batch_debt: u256,
        check_batch_shares_ratio: bool,
    ) {
        // Debt
        let current_batch_debt_shares = self.batches.read(batch_address).total_debt_shares;
        let mut batch_debt_shares_delta = 0;
        let mut debt_increase = trove_change.debt_increase
            + trove_change.upfront_fee
            + trove_change.applied_redist_bit_usd_debt_gain;
        let mut debt_decrease = 0;
        if (debt_increase > trove_change.debt_decrease) {
            debt_increase -= trove_change.debt_decrease;
        } else {
            debt_decrease = trove_change.debt_decrease - debt_increase;
            debt_increase = 0;
        }

        if (debt_increase == 0 && debt_decrease == 0) {
            self.batches.entry(batch_address).debt.write(batch_debt);
        } else {
            if (debt_increase > 0) {
                // Add debt
                if (batch_debt == 0) {
                    batch_debt_shares_delta = debt_increase;
                } else {
                    // To avoid rebasing issues, let’s make sure the ratio debt / shares is not
                    // too high
                    _require_below_max_shares_ratio(
                        @self, current_batch_debt_shares, batch_debt, check_batch_shares_ratio,
                    );
                    batch_debt_shares_delta = current_batch_debt_shares
                        * debt_increase
                        / batch_debt;
                }
                let new_batch_debt_shares = self.troves.entry(trove_id).batch_debt_shares.read()
                    + batch_debt_shares_delta;
                self.troves.entry(trove_id).batch_debt_shares.write(new_batch_debt_shares);
                self.batches.entry(batch_address).debt.write(batch_debt + debt_increase);
                self
                    .batches
                    .entry(batch_address)
                    .total_debt_shares
                    .write(current_batch_debt_shares + batch_debt_shares_delta);
            } else if (debt_decrease > 0) {
                // Subtract debt
                // We make sure that if final trove debt is zero, shares are too (avoiding rounding
                // issues)
                // This can only happen from redemptions, as otherwise we would be using
                // _removeTroveSharesFromBatch In redemptions we don’t do that because we don’t
                // want to kick the trove out of the batch (it’d be bad UX)
                if (new_trove_debt == 0) {
                    self.batches.entry(batch_address).debt.write(batch_debt - debt_decrease);
                    self
                        .batches
                        .entry(batch_address)
                        .total_debt_shares
                        .write(
                            current_batch_debt_shares
                                - self.troves.entry(trove_id).batch_debt_shares.read(),
                        );
                    self.troves.entry(trove_id).batch_debt_shares.write(0);
                } else {
                    batch_debt_shares_delta = current_batch_debt_shares
                        * debt_decrease
                        / batch_debt;
                    let new_batch_debt_shares = self.troves.entry(trove_id).batch_debt_shares.read()
                        - batch_debt_shares_delta;
                    self.troves.entry(trove_id).batch_debt_shares.write(new_batch_debt_shares);
                    self.batches.entry(batch_address).debt.write(batch_debt - debt_decrease);
                    self
                        .batches
                        .entry(batch_address)
                        .total_debt_shares
                        .write(current_batch_debt_shares - batch_debt_shares_delta);
                }
            }
        }
        // Update debt checkpoint
        self.batches.entry(batch_address).last_debt_update_time.write(get_block_timestamp());

        // Collateral
        let mut coll_increase = trove_change.coll_increase + trove_change.applied_redist_coll_gain;
        let mut coll_decrease = 0;
        if (coll_increase > trove_change.coll_decrease) {
            coll_increase -= trove_change.coll_decrease;
        } else {
            coll_decrease = trove_change.coll_decrease - coll_increase;
            coll_increase = 0;
        }

        if (coll_increase == 0 && coll_decrease == 0) {
            self.batches.entry(batch_address).coll.write(batch_coll);
        } else if (coll_increase > 0) {
            // Add collateral
            self.batches.entry(batch_address).coll.write(batch_coll + coll_increase);
        } else if (coll_decrease > 0) {
            // Subtract collateral
            self.batches.entry(batch_address).coll.write(batch_coll - coll_decrease);
        }
    }

    // For the debt / shares ratio to increase by a factor 1e9
    // at a average annual debt increase (compounded interest + fees) of 10%, it would take more
    // than 217 years (log(1e9)/log(1.1))
    // at a average annual debt increase (compounded interest + fees) of 50%, it would take more
    // than 51 years (log(1e9)/log(1.5))
    // When that happens, no more debt can be manually added to the batch, so batch should be
    // migrated to a new one
    fn _require_below_max_shares_ratio(
        self: @ContractState,
        current_batch_debt_shares: u256,
        batch_debt: u256,
        check_batch_shares_ratio: bool,
    ) {
        if (current_batch_debt_shares
            * MAX_BATCH_SHARES_RATIO < batch_debt && check_batch_shares_ratio) {
            assert(false, 'TM: Batch shares ratio too high');
        }
    }

    fn _get_coll_penalty_and_surplus(
        self: @ContractState,
        coll_to_liquidate: u256,
        debt_to_liquidate: u256,
        penalty_ratio: u256,
        price: u256,
    ) -> (u256, u256) {
        let max_seized_coll = debt_to_liquidate * (DECIMAL_PRECISION + penalty_ratio) / price;
        let mut seized_coll = 0;
        let mut coll_surplus = 0;
        if (coll_to_liquidate > max_seized_coll) {
            seized_coll = max_seized_coll;
            coll_surplus = coll_to_liquidate - max_seized_coll;
        } else {
            seized_coll = coll_to_liquidate;
            coll_surplus = 0;
        }
        (seized_coll, coll_surplus)
    }

    // Return the amount of Coll to be drawn from a trove's collateral and sent as gas compensation.
    fn _get_coll_gas_compensation(self: @ContractState, coll: u256) -> u256 {
        // _entireDebt should never be zero, but we add the condition defensively to avoid an
        // unexpected revert
        let result = min(coll / COLL_GAS_COMPENSATION_DIVISOR, COLL_GAS_COMPENSATION_CAP);
        result
    }

    // Move a Trove's pending debt and collateral rewards from distributions, from the Default Pool
    // to the Active Pool
    fn _move_pending_trove_rewards_to_active_pool(
        ref self: ContractState, default_pool_address: ContractAddress, bit_usd: u256, coll: u256,
    ) {
        let default_pool = IDefaultPoolDispatcher { contract_address: default_pool_address };
        if (bit_usd > 0) {
            default_pool.decrease_bit_usd_debt(bit_usd);
        }
        if (coll > 0) {
            default_pool.send_coll_to_active_pool(coll);
        }
    }

    // Return the Troves entire debt and coll, including redistribution gains from redistributions.
    fn _get_latest_trove_data(self: @ContractState, trove_id: u256, ref trove: LatestTroveData) {
        // If trove belongs to a batch, we fetch the batch and apply its share to obtained values.
        let batch_address = _get_batch_manager(self, trove_id);
        let zero_address: ContractAddress = 0.try_into().unwrap();
        if (batch_address != zero_address) {
            let mut batch: LatestBatchData = Default::default();

            _get_latest_batch_data(self, batch_address, ref batch);
            _get_latest_trove_data_from_batch(self, trove_id, ref trove, ref batch);
            return;
        }

        let stake = self.troves.read(trove_id).stake;
        trove.redist_bit_usd_debt_gain = stake
            * (self.l_bit_usd_debt.read() - self.reward_snapshots.read(trove_id).bit_usd_debt)
            / DECIMAL_PRECISION;

        trove.redist_coll_gain = stake
            * (self.l_coll.read() - self.reward_snapshots.read(trove_id).coll)
            / DECIMAL_PRECISION;

        trove.recorded_debt = self.troves.read(trove_id).debt;
        trove.annual_interest_rate = self.troves.read(trove_id).annual_interest_rate;
        trove.weighted_recorded_debt = trove.recorded_debt * trove.annual_interest_rate;

        let period = _get_interest_period(
            self, conversion_lib::u256_from_u64(self.troves.read(trove_id).last_debt_update_time),
        );
        trove
            .accrued_interest = self
            .liquity_base
            ._calc_interest(trove.weighted_recorded_debt, period);
        trove.entire_debt = trove.recorded_debt
            + trove.redist_bit_usd_debt_gain
            + trove.accrued_interest;
        trove.entire_coll = self.troves.read(trove_id).coll + trove.redist_coll_gain;
        trove
            .last_interest_rate_adj_time =
                conversion_lib::u256_from_u64(
                    self.troves.read(trove_id).last_interest_rate_adj_time,
                );
    }

    fn _get_batch_manager(self: @ContractState, trove_id: u256) -> ContractAddress {
        self.troves.read(trove_id).interest_batch_manager
    }

    fn _get_latest_trove_data_from_batch(
        self: @ContractState,
        trove_id: u256,
        ref latest_trove_data: LatestTroveData,
        ref latest_batch_data: LatestBatchData,
    ) {
        let trove = self.troves.read(trove_id);
        let batch_debt_shares = trove.batch_debt_shares;
        let total_debt_shares = latest_batch_data.total_debt_shares;
        let stake = trove.stake;
        latest_trove_data.redist_bit_usd_debt_gain = stake
            * (self.l_bit_usd_debt.read() - self.reward_snapshots.read(trove_id).coll)
            / DECIMAL_PRECISION;

        latest_trove_data.redist_coll_gain = stake
            * (self.l_coll.read() - self.reward_snapshots.read(trove_id).coll)
            / DECIMAL_PRECISION;

        if (total_debt_shares > 0) {
            latest_trove_data.recorded_debt = latest_batch_data.recorded_debt
                * batch_debt_shares
                / total_debt_shares;
            latest_trove_data.weighted_recorded_debt = latest_trove_data.recorded_debt
                * latest_batch_data.annual_interest_rate;
            latest_trove_data.accrued_interest = latest_batch_data.accrued_interest
                * batch_debt_shares
                / total_debt_shares;
            latest_trove_data
                .accrued_batch_management_fee = latest_batch_data
                .accrued_management_fee
                * batch_debt_shares
                / total_debt_shares;
        }

        latest_trove_data.annual_interest_rate = latest_batch_data.annual_interest_rate;

        // We can’t do pro-rata batch entireDebt, because redist gains are proportional to coll,
        // not to debt
        latest_trove_data.entire_debt = latest_trove_data.recorded_debt
            + latest_trove_data.redist_bit_usd_debt_gain
            + latest_trove_data.accrued_interest
            + latest_trove_data.accrued_batch_management_fee;

        latest_trove_data.entire_coll = trove.coll + latest_trove_data.redist_coll_gain;
        latest_trove_data
            .last_interest_rate_adj_time =
                max(
                    latest_batch_data.last_interest_rate_adj_time,
                    conversion_lib::u256_from_u64(trove.last_interest_rate_adj_time),
                );
    }

    fn _get_latest_batch_data(
        self: @ContractState,
        batch_address: ContractAddress,
        ref latest_batch_data: LatestBatchData,
    ) {
        let batch = self.batches.read(batch_address);

        latest_batch_data.total_debt_shares = batch.total_debt_shares;
        latest_batch_data.recorded_debt = batch.debt;
        latest_batch_data.annual_interest_rate = batch.annual_interest_rate;
        latest_batch_data.weighted_recorded_debt = batch.debt * batch.annual_interest_rate;
        let last_debt_update_time_u256 = conversion_lib::u256_from_u64(batch.last_debt_update_time);
        let period = _get_interest_period(self, last_debt_update_time_u256);
        latest_batch_data
            .accrued_interest = self
            .liquity_base
            ._calc_interest(latest_batch_data.weighted_recorded_debt, period);
        latest_batch_data.annual_management_fee = batch.annual_management_fee;
        latest_batch_data.weighted_recorded_batch_management_fee = batch.annual_management_fee
            * batch.debt;
        latest_batch_data
            .accrued_management_fee = self
            .liquity_base
            ._calc_interest(latest_batch_data.weighted_recorded_batch_management_fee, period);
        latest_batch_data.entire_debt_without_redistribution = batch.debt
            + latest_batch_data.accrued_interest
            + latest_batch_data.accrued_management_fee;
        latest_batch_data.entire_coll_without_redistribution = batch.coll;
        latest_batch_data.last_debt_update_time = last_debt_update_time_u256;
        latest_batch_data
            .last_interest_rate_adj_time =
                conversion_lib::u256_from_u64(batch.last_interest_rate_adj_time);
    }

    fn _get_interest_period(self: @ContractState, last_debt_update_time: u256) -> u256 {
        let shutdown_time = self.shutdown_time.read();
        if shutdown_time == 0 {
            // If branch is not shut down, interest is earned up to now.
            let block_timestamp_u256 = conversion_lib::u256_from_u64(get_block_timestamp());
            return block_timestamp_u256 - last_debt_update_time;
        } else if (shutdown_time > 0 && last_debt_update_time < shutdown_time) {
            // If branch is shut down and the Trove was not updated since shut down, interest is
            // earned up to the shutdown time.
            return shutdown_time - last_debt_update_time;
        } else {
            // if (shutdownTime > 0 && _lastDebtUpdateTime >= shutdownTime)
            // If branch is shut down and the Trove was updated after shutdown, no interest is
            // earned since.
            return 0;
        }
    }

    fn _is_active_or_zombie(status: Status) -> bool {
        status == Status::Active || status == Status::Zombie
    }

    fn _require_more_than_one_trove_in_system(trove_ids_array_length: u64) {
        assert(trove_ids_array_length > 1, 'At least 1 trove must exist');
    }

    // Remove a Trove owner from the TroveIds array, not preserving array order. Removing owner 'B'
    // does the following:
    // [A B C D E] => [A E C D], and updates E's Trove struct to point to its new array index.
    fn _remove_trove_id(ref self: ContractState, trove_id: u256, trove_ids_array_length: u64) {
        let index = self.troves.read(trove_id).array_index;
        let last_index = trove_ids_array_length - 1;

        // assert(index <= last_index);
        // TODO: Double check valid storage update here.
        let id_to_move = self.trove_ids.at(last_index).read();
        let mut storage_ptr = self.trove_ids.at(index);
        storage_ptr.write(id_to_move);

        self.troves.entry(id_to_move).array_index.write(index);
        self.trove_ids.pop().unwrap();
    }

    fn _urgent_redeem_collateral_from_trove(
        ref self: ContractState,
        default_pool_address: ContractAddress,
        max_bit_usd_amount: u256,
        price: u256,
        ref single_redemption: SingleRedemptionValues,
    ) {
        // Determine the remaining amount (lot) to be redeemed, capped by the entire debt of the
        // Trove minus the liquidation reserve
        single_redemption
            .bit_usd_lot = min(max_bit_usd_amount, single_redemption.trove.entire_debt);

        // Get the amount of coll equal in USD value to the bitUSD lot redeemed
        single_redemption.coll_lot = single_redemption.bit_usd_lot
            * (DECIMAL_PRECISION + URGENT_REDEMPTION_BONUS)
            / price;
        // As here we can redeem when CR < 101% (accounting for 1% bonus), we need to cap by
        // collateral too
        if (single_redemption.coll_lot > single_redemption.trove.entire_coll) {
            single_redemption.coll_lot = single_redemption.trove.entire_coll;
            single_redemption.bit_usd_lot = single_redemption.trove.entire_coll
                * price
                / (DECIMAL_PRECISION + URGENT_REDEMPTION_BONUS);
        }

        let is_trove_in_batch = single_redemption.batch_address != 0.try_into().unwrap();
        _apply_single_redemption(
            ref self, default_pool_address, ref single_redemption, is_trove_in_batch,
        );
        // No need to make this Trove zombie if it has tiny debt, since:
    // - This collateral branch has shut down and urgent redemptions are enabled
    // - Urgent redemptions aren't sequential, so they can't be griefed by tiny Troves.
    }

    fn _require_amount_greather_than_zero(self: @ContractState, amount: u256) {
        assert(amount > 0, 'TM: amount must be > than zero');
    }

    fn _require_bit_usd_balance_covers_redemption(
        self: @ContractState,
        bit_usd_token: ContractAddress,
        caller: ContractAddress,
        bit_usd_amount: u256,
    ) {
        let bit_usd = IERC20Dispatcher { contract_address: bit_usd_token };
        let bit_usd_balance = bit_usd.balance_of(caller);
        assert(bit_usd_balance >= bit_usd_amount, 'TM: not enough bitUSD balance');
    }
}
