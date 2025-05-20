use starknet::ContractAddress;

#[starknet::interface]
pub trait IAddressesRegistry<TContractState> {
    fn set_addresses(
        ref self: TContractState,
        active_pool: ContractAddress,
        default_pool: ContractAddress,
        price_feed: ContractAddress,
        hint_helpers: ContractAddress,
        multi_trove_getter: ContractAddress,
        metadata_nft: ContractAddress,
        eth: ContractAddress,
        borrower_operations: ContractAddress,
        trove_manager: ContractAddress,
        trove_nft: ContractAddress,
        gas_pool: ContractAddress,
        coll_surplus_pool: ContractAddress,
        sorted_troves: ContractAddress,
        collateral_registry: ContractAddress,
        bitusd: ContractAddress,
        interest_router: ContractAddress,
        stability_pool: ContractAddress,
        coll_token: ContractAddress,
    );

    fn get_active_pool(self: @TContractState) -> ContractAddress;
    fn get_default_pool(self: @TContractState) -> ContractAddress;
    fn get_price_pool(self: @TContractState) -> ContractAddress;
    fn get_coll_token(self: @TContractState) -> ContractAddress;
    fn get_trove_manager(self: @TContractState) -> ContractAddress;
    fn get_borrower_operations(self: @TContractState) -> ContractAddress;
    fn get_interest_router(self: @TContractState) -> ContractAddress;
    fn get_stability_pool(self: @TContractState) -> ContractAddress;
    fn get_bitusd_token(self: @TContractState) -> ContractAddress;
    fn get_liquidation_penalty_sp(self: @TContractState) -> u256;
    fn get_liquidation_penalty_redistribution(self: @TContractState) -> u256;
    fn get_CCR(self: @TContractState) -> u256;
    fn get_SCR(self: @TContractState) -> u256;
    fn get_MCR(self: @TContractState) -> u256;
    fn get_BCR(self: @TContractState) -> u256;
    fn get_trove_nft(self: @TContractState) -> ContractAddress;
    fn get_gas_pool(self: @TContractState) -> ContractAddress;
    fn get_coll_surplus_pool(self: @TContractState) -> ContractAddress;
    fn get_sorted_troves(self: @TContractState) -> ContractAddress;
    fn get_collateral_registry(self: @TContractState) -> ContractAddress;
    fn get_eth(self: @TContractState) -> ContractAddress;
    fn get_hint_helpers(self: @TContractState) -> ContractAddress;
    fn get_multi_trove_getter(self: @TContractState) -> ContractAddress;
    fn get_metadata_nft(self: @TContractState) -> ContractAddress;
    fn get_price_feed(self: @TContractState) -> ContractAddress;
}

#[starknet::contract]
pub mod AddressesRegistry {
    use openzeppelin::access::ownable::OwnableComponent;
    use starknet::ContractAddress;
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use crate::dependencies::Constants::Constants::{
        MAX_LIQUIDATION_PENALTY_REDISTRIBUTION, MIN_LIQUIDATION_PENALTY_SP, _100PCT, _1PCT,
    };
    use super::IAddressesRegistry;

    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);

    //////////////////////////////////////////////////////////////
    //                          STORAGE                         //
    //////////////////////////////////////////////////////////////

    #[storage]
    struct Storage {
        owner: ContractAddress,
        // Critical system collateral ratio. If the system's total collateral ratio (TCR) falls
        // below the CCR, some borrowing operation restrictions are applied.
        CCR: u256,
        // Minimum collateral ratio for individual troves.
        MCR: u256,
        // Extra buffer of collateral ratio to join a batch or adjust a trove inside a batch (on top
        // of MCR).
        BCR: u256,
        // Shutdown system collateral ratio. If the system's total collateral ratio (TCR) for a
        // given collateral falls below the SCR, the protocol triggers the shutdown of the borrow
        // market and permanently disables all borrowing operations except for closing Troves.
        SCR: u256,
        // Liquidation penalty for troves offset to the SP.
        liquidation_penalty_sp: u256,
        // Liquidation penalty for troves redistributed.
        liquidation_penalty_redistribution: u256,
        coll_token: ContractAddress,
        trove_manager: ContractAddress,
        borrower_operations: ContractAddress,
        active_pool: ContractAddress,
        default_pool: ContractAddress,
        price_feed: ContractAddress,
        stability_pool: ContractAddress,
        bit_usd: ContractAddress,
        interest_router: ContractAddress,
        trove_nft: ContractAddress,
        gas_pool: ContractAddress,
        coll_surplus_pool: ContractAddress,
        sorted_troves: ContractAddress,
        collateral_registry: ContractAddress,
        eth: ContractAddress,
        hint_helpers: ContractAddress,
        multi_trove_getter: ContractAddress,
        metadata_nft: ContractAddress,
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
    }

    //////////////////////////////////////////////////////////////
    //                          EVENTS                          //
    //////////////////////////////////////////////////////////////

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        OwnableEvent: OwnableComponent::Event,
    }

    ////////////////////////////////////////////////////////////////
    //                 EXPOSE COMPONENT FUNCTIONS                 //
    ////////////////////////////////////////////////////////////////

    #[abi(embed_v0)]
    impl OwnableImpl = OwnableComponent::OwnableImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;

    ////////////////////////////////////////////////////////////////
    //                        CONSTRUCTOR                         //
    ////////////////////////////////////////////////////////////////

    #[constructor]
    fn constructor(
        ref self: ContractState,
        owner: ContractAddress,
        ccr: u256,
        mcr: u256,
        bcr: u256,
        scr: u256,
        liquidation_penalty_sp: u256,
        liquidation_penalty_redistribution: u256,
    ) {
        assert(ccr > _100PCT && ccr < 2 * _100PCT, 'AR: InvalidCCR');
        assert(mcr > _100PCT && mcr < 2 * _100PCT, 'AR: InvalidMCR');
        assert(bcr >= _1PCT * 5 && bcr < _1PCT * 50, 'AR: InvalidBCR');
        assert(scr > _100PCT && scr < 2 * _100PCT, 'AR: InvalidSCR');

        assert(liquidation_penalty_sp >= MIN_LIQUIDATION_PENALTY_SP, 'AR: SPPenaltyTooLow');
        assert(
            liquidation_penalty_sp <= liquidation_penalty_redistribution, 'AR: SPPenaltyGtRedist',
        );
        assert(
            liquidation_penalty_redistribution <= MAX_LIQUIDATION_PENALTY_REDISTRIBUTION,
            'AR: RedistPenaltyTooHigh',
        );

        self.ownable.initializer(owner);
        self.CCR.write(ccr);
        self.MCR.write(mcr);
        self.BCR.write(bcr);
        self.SCR.write(scr);
        self.liquidation_penalty_sp.write(liquidation_penalty_sp);
        self.liquidation_penalty_redistribution.write(liquidation_penalty_redistribution);
    }

    ////////////////////////////////////////////////////////////////
    //                     EXTERNAL FUNCTIONS                     //
    ////////////////////////////////////////////////////////////////

    #[abi(embed_v0)]
    impl AddressesRegistryImpl of IAddressesRegistry<ContractState> {
        fn set_addresses(
            ref self: ContractState,
            active_pool: ContractAddress,
            default_pool: ContractAddress,
            price_feed: ContractAddress,
            hint_helpers: ContractAddress,
            multi_trove_getter: ContractAddress,
            metadata_nft: ContractAddress,
            eth: ContractAddress,
            borrower_operations: ContractAddress,
            trove_manager: ContractAddress,
            trove_nft: ContractAddress,
            gas_pool: ContractAddress,
            coll_surplus_pool: ContractAddress,
            sorted_troves: ContractAddress,
            collateral_registry: ContractAddress,
            bitusd: ContractAddress,
            interest_router: ContractAddress,
            stability_pool: ContractAddress,
            coll_token: ContractAddress,
        ) {
            self.ownable.assert_only_owner();

            self.active_pool.write(active_pool);
            self.default_pool.write(default_pool);
            self.price_feed.write(price_feed);
            self.hint_helpers.write(hint_helpers);
            self.multi_trove_getter.write(multi_trove_getter);
            self.metadata_nft.write(metadata_nft);
            self.eth.write(eth);
            self.borrower_operations.write(borrower_operations);
            self.trove_manager.write(trove_manager);
            self.trove_nft.write(trove_nft);
            self.gas_pool.write(gas_pool);
            self.coll_surplus_pool.write(coll_surplus_pool);
            self.sorted_troves.write(sorted_troves);
            self.collateral_registry.write(collateral_registry);
            self.bit_usd.write(bitusd);
            self.interest_router.write(interest_router);
            self.stability_pool.write(stability_pool);
            self.coll_token.write(coll_token);
            self.ownable.renounce_ownership();
        }

        //////////////////////////////////////////////////////////////
        //                     VIEW FUNCTIONS                       //
        //////////////////////////////////////////////////////////////

        fn get_active_pool(self: @ContractState) -> ContractAddress {
            self.active_pool.read()
        }

        fn get_default_pool(self: @ContractState) -> ContractAddress {
            self.default_pool.read()
        }

        fn get_price_pool(self: @ContractState) -> ContractAddress {
            self.price_feed.read()
        }

        fn get_coll_token(self: @ContractState) -> ContractAddress {
            self.coll_token.read()
        }

        fn get_trove_manager(self: @ContractState) -> ContractAddress {
            self.trove_manager.read()
        }

        fn get_borrower_operations(self: @ContractState) -> ContractAddress {
            self.borrower_operations.read()
        }

        fn get_interest_router(self: @ContractState) -> ContractAddress {
            self.interest_router.read()
        }

        fn get_stability_pool(self: @ContractState) -> ContractAddress {
            self.stability_pool.read()
        }

        fn get_bitusd_token(self: @ContractState) -> ContractAddress {
            self.bit_usd.read()
        }

        fn get_liquidation_penalty_sp(self: @ContractState) -> u256 {
            self.liquidation_penalty_sp.read()
        }

        fn get_liquidation_penalty_redistribution(self: @ContractState) -> u256 {
            self.liquidation_penalty_redistribution.read()
        }

        fn get_CCR(self: @ContractState) -> u256 {
            self.CCR.read()
        }
        fn get_SCR(self: @ContractState) -> u256 {
            self.SCR.read()
        }
        fn get_MCR(self: @ContractState) -> u256 {
            self.MCR.read()
        }
        fn get_BCR(self: @ContractState) -> u256 {
            self.BCR.read()
        }

        fn get_trove_nft(self: @ContractState) -> ContractAddress {
            self.trove_nft.read()
        }

        fn get_gas_pool(self: @ContractState) -> ContractAddress {
            self.gas_pool.read()
        }

        fn get_coll_surplus_pool(self: @ContractState) -> ContractAddress {
            self.coll_surplus_pool.read()
        }

        fn get_sorted_troves(self: @ContractState) -> ContractAddress {
            self.sorted_troves.read()
        }

        fn get_collateral_registry(self: @ContractState) -> ContractAddress {
            self.collateral_registry.read()
        }

        fn get_eth(self: @ContractState) -> ContractAddress {
            self.eth.read()
        }

        fn get_hint_helpers(self: @ContractState) -> ContractAddress {
            self.hint_helpers.read()
        }

        fn get_multi_trove_getter(self: @ContractState) -> ContractAddress {
            self.multi_trove_getter.read()
        }

        fn get_metadata_nft(self: @ContractState) -> ContractAddress {
            self.metadata_nft.read()
        }

        fn get_price_feed(self: @ContractState) -> ContractAddress {
            self.price_feed.read()
        }
    }
}
