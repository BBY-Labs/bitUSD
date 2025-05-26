#[starknet::interface]
pub trait ILiquityBase<TContractState> {
    fn get_entire_branch_coll(self: @TContractState) -> u256;
    fn get_entire_branch_debt(self: @TContractState) -> u256;
}


/// Base contract for TroveManager, BorrowerOperations and StabilityPool. Contains global system
/// constants and common functions.
#[starknet::component]
pub mod LiquityBaseComponent {
    use starknet::ContractAddress;
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use crate::ActivePool::{IActivePoolDispatcher, IActivePoolDispatcherTrait};
    use crate::AddressesRegistry::{IAddressesRegistryDispatcher, IAddressesRegistryDispatcherTrait};
    use crate::DefaultPool::{IDefaultPoolDispatcher, IDefaultPoolDispatcherTrait};
    use crate::dependencies::Constants::Constants::{DECIMAL_PRECISION, ONE_YEAR};
    use crate::dependencies::ConversionLib::conversion_lib;
    use crate::dependencies::MathLib::math_lib;
    use super::ILiquityBase;
    //////////////////////////////////////////////////////////////
    //                          STORAGE                         //
    //////////////////////////////////////////////////////////////

    #[storage]
    pub struct Storage {
        pub active_pool: ContractAddress,
        pub default_pool: ContractAddress,
        pub price_feed: ContractAddress,
    }

    //////////////////////////////////////////////////////////////
    //                          EVENTS                          //
    //////////////////////////////////////////////////////////////

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        ActivePoolAddressChanged: ActivePoolAddressChanged,
        DefaultPoolAddressChanged: DefaultPoolAddressChanged,
        PriceFeedAddressChanged: PriceFeedAddressChanged,
    }

    #[derive(Drop, starknet::Event)]
    pub struct ActivePoolAddressChanged {
        pub new_active_pool_address: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    pub struct DefaultPoolAddressChanged {
        pub new_default_pool_address: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    pub struct PriceFeedAddressChanged {
        pub new_price_feed_address: ContractAddress,
    }

    ////////////////////////////////////////////////////////////////
    //                     EXTERNAL FUNCTIONS                     //
    ////////////////////////////////////////////////////////////////

    #[embeddable_as(LiquityBaseImpl)]
    impl LiquityBase<
        TContractState, +HasComponent<TContractState>,
    > of ILiquityBase<ComponentState<TContractState>> {
        fn get_entire_branch_coll(self: @ComponentState<TContractState>) -> u256 {
            let active_pool_address = self.active_pool.read();
            let default_pool_address = self.default_pool.read();

            let active_pool = IActivePoolDispatcher { contract_address: active_pool_address };

            let default_pool = IDefaultPoolDispatcher { contract_address: default_pool_address };

            let active_pool_coll = active_pool.get_coll_balance();
            let default_pool_coll = default_pool.get_coll_balance();

            active_pool_coll + default_pool_coll
        }

        fn get_entire_branch_debt(self: @ComponentState<TContractState>) -> u256 {
            let active_pool_address = self.active_pool.read();
            let default_pool_address = self.default_pool.read();

            let active_pool = IActivePoolDispatcher { contract_address: active_pool_address };

            let default_pool = IDefaultPoolDispatcher { contract_address: default_pool_address };

            let active_pool_debt = active_pool.get_bit_usd_debt();
            let default_pool_debt = default_pool.get_bit_usd_debt();

            active_pool_debt + default_pool_debt
        }
    }

    ////////////////////////////////////////////////////////////////
    //                     INTERNAL FUNCTIONS                     //
    ////////////////////////////////////////////////////////////////

    #[generate_trait]
    pub impl InternalImpl<
        TContractState, +HasComponent<TContractState>,
    > of InternalTrait<TContractState> {
        fn initializer(
            ref self: ComponentState<TContractState>, addresses_registry: ContractAddress,
        ) {
            let addresses_registry = IAddressesRegistryDispatcher {
                contract_address: addresses_registry,
            };

            self.active_pool.write(addresses_registry.get_active_pool());
            self.default_pool.write(addresses_registry.get_default_pool());
            self.price_feed.write(addresses_registry.get_price_pool());
        }

        fn _get_TCR(self: @ComponentState<TContractState>, price: u256) -> u256 {
            let entire_system_coll = self.get_entire_branch_coll();
            let entire_system_debt = self.get_entire_branch_debt();

            math_lib::compute_cr(entire_system_coll, entire_system_debt, price)
        }

        fn _check_below_critical_threshold(
            self: @ComponentState<TContractState>, price: u256, ccr: u256,
        ) -> bool {
            let tcr = self._get_TCR(price);
            tcr < ccr
        }

        fn _calc_interest(
            self: @ComponentState<TContractState>, weighted_debt: u256, period: u256,
        ) -> u256 {
            let one_year_u256 = conversion_lib::u256_from_u64(ONE_YEAR);
            weighted_debt * period / one_year_u256 / DECIMAL_PRECISION
        }
    }
}
