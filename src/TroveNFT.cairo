use starknet::ContractAddress;
#[starknet::interface]
pub trait ITroveNFT<TContractState> {
    fn mint(ref self: TContractState, owner: ContractAddress, trove_id: u256);
    fn burn(ref self: TContractState, trove_id: u256);
    fn get_trove_manager(self: @TContractState) -> ContractAddress;
    fn get_trove_owner(self: @TContractState, trove_id: u256) -> ContractAddress;
    fn get_metadata_nft(self: @TContractState) -> ContractAddress;
    // TODO: Remove below fix
    fn set_addresses(ref self: TContractState, addresses_registry: ContractAddress);
}

#[starknet::contract]
pub mod TroveNFT {
    use openzeppelin::introspection::src5::SRC5Component;
    use openzeppelin::introspection::src5::SRC5Component::SRC5Impl;
    use openzeppelin::token::erc721::{ERC721Component, ERC721HooksEmptyImpl};
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use starknet::{ContractAddress, get_caller_address};
    use crate::AddressesRegistry::{IAddressesRegistryDispatcher, IAddressesRegistryDispatcherTrait};
    use super::ITroveNFT;

    component!(path: ERC721Component, storage: erc721, event: ERC721Event);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);

    //////////////////////////////////////////////////////////////
    //                          STORAGE                         //
    //////////////////////////////////////////////////////////////

    #[storage]
    struct Storage {
        trove_manager: ContractAddress,
        coll_token: ContractAddress,
        metadata_nft: ContractAddress,
        bitusd: ContractAddress,
        #[substorage(v0)]
        erc721: ERC721Component::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
    }

    //////////////////////////////////////////////////////////////
    //                          EVENTS                          //
    //////////////////////////////////////////////////////////////

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        #[flat]
        ERC721Event: ERC721Component::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
    }

    ////////////////////////////////////////////////////////////////
    //                 EXPOSE COMPONENT FUNCTIONS                 //
    ////////////////////////////////////////////////////////////////

    #[abi(embed_v0)]
    impl ERC721MetadataImpl = ERC721Component::ERC721MetadataImpl<ContractState>;
    #[abi(embed_v0)]
    impl ERC721Impl = ERC721Component::ERC721Impl<ContractState>;

    impl ERC721InternalImpl = ERC721Component::InternalImpl<ContractState>;

    //////////////////////////////////////////////////////////////
    //                        CONSTRUCTOR                       //
    //////////////////////////////////////////////////////////////

    #[constructor]
    fn constructor(
        ref self: ContractState,
        addresses_registry: ContractAddress,
        name: ByteArray,
        symbol: ByteArray,
        uri: ByteArray,
    ) {
        let addresses_registry_contract = IAddressesRegistryDispatcher {
            contract_address: addresses_registry,
        };

        self.erc721.initializer(name, symbol, uri);

        self.trove_manager.write(addresses_registry_contract.get_trove_manager());
        self.coll_token.write(addresses_registry_contract.get_coll_token());
        self.metadata_nft.write(addresses_registry_contract.get_metadata_nft());
        self.bitusd.write(addresses_registry_contract.get_bitusd_token());
    }

    //////////////////////////////////////////////////////////////
    //                        EXTERNAL FUNCTIONS                //
    //////////////////////////////////////////////////////////////

    #[abi(embed_v0)]
    impl ITroveNFTImpl of ITroveNFT<ContractState> {
        fn mint(ref self: ContractState, owner: ContractAddress, trove_id: u256) {
            _require_caller_is_trove_manager(@self);
            // TODO: Use safe_mint or not needed ?
            self.erc721.mint(owner, trove_id);
        }

        fn burn(ref self: ContractState, trove_id: u256) {
            _require_caller_is_trove_manager(@self);
            self.erc721.burn(trove_id);
        }

        fn get_trove_manager(self: @ContractState) -> ContractAddress {
            self.trove_manager.read()
        }

        fn get_metadata_nft(self: @ContractState) -> ContractAddress {
            self.metadata_nft.read()
        }

        fn get_trove_owner(self: @ContractState, trove_id: u256) -> ContractAddress {
            self.erc721.owner_of(trove_id)
        }

        // TODO: Remove below fix
        fn set_addresses(ref self: ContractState, addresses_registry: ContractAddress) {
            let addresses_registry_contract = IAddressesRegistryDispatcher {
                contract_address: addresses_registry,
            };

            self.trove_manager.write(addresses_registry_contract.get_trove_manager());
            self.coll_token.write(addresses_registry_contract.get_coll_token());
            self.metadata_nft.write(addresses_registry_contract.get_metadata_nft());
            self.bitusd.write(addresses_registry_contract.get_bitusd_token());
        }
    }

    //////////////////////////////////////////////////////////////
    //                        ACCESS FUNCTIONS                  //
    //////////////////////////////////////////////////////////////

    fn _require_caller_is_trove_manager(self: @ContractState) {
        assert(get_caller_address() == self.trove_manager.read(), 'TNFT: Caller is not TM');
    }
}
