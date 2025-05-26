use starknet::ContractAddress;

#[starknet::interface]
pub trait ISortedTroves<TContractState> {
    fn set_addresses(ref self: TContractState, addresses_registry: ContractAddress);
    fn insert(
        ref self: TContractState,
        id: u256,
        annual_interest_rate: u256,
        prev_id: u256,
        next_id: u256,
    );
    fn insert_into_batch(
        ref self: TContractState,
        trove_id: u256,
        batch_id: ContractAddress,
        annual_interest_rate: u256,
        prev_id: u256,
        next_id: u256,
    );
    fn valid_insert_position(
        self: @TContractState,
        trove_manager: ContractAddress,
        annual_interest_rate: u256,
        prev_id: u256,
        next_id: u256,
    ) -> bool;
    fn find_insert_position(
        self: @TContractState, annual_interest_rate: u256, prev_id: u256, next_id: u256,
    ) -> (u256, u256);
    fn remove_from_batch(ref self: TContractState, id: u256);
    fn remove(ref self: TContractState, id: u256);
    fn get_first(self: @TContractState) -> u256;
    fn get_last(self: @TContractState) -> u256;
    fn get_next(self: @TContractState, trove_id: u256) -> u256;
    fn get_prev(self: @TContractState, trove_id: u256) -> u256;
    fn get_batch(self: @TContractState, batch_id: ContractAddress) -> Batch;
    fn get_node(self: @TContractState, id: u256) -> Node;
    fn get_size(self: @TContractState) -> u256;
    fn get_trove_manager(self: @TContractState) -> ContractAddress;
    fn get_borrower_operations(self: @TContractState) -> ContractAddress;
    fn contains(self: @TContractState, id: u256) -> bool;
    fn re_insert(
        ref self: TContractState,
        id: u256,
        new_annual_interest_rate: u256,
        prev_id: u256,
        next_id: u256,
    );
    fn re_insert_batch(
        ref self: TContractState,
        batch_id: ContractAddress,
        new_annual_interest_rate: u256,
        prev_id: u256,
        next_id: u256,
    );
    fn is_batched_node(self: @TContractState, id: u256) -> bool;
    fn is_empty_batch(self: @TContractState, batch_id: ContractAddress) -> bool;
    fn is_empty(self: @TContractState) -> bool;
}

#[derive(Copy, Drop, Serde, starknet::Store, Default)]
struct Batch {
    head: u256,
    tail: u256,
}

#[derive(Copy, Drop, Serde, starknet::Store)]
struct Node {
    // Id of next node (smaller interest rate) in the list
    next_id: u256,
    // Id of previous node (larger interest rate) in the list
    prev_id: u256,
    // Id of this node's batch manager, or zero in case of non-batched nodes
    batch_id: ContractAddress,
    exists: bool,
}

// A sorted doubly linked list with nodes sorted in descending order.
// Nodes map to active Troves in the system - the ID property is the address of a Trove owner.
// Nodes are ordered according to the borrower's chosen annual interest rate.
// The list optionally accepts insert position hints.
// The annual interest rate is stored on the Trove struct in TroveManager, not directly on the Node.
// A node need only be re-inserted when the borrower adjusts their interest rate. Interest rate
// order is preserved under all other system operations.
// The list is a modification of the following audited SortedDoublyLinkedList:
// https://github.com/livepeer/protocol/blob/master/contracts/libraries/SortedDoublyLL.sol
// Changes made in the BitUSD implementation:
// - Keys have been removed from nodes
// - Ordering checks for insertion are performed by comparing an interest rate argument to the
// Trove's current interest rate.
// - Public functions with parameters have been made internal to save gas, and given an external
// wrapper function for external access
#[starknet::contract]
pub mod SortedTroves {
    use starknet::storage::{
        Map, StoragePathEntry, StoragePointerReadAccess, StoragePointerWriteAccess,
    };
    use starknet::{ContractAddress, get_caller_address};
    use crate::AddressesRegistry::{IAddressesRegistryDispatcher, IAddressesRegistryDispatcherTrait};
    use crate::TroveManager::{ITroveManagerDispatcher, ITroveManagerDispatcherTrait};
    use super::{Batch, ISortedTroves, Node};

    //////////////////////////////////////////////////////////////
    //                          CONSTANTS                       //
    //////////////////////////////////////////////////////////////

    // ID of head & tail of the list. Callers should stop iterating with `getNext()` / `getPrev()`
    // when encountering this node ID.
    pub const ROOT_NODE_ID: u256 = 0;

    pub const NAME: felt252 = 'SortedTroves';

    pub const UNINITIALIZED_ID: u256 = 0;
    pub const BAD_HINT: u256 = 0;

    //////////////////////////////////////////////////////////////
    //                          STORAGE                         //
    //////////////////////////////////////////////////////////////

    #[storage]
    struct Storage {
        borrower_operations: ContractAddress,
        trove_manager: ContractAddress,
        // Current size of the list.
        size: u256,
        // Stores the forward and reverse links of each node in the list.
        // nodes[ROOT_NODE_ID] holds the head and tail of the list. This avoids the need for special
        // handling when inserting into or removing from a terminal position (head or tail),
        // inserting into an empty list or removing the element of a singleton list.
        nodes: Map<u256, Node>,
        batches: Map<ContractAddress, Batch>,
    }

    //////////////////////////////////////////////////////////////
    //                          STRUCTS                         //
    //////////////////////////////////////////////////////////////

    #[derive(Copy, Drop, Serde, starknet::Store, Default)]
    struct Position {
        prev_id: u256,
        next_id: u256,
    }

    //////////////////////////////////////////////////////////////
    //                          EVENTS                          //
    //////////////////////////////////////////////////////////////

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        TroveManagerAddressChanged: TroveManagerAddressChanged,
        BorrowerOperationsAddressChanged: BorrowerOperationsAddressChanged,
    }

    #[derive(Drop, starknet::Event)]
    pub struct TroveManagerAddressChanged {
        pub new_trove_manager_address: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    pub struct BorrowerOperationsAddressChanged {
        pub new_borrower_operations_address: ContractAddress,
    }

    ////////////////////////////////////////////////////////////////
    //                        CONSTRUCTOR                         //
    ////////////////////////////////////////////////////////////////

    #[constructor]
    fn constructor(ref self: ContractState, addresses_registry: ContractAddress) {
        // Technically, this is not needed as long as ROOT_NODE_ID is 0, but it doesn't hurt
        self.nodes.entry(ROOT_NODE_ID).next_id.write(ROOT_NODE_ID);
        self.nodes.entry(ROOT_NODE_ID).prev_id.write(ROOT_NODE_ID);

        let addresses_registry = IAddressesRegistryDispatcher {
            contract_address: addresses_registry,
        };

        self.trove_manager.write(addresses_registry.get_trove_manager());
        self.borrower_operations.write(addresses_registry.get_borrower_operations());

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
    impl ISortedTrovesImpl of ISortedTroves<ContractState> {
        // TODO: remove
        fn set_addresses(ref self: ContractState, addresses_registry: ContractAddress) {
            let addresses_registry_instance = IAddressesRegistryDispatcher {
                contract_address: addresses_registry,
            };

            self.borrower_operations.write(addresses_registry_instance.get_borrower_operations());
            self.trove_manager.write(addresses_registry_instance.get_trove_manager());
        }

        // Add a trove to the list.
        fn insert(
            ref self: ContractState,
            id: u256,
            annual_interest_rate: u256,
            prev_id: u256,
            next_id: u256,
        ) {
            _require_caller_is_borrower_operations(@self);
            assert(!_contains(@self, id), 'ST: node already in list');
            assert(id != ROOT_NODE_ID, 'ST: id cannot be ROOT_NODE_ID');

            _insert_slice(
                ref self, self.trove_manager.read(), id, id, annual_interest_rate, prev_id, next_id,
            );
            self.nodes.entry(id).exists.write(true);
            self.size.write(self.size.read() + 1);
        }

        // Remove a non-batched Trove from the list
        fn remove(ref self: ContractState, id: u256) {
            _require_caller_is_BOorTM(@self);
            assert(_contains(@self, id), 'ST: id not in list');
            assert(!_is_batched_node(@self, id), 'ST: id is batched');

            _remove_slice(ref self, id, id);

            self.nodes.entry(id).exists.write(false);
            self.nodes.entry(id).batch_id.write(0.try_into().unwrap());
            self.nodes.entry(id).next_id.write(UNINITIALIZED_ID);
            self.nodes.entry(id).prev_id.write(UNINITIALIZED_ID);
            self.size.write(self.size.read() - 1);
        }

        // Re-insert an entire Batch of Troves at a new position, based on their new annual interest
        // rate
        fn re_insert_batch(
            ref self: ContractState,
            batch_id: ContractAddress,
            new_annual_interest_rate: u256,
            prev_id: u256,
            next_id: u256,
        ) {
            let batch = self.batches.entry(batch_id).read();

            _require_caller_is_borrower_operations(@self);
            assert(batch.head != UNINITIALIZED_ID, 'ST: List does not contain batch');

            _re_insert_slice(
                ref self,
                self.trove_manager.read(),
                batch.head,
                batch.tail,
                new_annual_interest_rate,
                prev_id,
                next_id,
            );
        }

        // Add a Trove to a Batch within the list
        fn insert_into_batch(
            ref self: ContractState,
            trove_id: u256,
            batch_id: ContractAddress,
            annual_interest_rate: u256,
            prev_id: u256,
            next_id: u256,
        ) {
            _require_caller_is_borrower_operations(@self);
            assert(!_contains(@self, trove_id), 'ST: node already in list');
            assert(trove_id != ROOT_NODE_ID, 'ST: trove_id cannot be root id');
            assert(batch_id != 0.try_into().unwrap(), 'ST: batch_id cannot be 0');

            let batch_tail = self.batches.entry(batch_id).tail.read();

            if (batch_tail == UNINITIALIZED_ID) {
                _insert_slice(
                    ref self,
                    self.trove_manager.read(),
                    trove_id,
                    trove_id,
                    annual_interest_rate,
                    prev_id,
                    next_id,
                );
                // Initialize the batch by setting both its head & tail to its singular node
                self.batches.entry(batch_id).head.write(trove_id);
                // (Tail will be set outside the "if")
            } else {
                _insert_slice_into_verified_position(
                    ref self,
                    trove_id,
                    trove_id,
                    batch_tail,
                    self.nodes.entry(batch_tail).next_id.read(),
                );
            }

            self.batches.entry(batch_id).tail.write(trove_id);
            self.nodes.entry(trove_id).batch_id.write(batch_id);
            self.nodes.entry(trove_id).exists.write(true);
            self.size.write(self.size.read() + 1);
        }

        // Remove a Trove from a Batch within the list
        fn remove_from_batch(ref self: ContractState, id: u256) {
            _require_caller_is_BOorTM(@self);
            let batch_id = self.nodes.entry(id).batch_id.read();
            // batchId.isNotZero() implies that the list contains the node
            assert(batch_id != 0.try_into().unwrap(), 'ST: use remove for non batched');

            let batch: Batch = self.batches.entry(batch_id).read();

            if (batch.head == id && batch.tail == id) {
                // Remove singleton batch
                self.batches.entry(batch_id).head.write(UNINITIALIZED_ID);
                self.batches.entry(batch_id).tail.write(UNINITIALIZED_ID);
            } else if (batch.head == id) {
                self.batches.entry(batch_id).head.write(self.nodes.entry(id).next_id.read());
            } else if (batch.tail == id) {
                self.batches.entry(batch_id).tail.write(self.nodes.entry(id).prev_id.read());
            }

            _remove_slice(ref self, id, id);
            // Delete nodes[id]
            self.nodes.entry(id).exists.write(false);
            self.nodes.entry(id).batch_id.write(0.try_into().unwrap());
            self.nodes.entry(id).next_id.write(UNINITIALIZED_ID);
            self.nodes.entry(id).prev_id.write(UNINITIALIZED_ID);
            self.size.write(self.size.read() - 1);
        }

        // Re-insert a non-batched Trove at a new position, based on its new annual interest rate
        fn re_insert(
            ref self: ContractState,
            id: u256,
            new_annual_interest_rate: u256,
            prev_id: u256,
            next_id: u256,
        ) {
            _require_caller_is_borrower_operations(@self);
            assert(_contains(@self, id), 'ST: id not in list');
            assert(!_is_batched_node(@self, id), 'ST: id is batched');

            _re_insert_slice(
                ref self,
                self.trove_manager.read(),
                id,
                id,
                new_annual_interest_rate,
                prev_id,
                next_id,
            );
        }

        fn contains(self: @ContractState, id: u256) -> bool {
            _contains(self, id)
        }

        fn valid_insert_position(
            self: @ContractState,
            trove_manager: ContractAddress,
            annual_interest_rate: u256,
            prev_id: u256,
            next_id: u256,
        ) -> bool {
            _valid_insert_position(self, trove_manager, annual_interest_rate, prev_id, next_id)
        }

        fn find_insert_position(
            self: @ContractState, annual_interest_rate: u256, prev_id: u256, next_id: u256,
        ) -> (u256, u256) {
            _find_insert_position(
                self, self.trove_manager.read(), annual_interest_rate, prev_id, next_id,
            )
        }

        fn get_first(self: @ContractState) -> u256 {
            self.nodes.entry(ROOT_NODE_ID).next_id.read()
        }

        fn get_last(self: @ContractState) -> u256 {
            self.nodes.entry(ROOT_NODE_ID).prev_id.read()
        }

        fn get_next(self: @ContractState, trove_id: u256) -> u256 {
            self.nodes.entry(trove_id).next_id.read()
        }

        fn get_prev(self: @ContractState, trove_id: u256) -> u256 {
            self.nodes.entry(trove_id).prev_id.read()
        }

        fn get_batch(self: @ContractState, batch_id: ContractAddress) -> Batch {
            self.batches.entry(batch_id).read()
        }

        fn get_node(self: @ContractState, id: u256) -> Node {
            self.nodes.entry(id).read()
        }

        fn get_size(self: @ContractState) -> u256 {
            self.size.read()
        }

        fn get_trove_manager(self: @ContractState) -> ContractAddress {
            self.trove_manager.read()
        }

        fn get_borrower_operations(self: @ContractState) -> ContractAddress {
            self.borrower_operations.read()
        }

        fn is_batched_node(self: @ContractState, id: u256) -> bool {
            self.nodes.entry(id).batch_id.read() != 0.try_into().unwrap()
        }

        fn is_empty_batch(self: @ContractState, batch_id: ContractAddress) -> bool {
            self.batches.entry(batch_id).head.read() == UNINITIALIZED_ID
        }

        fn is_empty(self: @ContractState) -> bool {
            self.size.read() == 0
        }
    }

    ////////////////////////////////////////////////////////////////
    //                     INTERNAL FUNCTIONS                     //
    ////////////////////////////////////////////////////////////////

    fn _contains(self: @ContractState, id: u256) -> bool {
        self.nodes.entry(id).exists.read()
    }

    fn _insert_slice(
        ref self: ContractState,
        trove_manager: ContractAddress,
        slice_head: u256,
        slice_tail: u256,
        annual_interest_rate: u256,
        prev_id: u256,
        next_id: u256,
    ) {
        let mut new_prev_id = prev_id;
        let mut new_next_id = next_id;
        if (!_valid_insert_position(@self, trove_manager, annual_interest_rate, prev_id, next_id)) {
            // Sender's hint was not a valid insert position
            // Use sender's hint to find a valid insert position
            let (new_prev_id_, new_next_id_) = _find_insert_position(
                @self, trove_manager, annual_interest_rate, prev_id, next_id,
            );
            new_prev_id = new_prev_id_;
            new_next_id = new_next_id_;
        }

        _insert_slice_into_verified_position(
            ref self, slice_head, slice_tail, new_prev_id, new_next_id,
        );
    }

    // Re-insert a non-batched Trove at a new position, based on its new annual interest rate
    fn _re_insert_slice(
        ref self: ContractState,
        trove_manager: ContractAddress,
        slice_head: u256,
        slice_tail: u256,
        annual_interest_rate: u256,
        prev_id: u256,
        next_id: u256,
    ) {
        let mut new_prev_id = prev_id;
        let mut new_next_id = next_id;
        if (!_valid_insert_position(
            @self, trove_manager, annual_interest_rate, new_prev_id, new_next_id,
        )) {
            // Sender's hint was not a valid insert position
            // Use sender's hint to find a valid insert position
            let (new_prev_id_, new_next_id_) = _find_insert_position(
                @self, trove_manager, annual_interest_rate, new_prev_id, new_next_id,
            );
            new_prev_id = new_prev_id_;
            new_next_id = new_next_id_;
        }

        // Check that the new insert position isn't the same as the existing one
        if (new_next_id != slice_head && new_prev_id != slice_tail) {
            _remove_slice(ref self, slice_head, slice_tail);
            _insert_slice_into_verified_position(
                ref self, slice_head, slice_tail, new_prev_id, new_next_id,
            );
        }
    }

    // Remove the entire slice between `_sliceHead` and `_sliceTail` from the list while keeping
    // the removed nodes connected to each other, such that they can be reinserted into a different
    // position with `_insertSlice()`.
    // Can be used to remove a single node by passing its ID as both `_sliceHead` and `_sliceTail`.
    fn _remove_slice(ref self: ContractState, slice_head: u256, slice_tail: u256) {
        let prev_id = self.nodes.entry(slice_head).prev_id.read();
        let next_id = self.nodes.entry(slice_tail).next_id.read();
        self.nodes.entry(prev_id).next_id.write(self.nodes.entry(slice_tail).next_id.read());
        self.nodes.entry(next_id).prev_id.write(self.nodes.entry(slice_head).prev_id.read());
    }

    // Check if a pair of nodes is a valid insertion point for a new node with the given interest
    // rate
    fn _valid_insert_position(
        self: @ContractState,
        trove_manager: ContractAddress,
        annual_interest_rate: u256,
        prev_id: u256,
        next_id: u256,
    ) -> bool {
        let trove_manager = ITroveManagerDispatcher { contract_address: trove_manager };

        let prev_batch_id = self.nodes.entry(prev_id).batch_id.read();

        // `(_prevId, _nextId)` is a valid insert position if:
        // They are adjacent nodes in the list
        return (self.nodes.entry(prev_id).next_id.read() == next_id
            && self.nodes.entry(next_id).prev_id.read() == prev_id
            // they aren't part of the same batch
            && (prev_batch_id != self.nodes.entry(next_id).batch_id.read()
                || prev_batch_id == 0.try_into().unwrap())
            // 'annual_interest_rate' falls between the two nodes interest rates
            && (prev_id == ROOT_NODE_ID
                || trove_manager.get_trove_annual_interest_rate(prev_id) >= annual_interest_rate)
            && (next_id == ROOT_NODE_ID
                || annual_interest_rate > trove_manager.get_trove_annual_interest_rate(next_id)));
    }

    // Insert an entire list slice (such as a batch of Troves sharing the same interest rate)
    // between adjacent nodes `_prevId` and `_nextId`.
    // Can be used to insert a single node by passing its ID as both `_sliceHead` and `_sliceTail`.
    fn _insert_slice_into_verified_position(
        ref self: ContractState, slice_head: u256, slice_tail: u256, prev_id: u256, next_id: u256,
    ) {
        self.nodes.entry(prev_id).next_id.write(slice_head);
        self.nodes.entry(slice_head).prev_id.write(prev_id);
        self.nodes.entry(slice_tail).next_id.write(next_id);
        self.nodes.entry(next_id).prev_id.write(slice_tail);
    }

    // This function is optimized under the assumption that only one of the original neighbours has
    // been (re)moved.
    // In other words, we assume that the correct position can be found close to one of the two.
    // Nevertheless, the function will always find the correct position, regardless of hints or
    // interference.
    fn _find_insert_position(
        self: @ContractState,
        trove_manager_address: ContractAddress,
        annual_interest_rate: u256,
        prev_id: u256,
        next_id: u256,
    ) -> (u256, u256) {
        let trove_manager = ITroveManagerDispatcher { contract_address: trove_manager_address };

        let mut prev_id_mut = prev_id;
        let mut next_id_mut = next_id;

        if (prev_id_mut == ROOT_NODE_ID) {
            // The original correct position was found before the head of the list.
            // Assuming minimal interference, the new correct position is still close to the head.
            return _descend_list(self, trove_manager_address, annual_interest_rate, ROOT_NODE_ID);
        } else {
            if (!_contains(self, prev_id_mut)
                || trove_manager
                    .get_trove_annual_interest_rate(prev_id_mut) < annual_interest_rate) {
                // `prevId` does not exist anymore or now has a smaller interest rate than the given
                // interest rate
                prev_id_mut = BAD_HINT;
            }
        }

        if (next_id_mut == ROOT_NODE_ID) {
            // The original correct position was found after the tail of the list.
            // Assuming minimal interference, the new correct position is still close to the tail.
            return _ascend_list(self, trove_manager_address, annual_interest_rate, ROOT_NODE_ID);
        } else {
            if (!_contains(self, next_id_mut)
                || annual_interest_rate <= trove_manager
                    .get_trove_annual_interest_rate(next_id_mut)) {
                // `nextId` does not exist anymore or now has a larger interest rate than the given
                // interest rate
                next_id_mut = BAD_HINT;
            }
        }

        if (prev_id_mut == BAD_HINT && next_id_mut == BAD_HINT) {
            // Both original neighbours have been moved or removed.
            // We default to descending the list, starting from the head.
            return _descend_list(self, trove_manager_address, annual_interest_rate, ROOT_NODE_ID);
        } else if (prev_id_mut == BAD_HINT) {
            // No `prevId` for hint - ascend list starting from `nextId`
            return _ascend_list(
                self,
                trove_manager_address,
                annual_interest_rate,
                _skip_to_batch_head(self, next_id_mut),
            );
        } else if (next_id_mut == BAD_HINT) {
            // No `nextId` for hint - descend list starting from `prevId`
            return _descend_list(
                self,
                trove_manager_address,
                annual_interest_rate,
                _skip_to_batch_tail(self, prev_id_mut),
            );
        } else {
            // The correct position is still somewhere between the 2 hints, so it's not obvious
            // which of the 2 has been moved (assuming only one of them has been).
            // We simultaneously descend & ascend in the hope that one of them is very close.
            return _descend_and_ascend_list(
                self,
                trove_manager_address,
                annual_interest_rate,
                _skip_to_batch_tail(self, prev_id_mut),
                _skip_to_batch_head(self, next_id_mut),
            );
        }
    }

    fn _descend_and_ascend_list(
        self: @ContractState,
        trove_manager_address: ContractAddress,
        annual_interest_rate: u256,
        descent_start_id: u256,
        ascent_start_id: u256,
    ) -> (u256, u256) {
        let mut descent_pos: Position = Position {
            prev_id: descent_start_id, next_id: self.nodes.entry(descent_start_id).next_id.read(),
        };
        let mut ascent_pos: Position = Position {
            prev_id: self.nodes.entry(ascent_start_id).prev_id.read(), next_id: ascent_start_id,
        };

        while (true) {
            if (_descend_one(self, trove_manager_address, annual_interest_rate, ref descent_pos)) {
                return (descent_pos.prev_id, ascent_pos.next_id);
            }
            if (_ascend_one(self, trove_manager_address, annual_interest_rate, ref ascent_pos)) {
                return (descent_pos.prev_id, ascent_pos.next_id);
            }
        }

        assert(false, 'ST: should not reach');
        return (0, 0);
    }

    // Descend the list (larger interest rates to smaller interest rates) to find a valid insert
    // position TroveManager contract, passed in as param to save SLOAD’s
    // Node's annual interest rate
    // Id of node to start descending the list from
    fn _descend_list(
        self: @ContractState,
        trove_manager: ContractAddress,
        annual_interest_rate: u256,
        start_id: u256,
    ) -> (u256, u256) {
        let mut pos: Position = Position {
            prev_id: start_id, next_id: self.nodes.entry(start_id).next_id.read(),
        };

        while (!_descend_one(self, trove_manager, annual_interest_rate, ref pos)) {}
        (pos.prev_id, pos.next_id)
    }

    // Ascend the list (smaller interest rates to larger interest rates) to find a valid insert
    // position _troveManager TroveManager contract, passed in as param to save SLOAD’s
    // _annualInterestRate Node's annual interest rate``
    // _startId Id of node to start ascending the list from
    fn _ascend_list(
        self: @ContractState,
        trove_manager_address: ContractAddress,
        annual_interest_rate: u256,
        start_id: u256,
    ) -> (u256, u256) {
        let mut pos: Position = Position {
            prev_id: self.nodes.entry(start_id).prev_id.read(), next_id: start_id,
        };

        while (!_ascend_one(self, trove_manager_address, annual_interest_rate, ref pos)) {}
        (pos.prev_id, pos.next_id)
    }

    fn _descend_one(
        self: @ContractState,
        trove_manager: ContractAddress,
        annual_interest_rate: u256,
        ref pos: Position,
    ) -> bool {
        let trove_manager = ITroveManagerDispatcher { contract_address: trove_manager };

        if (pos.next_id == ROOT_NODE_ID
            || annual_interest_rate > trove_manager.get_trove_annual_interest_rate(pos.next_id)) {
            return true;
        } else {
            pos.prev_id = _skip_to_batch_tail(self, pos.next_id);
            pos.next_id = self.nodes.entry(pos.prev_id).next_id.read();
            return false;
        }
    }

    fn _ascend_one(
        self: @ContractState,
        trove_manager_address: ContractAddress,
        annual_interest_rate: u256,
        ref pos: Position,
    ) -> bool {
        let trove_manager = ITroveManagerDispatcher { contract_address: trove_manager_address };
        if (pos.prev_id == ROOT_NODE_ID
            || trove_manager.get_trove_annual_interest_rate(pos.prev_id) >= annual_interest_rate) {
            return true;
        } else {
            pos.next_id = _skip_to_batch_head(self, pos.prev_id);
            pos.prev_id = self.nodes.entry(pos.next_id).prev_id.read();
            return false;
        }
    }

    fn _skip_to_batch_tail(self: @ContractState, id: u256) -> u256 {
        let batch_id: ContractAddress = self.nodes.entry(id).batch_id.read();
        if (batch_id != 0.try_into().unwrap()) {
            let batch = self.batches.entry(batch_id).read();
            batch.tail
        } else {
            id
        }
    }

    fn _skip_to_batch_head(self: @ContractState, id: u256) -> u256 {
        let batch_id: ContractAddress = self.nodes.entry(id).batch_id.read();
        if (batch_id != 0.try_into().unwrap()) {
            let batch = self.batches.entry(batch_id).read();
            batch.head
        } else {
            id
        }
    }

    fn _is_batched_node(self: @ContractState, id: u256) -> bool {
        self.nodes.entry(id).batch_id.read() != 0.try_into().unwrap()
    }

    ////////////////////////////////////////////////////////////////
    //                     ACCESS FUNCTIONS                       //
    ////////////////////////////////////////////////////////////////

    fn _require_caller_is_borrower_operations(self: @ContractState) {
        assert(get_caller_address() == self.borrower_operations.read(), 'TM: caller is not BO');
    }

    fn _require_caller_is_BOorTM(self: @ContractState) {
        assert(
            get_caller_address() == self.borrower_operations.read()
                || get_caller_address() == self.trove_manager.read(),
            'TM: caller is not BO or TM',
        );
    }
}
