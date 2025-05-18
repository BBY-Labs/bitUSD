use starknet::ContractAddress;

#[starknet::interface]
pub trait IBitUSD<TContractState> {
    fn mint(ref self: TContractState, recipient: ContractAddress, amount: u256);
    fn burn(ref self: TContractState, account: ContractAddress, amount: u256);
    fn set_branch_addresses(
        ref self: TContractState,
        trove_manager: ContractAddress,
        stability_pool: ContractAddress,
        borrower_operations: ContractAddress,
        active_pool: ContractAddress,
    );
    fn set_collateral_registry(ref self: TContractState, collateral_registry: ContractAddress);
    fn send_to_pool(
        ref self: TContractState, sender: ContractAddress, pool: ContractAddress, amount: u256,
    );
    fn return_from_pool(
        ref self: TContractState, pool: ContractAddress, receiver: ContractAddress, amount: u256,
    );
}

/// --- Functionality added specific to the bitUSD Token ---
/// 1) Transfer protection: blacklist of addresses that are invalid recipients (i.e. core Liquity
/// contracts) in external transfer() and transferFrom() calls. The purpose is to protect users from
/// losing tokens by mistakenly sending bitUSD directly to a Liquity core contract, when they should
/// rather call the right function.
///
/// 2) sendToPool() and returnFromPool(): functions callable only Liquity core contracts, which move
/// bitUSD tokens between Liquity <-> user.
#[starknet::contract]
pub mod BitUSD {
    use core::traits::TryInto;
    use openzeppelin::access::ownable::OwnableComponent;
    use openzeppelin::token::erc20::interface::IERC20;
    use openzeppelin::token::erc20::{ERC20Component, ERC20HooksEmptyImpl};
    use openzeppelin::utils::cryptography::nonces::NoncesComponent;
    use openzeppelin::utils::cryptography::snip12::SNIP12Metadata;
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };
    use starknet::{ContractAddress, get_caller_address, get_contract_address};
    use super::IBitUSD;

    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);
    component!(path: ERC20Component, storage: erc20, event: ERC20Event);
    component!(path: NoncesComponent, storage: nonces, event: NoncesEvent);

    //////////////////////////////////////////////////////////////
    //                          STORAGE                         //
    //////////////////////////////////////////////////////////////

    #[storage]
    pub struct Storage {
        collateral_registry_address: ContractAddress,
        trove_manager_addresses: Map<ContractAddress, bool>,
        stability_pool_addresses: Map<ContractAddress, bool>,
        borrower_operations_addresses: Map<ContractAddress, bool>,
        active_pool_addresses: Map<ContractAddress, bool>,
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        #[substorage(v0)]
        erc20: ERC20Component::Storage,
        #[substorage(v0)]
        nonces: NoncesComponent::Storage,
    }

    //////////////////////////////////////////////////////////////
    //                          EVENTS                          //
    //////////////////////////////////////////////////////////////

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        CollateralRegistryAddressChanged: CollateralRegistryAddressChanged,
        TroveManagerAddressAdded: TroveManagerAddressAdded,
        StabilityPoolAddressAdded: StabilityPoolAddressAdded,
        BorrowerOperationsAddressAdded: BorrowerOperationsAddressAdded,
        ActivePoolAddressAdded: ActivePoolAddressAdded,
        #[flat]
        OwnableEvent: OwnableComponent::Event,
        #[flat]
        ERC20Event: ERC20Component::Event,
        #[flat]
        NoncesEvent: NoncesComponent::Event,
    }

    #[derive(Drop, starknet::Event)]
    pub struct CollateralRegistryAddressChanged {
        pub new_collateral_registry: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    pub struct TroveManagerAddressAdded {
        pub new_trove_manager: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    pub struct StabilityPoolAddressAdded {
        pub new_stability_pool: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    pub struct BorrowerOperationsAddressAdded {
        pub new_borrower_operations: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    pub struct ActivePoolAddressAdded {
        pub new_active_pool: ContractAddress,
    }

    ////////////////////////////////////////////////////////////////
    //                 EXPOSE COMPONENT FUNCTIONS                 //
    ////////////////////////////////////////////////////////////////

    #[abi(embed_v0)]
    impl OwnableImpl = OwnableComponent::OwnableImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;

    #[abi(embed_v0)]
    impl ERC20MetadataImpl = ERC20Component::ERC20MetadataImpl<ContractState>;
    #[abi(embed_v0)]
    impl ERC20PermitImpl = ERC20Component::ERC20PermitImpl<ContractState>;

    // impl ERC20MixinImpl = ERC20Component::ERC20MixinImpl<ContractState>;
    impl ERC20InternalImpl = ERC20Component::InternalImpl<ContractState>;


    ////////////////////////////////////////////////////////////////
    //                        CONSTRUCTOR                         //
    ////////////////////////////////////////////////////////////////

    #[constructor]
    fn constructor(
        ref self: ContractState, owner: ContractAddress, name: ByteArray, symbol: ByteArray,
    ) {
        self.ownable.initializer(owner);
        self.erc20.initializer(name, symbol);
    }

    ////////////////////////////////////////////////////////////////
    //                     EXTERNAL FUNCTIONS                     //
    ////////////////////////////////////////////////////////////////

    #[abi(embed_v0)]
    impl BitUSDERC20Impl of IERC20<ContractState> {
        fn transfer(ref self: ContractState, recipient: ContractAddress, amount: u256) -> bool {
            _require_valid_recipient(recipient);
            self.erc20.transfer(recipient, amount)
        }

        fn transfer_from(
            ref self: ContractState,
            sender: ContractAddress,
            recipient: ContractAddress,
            amount: u256,
        ) -> bool {
            _require_valid_recipient(recipient);
            self.erc20.transfer_from(sender, recipient, amount)
        }

        fn total_supply(self: @ContractState) -> u256 {
            self.erc20.total_supply()
        }

        fn balance_of(self: @ContractState, account: ContractAddress) -> u256 {
            self.erc20.balance_of(account)
        }

        fn allowance(
            self: @ContractState, owner: ContractAddress, spender: ContractAddress,
        ) -> u256 {
            self.erc20.allowance(owner, spender)
        }

        fn approve(ref self: ContractState, spender: ContractAddress, amount: u256) -> bool {
            self.erc20.approve(spender, amount)
        }
    }

    #[abi(embed_v0)]
    impl IBitUSDImpl of IBitUSD<ContractState> {
        fn mint(ref self: ContractState, recipient: ContractAddress, amount: u256) {
            _require_caller_is_BO_or_AP(@self);
            self.erc20.mint(recipient, amount);
        }

        fn burn(ref self: ContractState, account: ContractAddress, amount: u256) {
            _require_caller_is_CR_or_BO_or_TM_or_SP(@self);
            self.erc20.burn(account, amount);
        }

        fn set_branch_addresses(
            ref self: ContractState,
            trove_manager: ContractAddress,
            stability_pool: ContractAddress,
            borrower_operations: ContractAddress,
            active_pool: ContractAddress,
        ) {
            self.ownable.assert_only_owner();

            self.trove_manager_addresses.write(trove_manager, true);
            self.emit(event: TroveManagerAddressAdded { new_trove_manager: trove_manager });

            self.stability_pool_addresses.write(stability_pool, true);
            self.emit(event: StabilityPoolAddressAdded { new_stability_pool: stability_pool });

            self.borrower_operations_addresses.write(borrower_operations, true);
            self
                .emit(
                    event: BorrowerOperationsAddressAdded {
                        new_borrower_operations: borrower_operations,
                    },
                );

            self.active_pool_addresses.write(active_pool, true);
            self.emit(event: ActivePoolAddressAdded { new_active_pool: active_pool });
        }

        fn set_collateral_registry(ref self: ContractState, collateral_registry: ContractAddress) {
            self.ownable.assert_only_owner();
            self.collateral_registry_address.write(collateral_registry);
            self
                .emit(
                    event: CollateralRegistryAddressChanged {
                        new_collateral_registry: collateral_registry,
                    },
                );

            self.ownable.renounce_ownership();
        }

        fn send_to_pool(
            ref self: ContractState, sender: ContractAddress, pool: ContractAddress, amount: u256,
        ) {
            _require_caller_is_stability_pool(@self);
            self.erc20._transfer(sender, pool, amount);
        }

        fn return_from_pool(
            ref self: ContractState, pool: ContractAddress, receiver: ContractAddress, amount: u256,
        ) {
            _require_caller_is_stability_pool(@self);
            self.erc20._transfer(pool, receiver, amount);
        }
    }

    ////////////////////////////////////////////////////////////////
    //                     INTERNAL FUNCTIONS                     //
    ////////////////////////////////////////////////////////////////

    fn _require_caller_is_BO_or_AP(self: @ContractState) {
        let caller = get_caller_address();
        let is_BO = self.borrower_operations_addresses.read(caller);
        let is_AP = self.active_pool_addresses.read(caller);
        assert(is_BO || is_AP, 'BU: Caller is not BO or AP');
    }

    fn _require_caller_is_CR_or_BO_or_TM_or_SP(self: @ContractState) {
        let caller = get_caller_address();
        let is_CR = self.collateral_registry_address.read() == caller;
        let is_BO = self.borrower_operations_addresses.read(caller);
        let is_TM = self.trove_manager_addresses.read(caller);
        let is_SP = self.stability_pool_addresses.read(caller);

        assert(is_CR || is_BO || is_TM || is_SP, 'BU: Caller is not CR,BO,TM,SP');
    }

    fn _require_valid_recipient(recipient: ContractAddress) {
        let zero_address: ContractAddress = 0.try_into().unwrap();
        let is_zero = recipient == zero_address;
        let is_self = recipient == get_contract_address();
        assert(!is_zero && !is_self, 'BU: Recipient is zero or self');
    }

    fn _require_caller_is_stability_pool(self: @ContractState) {
        let caller = get_caller_address();
        let is_SP = self.stability_pool_addresses.read(caller);
        assert(is_SP == true, 'BU: Caller is not SP');
    }


    ////////////////////////////////////////////////////////////////
    //                       SNIP12 IMPL                          //
    ////////////////////////////////////////////////////////////////

    impl Snip12MetadataImpl of SNIP12Metadata {
        fn name() -> felt252 {
            'BitUSD'
        }

        fn version() -> felt252 {
            '1'
        }
    }
}

