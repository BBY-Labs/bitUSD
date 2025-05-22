use starknet::ContractAddress;

#[starknet::interface]
pub trait IAddRemoveManagers<TContractState> {
    fn set_add_manager(ref self: TContractState, trove_id: u256, manager: ContractAddress);
    fn set_remove_manager(ref self: TContractState, trove_id: u256, manager: ContractAddress);
    fn set_remove_manager_with_receiver(
        ref self: TContractState,
        trove_id: u256,
        manager: ContractAddress,
        receiver: ContractAddress,
    );
    fn get_remove_manager_receiver_of(
        self: @TContractState, trove_id: u256,
    ) -> RemoveManagerReceiver;
    fn get_add_manager_of(self: @TContractState, trove_id: u256) -> ContractAddress;
}

#[derive(Copy, Drop, Serde, starknet::Store)]
struct RemoveManagerReceiver {
    manager: ContractAddress,
    receiver: ContractAddress,
}

/// Base contract for TroveManager, BorrowerOperations and StabilityPool. Contains global system
/// constants and common functions.
#[starknet::component]
pub mod AddRemoveManagersComponent {
    use starknet::storage::{
        Map, StoragePathEntry, StoragePointerReadAccess, StoragePointerWriteAccess,
    };
    use starknet::{ContractAddress, get_caller_address};
    use crate::AddressesRegistry::{IAddressesRegistryDispatcher, IAddressesRegistryDispatcherTrait};
    use crate::TroveNFT::{ITroveNFTDispatcher, ITroveNFTDispatcherTrait};
    use super::{IAddRemoveManagers, RemoveManagerReceiver};

    //////////////////////////////////////////////////////////////
    //                          STORAGE                         //
    //////////////////////////////////////////////////////////////

    #[storage]
    pub struct Storage {
        pub trove_nft: ContractAddress,
        // Mapping from TroveId to granted address for operations that "give" money to the trove
        // (add collateral, pay debt).
        // Useful for instance for cold/hot wallet setups.
        // If its value is zero address, any address is allowed to do those operations on behalf of
        // trove owner.
        // Otherwise, only the address in this mapping (and the trove owner) will be allowed.
        // To restrict this permission to no one, trove owner should be set in this mapping.
        pub add_manager_of: Map<u256, ContractAddress>,
        // Mapping from TroveId to granted addresses for operations that "withdraw" money from the
        // trove (withdraw collateral, borrow), and for each of those addresses another address for
        // the receiver of those withdrawn funds.
        // Useful for instance for cold/hot wallet setups or for automations.
        // Only the address in this mapping, if any, and the trove owner, will be allowed.
        // Therefore, by default this permission is restricted to no one.
        // If the receiver is zero, the owner is assumed as the receiver.
        // RemoveManager also assumes AddManager permission
        pub remove_manager_receiver_of: Map<u256, RemoveManagerReceiver>,
    }

    //////////////////////////////////////////////////////////////
    //                          EVENTS                          //
    //////////////////////////////////////////////////////////////

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        TroveNFTAddressChanged: TroveNFTAddressChanged,
        AddManagerUpdated: AddManagerUpdated,
        RemoveManagerAndReceiverUpdated: RemoveManagerAndReceiverUpdated,
    }

    #[derive(Drop, starknet::Event)]
    pub struct TroveNFTAddressChanged {
        pub new_trove_nft_address: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    pub struct AddManagerUpdated {
        pub trove_id: u256,
        pub new_add_manager: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    pub struct RemoveManagerAndReceiverUpdated {
        pub trove_id: u256,
        pub new_remove_manager: ContractAddress,
        pub new_receiver: ContractAddress,
    }

    ////////////////////////////////////////////////////////////////
    //                          FUNCTIONS                         //
    ////////////////////////////////////////////////////////////////

    #[embeddable_as(AddRemoveManagersImpl)]
    impl AddRemoveManagers<
        TContractState, +HasComponent<TContractState>,
    > of IAddRemoveManagers<ComponentState<TContractState>> {
        fn set_add_manager(
            ref self: ComponentState<TContractState>, trove_id: u256, manager: ContractAddress,
        ) {
            self._require_caller_is_borrower(trove_id);
            self._set_add_manager(trove_id, manager);
        }

        fn set_remove_manager(
            ref self: ComponentState<TContractState>, trove_id: u256, manager: ContractAddress,
        ) {
            self._require_caller_is_borrower(trove_id);
            let trove_nft = ITroveNFTDispatcher { contract_address: self.trove_nft.read() };
            let owner = trove_nft.get_trove_owner(trove_id);
            self._set_remove_manager_and_receiver(trove_id, manager, owner);
        }

        fn set_remove_manager_with_receiver(
            ref self: ComponentState<TContractState>,
            trove_id: u256,
            manager: ContractAddress,
            receiver: ContractAddress,
        ) {
            self._require_caller_is_borrower(trove_id);
            self._set_remove_manager_and_receiver(trove_id, manager, receiver);
        }

        fn get_remove_manager_receiver_of(
            self: @ComponentState<TContractState>, trove_id: u256,
        ) -> RemoveManagerReceiver {
            self.remove_manager_receiver_of.entry(trove_id).read()
        }

        fn get_add_manager_of(
            self: @ComponentState<TContractState>, trove_id: u256,
        ) -> ContractAddress {
            let add_manager = self.add_manager_of.entry(trove_id).read();
            add_manager
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
            ref self: ComponentState<TContractState>, addresses_registry_address: ContractAddress,
        ) {
            let addresses_registry = IAddressesRegistryDispatcher {
                contract_address: addresses_registry_address,
            };

            self.trove_nft.write(addresses_registry.get_trove_nft());
        }

        fn _require_caller_is_borrower(self: @ComponentState<TContractState>, trove_id: u256) {
            let trove_nft_address = self.trove_nft.read();
            let trove_nft = ITroveNFTDispatcher { contract_address: trove_nft_address };
            let trove_owner = trove_nft.get_trove_owner(trove_id);
            assert(get_caller_address() == trove_owner, 'ARM: Caller is not trove owner');
        }

        fn _set_add_manager(
            ref self: ComponentState<TContractState>, trove_id: u256, manager: ContractAddress,
        ) {
            self.add_manager_of.entry(trove_id).write(manager);
            self.emit(event: AddManagerUpdated { trove_id: trove_id, new_add_manager: manager });
        }

        fn _set_remove_manager_and_receiver(
            ref self: ComponentState<TContractState>,
            trove_id: u256,
            manager: ContractAddress,
            receiver: ContractAddress,
        ) {
            self._require_non_zero_manager_unless_wiping(manager, receiver);
            self.remove_manager_receiver_of.entry(trove_id).manager.write(manager);
            self.remove_manager_receiver_of.entry(trove_id).receiver.write(receiver);
            self
                .emit(
                    event: RemoveManagerAndReceiverUpdated {
                        trove_id: trove_id, new_remove_manager: manager, new_receiver: receiver,
                    },
                );
        }

        fn _require_non_zero_manager_unless_wiping(
            self: @ComponentState<TContractState>,
            manager: ContractAddress,
            receiver: ContractAddress,
        ) {
            if manager == 0.try_into().unwrap() && receiver != 0.try_into().unwrap() {
                assert(false, 'ARM: Empty Manager');
            }
        }

        fn _wipe_add_remove_managers(ref self: ComponentState<TContractState>, trove_id: u256) {
            self.add_manager_of.entry(trove_id).write(0.try_into().unwrap());
            self.remove_manager_receiver_of.entry(trove_id).manager.write(0.try_into().unwrap());
            self.remove_manager_receiver_of.entry(trove_id).receiver.write(0.try_into().unwrap());

            self
                .emit(
                    event: AddManagerUpdated {
                        trove_id: trove_id, new_add_manager: 0.try_into().unwrap(),
                    },
                );
            self
                .emit(
                    event: RemoveManagerAndReceiverUpdated {
                        trove_id: trove_id,
                        new_remove_manager: 0.try_into().unwrap(),
                        new_receiver: 0.try_into().unwrap(),
                    },
                );
        }

        fn _require_sender_is_owner_or_add_manager(
            self: @ComponentState<TContractState>, trove_id: u256, owner: ContractAddress,
        ) {
            let add_manager = self.add_manager_of.entry(trove_id).read();
            let caller = get_caller_address();
            if (caller != owner && add_manager != 0.try_into().unwrap() && caller != add_manager) {
                // RemoveManager assumes AddManager permission too
                let remove_manager = self.remove_manager_receiver_of.entry(trove_id).manager.read();
                if (caller != remove_manager) {
                    assert(false, 'ARM: Not owner or add manager');
                }
            }
        }

        fn _require_sender_is_owner_or_remove_manager_and_get_receiver(
            self: @ComponentState<TContractState>, trove_id: u256, owner: ContractAddress,
        ) -> ContractAddress {
            let manager = self.remove_manager_receiver_of.entry(trove_id).manager.read();
            let receiver = self.remove_manager_receiver_of.entry(trove_id).receiver.read();
            let caller = get_caller_address();
            if (caller != owner && caller != manager) {
                assert(false, 'ARM: Not owner or rm');
            }
            if (receiver == 0.try_into().unwrap() || caller != manager) {
                return owner;
            }
            return receiver;
        }
    }
}
