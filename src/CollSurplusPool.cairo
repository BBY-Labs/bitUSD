use starknet::ContractAddress;

#[starknet::interface]
pub trait ICollSurplusPool<TContractState> {
    // TODO: delete
    fn set_addresses(ref self: TContractState, addresses_registry: ContractAddress);
    fn account_surplus(ref self: TContractState, account: ContractAddress, amount: u256);
    fn claim_coll(ref self: TContractState, account: ContractAddress);
    fn get_coll_token(ref self: TContractState) -> ContractAddress;
    fn get_coll_balance(ref self: TContractState) -> u256;
    fn get_borrower_operations(ref self: TContractState) -> ContractAddress;
    fn get_trove_manager(ref self: TContractState) -> ContractAddress;
    fn get_collateral(ref self: TContractState, owner: ContractAddress) -> u256;
}

#[starknet::contract]
pub mod CollSurplusPool {
    use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use starknet::storage::{
        Map, StoragePathEntry, StoragePointerReadAccess, StoragePointerWriteAccess,
    };
    use starknet::{ContractAddress, get_caller_address};
    use crate::AddressesRegistry::{IAddressesRegistryDispatcher, IAddressesRegistryDispatcherTrait};
    use super::ICollSurplusPool;
    //////////////////////////////////////////////////////////////
    //                          CONSTANTS                       //
    //////////////////////////////////////////////////////////////

    // ID of head & tail of the list. Callers should stop iterating with `getNext()` / `getPrev()`
    // when encountering this node ID.
    pub const NAME: felt252 = 'CollSurplusPool';

    //////////////////////////////////////////////////////////////
    //                          STORAGE                         //
    //////////////////////////////////////////////////////////////

    #[storage]
    struct Storage {
        coll_token: ContractAddress,
        borrower_operations: ContractAddress,
        trove_manager: ContractAddress,
        coll_balance: u256,
        balances: Map<ContractAddress, u256>,
    }

    //////////////////////////////////////////////////////////////
    //                          EVENTS                          //
    //////////////////////////////////////////////////////////////

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        TroveManagerAddressChanged: TroveManagerAddressChanged,
        BorrowerOperationsAddressChanged: BorrowerOperationsAddressChanged,
        CollBalanceUpdated: CollBalanceUpdated,
        CollSent: CollSent,
    }

    #[derive(Drop, starknet::Event)]
    pub struct TroveManagerAddressChanged {
        pub new_trove_manager_address: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    pub struct BorrowerOperationsAddressChanged {
        pub new_borrower_operations_address: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    pub struct CollBalanceUpdated {
        pub account: ContractAddress,
        pub new_balance: u256,
    }

    #[derive(Drop, starknet::Event)]
    pub struct CollSent {
        pub account: ContractAddress,
        pub amount: u256,
    }

    ////////////////////////////////////////////////////////////////
    //                        CONSTRUCTOR                         //
    ////////////////////////////////////////////////////////////////

    #[constructor]
    fn constructor(ref self: ContractState, addresses_registry: ContractAddress) {
        let addresses_registry = IAddressesRegistryDispatcher {
            contract_address: addresses_registry,
        };
        self.borrower_operations.write(addresses_registry.get_borrower_operations());
        self.trove_manager.write(addresses_registry.get_trove_manager());
        self.coll_token.write(addresses_registry.get_coll_token());

        self
            .emit(
                event: TroveManagerAddressChanged {
                    new_trove_manager_address: addresses_registry.get_trove_manager(),
                },
            );

        self
            .emit(
                event: BorrowerOperationsAddressChanged {
                    new_borrower_operations_address: addresses_registry.get_borrower_operations(),
                },
            );
    }

    ////////////////////////////////////////////////////////////////
    //                     EXTERNAL FUNCTIONS                     //
    ////////////////////////////////////////////////////////////////
    #[abi(embed_v0)]
    impl ICollSurplusPoolImpl of ICollSurplusPool<ContractState> {
        // TODO: remove
        fn set_addresses(ref self: ContractState, addresses_registry: ContractAddress) {
            let addresses_registry_instance = IAddressesRegistryDispatcher {
                contract_address: addresses_registry,
            };

            self.borrower_operations.write(addresses_registry_instance.get_borrower_operations());
            self.trove_manager.write(addresses_registry_instance.get_trove_manager());
            self.coll_token.write(addresses_registry_instance.get_coll_token());
        }

        // VIEW FUNCTIONS
        fn account_surplus(ref self: ContractState, account: ContractAddress, amount: u256) {
            _require_caller_is_trove_manager(@self);

            let new_amount = self.balances.entry(account).read() + amount;
            self.balances.entry(account).write(new_amount);
            self.coll_balance.write(self.coll_balance.read() + amount);

            self.emit(event: CollBalanceUpdated { account: account, new_balance: new_amount });
        }

        fn claim_coll(ref self: ContractState, account: ContractAddress) {
            _require_caller_is_borrower_operations(@self);

            let claimable_coll = self.balances.entry(account).read();
            assert(claimable_coll > 0, 'CSP: nothing to claim');
            self.balances.entry(account).write(0);
            self.emit(event: CollBalanceUpdated { account: account, new_balance: 0 });

            self.coll_balance.write(self.coll_balance.read() - claimable_coll);
            self.emit(event: CollSent { account: account, amount: claimable_coll });

            let coll_token = IERC20Dispatcher { contract_address: self.coll_token.read() };
            coll_token.transfer(account, claimable_coll);
        }

        fn get_coll_token(ref self: ContractState) -> ContractAddress {
            self.coll_token.read()
        }

        fn get_coll_balance(ref self: ContractState) -> u256 {
            self.coll_balance.read()
        }

        fn get_borrower_operations(ref self: ContractState) -> ContractAddress {
            self.borrower_operations.read()
        }

        fn get_trove_manager(ref self: ContractState) -> ContractAddress {
            self.trove_manager.read()
        }

        fn get_collateral(ref self: ContractState, owner: ContractAddress) -> u256 {
            self.balances.entry(owner).read()
        }
    }

    ////////////////////////////////////////////////////////////////
    //                     ACCESS FUNCTIONS                       //
    ////////////////////////////////////////////////////////////////

    fn _require_caller_is_borrower_operations(self: @ContractState) {
        assert(get_caller_address() == self.borrower_operations.read(), 'TM: caller is not BO');
    }

    fn _require_caller_is_trove_manager(self: @ContractState) {
        assert(get_caller_address() == self.trove_manager.read(), 'TM: caller is not TM');
    }
}
