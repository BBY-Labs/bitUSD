#[starknet::interface]
pub trait IDefaultPool<TContractState> {
    // View functions
    fn get_coll_balance(self: @TContractState) -> u256;
    fn get_bit_usd_debt(self: @TContractState) -> u256;
    // Pool Functionality
    fn send_coll_to_active_pool(ref self: TContractState, amount: u256);
    fn receive_coll(ref self: TContractState, amount: u256);
    fn increase_bit_usd_debt(ref self: TContractState, amount: u256);
    fn decrease_bit_usd_debt(ref self: TContractState, amount: u256);
}

/// The Default Pool holds the Coll and Bold debt (but not Bold tokens) from liquidations that have
/// been redistributed.
/// to active troves but not yet "applied", i.e. not yet recorded on a recipient active trove's
/// struct.
///
/// When a trove makes an operation that applies its pending Coll and Bold debt, its pending Coll
/// and Bold debt is moved.
/// from the Default Pool to the Active Pool.
#[starknet::contract]
pub mod DefaultPool {
    use core::num::traits::Bounded;
    use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use starknet::{ContractAddress, get_caller_address, get_contract_address};
    use crate::ActivePool::{IActivePoolDispatcher, IActivePoolDispatcherTrait};
    use crate::AddressesRegistry::{IAddressesRegistryDispatcher, IAddressesRegistryDispatcherTrait};
    use super::IDefaultPool;
    //////////////////////////////////////////////////////////////
    //                         CONSTANTS                        //
    //////////////////////////////////////////////////////////////

    const NAME: felt252 = 'DefaultPool';

    //////////////////////////////////////////////////////////////
    //                          STORAGE                         //
    //////////////////////////////////////////////////////////////

    #[storage]
    struct Storage {
        coll_token: ContractAddress,
        trove_manager: ContractAddress,
        active_pool: ContractAddress,
        coll_balance: u256,
        bit_usd_debt: u256,
    }

    //////////////////////////////////////////////////////////////
    //                          EVENTS                          //
    //////////////////////////////////////////////////////////////

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        DefaultPoolBitUSDDebtUpdated: DefaultPoolBitUSDDebtUpdated,
        DefaultPoolCollBalanceUpdated: DefaultPoolCollBalanceUpdated,
    }

    #[derive(Drop, starknet::Event)]
    pub struct DefaultPoolBitUSDDebtUpdated {
        pub bit_usd_debt: u256,
    }

    #[derive(Drop, starknet::Event)]
    pub struct DefaultPoolCollBalanceUpdated {
        pub coll_balance: u256,
    }

    //////////////////////////////////////////////////////////////
    //                     CONSTRUCTOR                          //
    //////////////////////////////////////////////////////////////

    #[constructor]
    fn constructor(ref self: ContractState, addresses_registry: ContractAddress) {
        let addresses_registry = IAddressesRegistryDispatcher {
            contract_address: addresses_registry,
        };

        let coll_token_address = addresses_registry.get_coll_token();

        self.coll_token.write(coll_token_address);
        self.active_pool.write(addresses_registry.get_active_pool());
        self.trove_manager.write(addresses_registry.get_trove_manager());

        // Allow funds movements between Liquity contracts.
        let max_u256 = Bounded::<u256>::MAX;
        let coll_token = IERC20Dispatcher { contract_address: coll_token_address };
        // TODO: Maybe add an new approval if approval becomes too low.
        coll_token.approve(self.active_pool.read(), max_u256);
    }

    //////////////////////////////////////////////////////////////
    //                     EXTERNAL FUNCTIONS                   //
    //////////////////////////////////////////////////////////////

    #[abi(embed_v0)]
    impl IDefaultPoolImpl of IDefaultPool<ContractState> {
        fn get_coll_balance(self: @ContractState) -> u256 {
            self.coll_balance.read()
        }

        fn get_bit_usd_debt(self: @ContractState) -> u256 {
            self.bit_usd_debt.read()
        }

        fn send_coll_to_active_pool(ref self: ContractState, amount: u256) {
            _require_caller_is_trove_manager(@self);
            let new_coll_balance = self.coll_balance.read() - amount;
            self.coll_balance.write(new_coll_balance);

            self.emit(event: DefaultPoolCollBalanceUpdated { coll_balance: new_coll_balance });

            let active_pool_address = self.active_pool.read();
            let active_pool = IActivePoolDispatcher { contract_address: active_pool_address };

            // Send Coll to Active Pool and increase its recorded Coll balance
            active_pool.receive_coll(amount);
        }

        fn receive_coll(ref self: ContractState, amount: u256) {
            _require_caller_is_active_pool(@self);

            let new_coll_balance = self.coll_balance.read() + amount;
            self.coll_balance.write(new_coll_balance);

            // Pull Coll tokens from ActivePool
            let coll_token_address = self.coll_token.read();
            let coll_token = IERC20Dispatcher { contract_address: coll_token_address };
            coll_token.transfer_from(get_caller_address(), get_contract_address(), amount);

            self.emit(event: DefaultPoolCollBalanceUpdated { coll_balance: new_coll_balance });
        }

        fn increase_bit_usd_debt(ref self: ContractState, amount: u256) {
            _require_caller_is_trove_manager(@self);
            let new_bit_usd_debt = self.bit_usd_debt.read() + amount;
            self.bit_usd_debt.write(new_bit_usd_debt);

            self.emit(event: DefaultPoolBitUSDDebtUpdated { bit_usd_debt: new_bit_usd_debt });
        }

        fn decrease_bit_usd_debt(ref self: ContractState, amount: u256) {
            _require_caller_is_trove_manager(@self);
            let new_bit_usd_debt = self.bit_usd_debt.read() - amount;
            self.bit_usd_debt.write(new_bit_usd_debt);

            self.emit(event: DefaultPoolBitUSDDebtUpdated { bit_usd_debt: new_bit_usd_debt });
        }
    }

    ////////////////////////////////////////////////////////////////
    //                     ACCESS FUNCTIONS                       //
    ////////////////////////////////////////////////////////////////

    fn _require_caller_is_active_pool(self: @ContractState) {
        assert(get_caller_address() == self.active_pool.read(), 'DP: Caller is not the AP');
    }

    fn _require_caller_is_trove_manager(self: @ContractState) {
        assert(get_caller_address() == self.trove_manager.read(), 'DP: Caller is not the TM');
    }
}
