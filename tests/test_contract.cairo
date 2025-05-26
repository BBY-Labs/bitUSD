// Import library
use bit_usd::ActivePool::{IActivePoolDispatcher, IActivePoolDispatcherTrait};
use bit_usd::AddressesRegistry::{IAddressesRegistryDispatcher, IAddressesRegistryDispatcherTrait};
use bit_usd::BitUSD::{IBitUSDDispatcher, IBitUSDDispatcherTrait};
use bit_usd::BorrowerOperations::{
    IBorrowerOperationsDispatcher, IBorrowerOperationsDispatcherTrait,
};
use bit_usd::CollSurplusPool::{ICollSurplusPoolDispatcher, ICollSurplusPoolDispatcherTrait};
use bit_usd::SortedTroves::{ISortedTrovesDispatcher, ISortedTrovesDispatcherTrait};
use bit_usd::StabilityPool::{IStabilityPoolDispatcher, IStabilityPoolDispatcherTrait};
use bit_usd::TroveManager::{ITroveManagerDispatcher, ITroveManagerDispatcherTrait};
use bit_usd::TroveNFT::{ITroveNFTDispatcher, ITroveNFTDispatcherTrait};
use bit_usd::mocks::TBTC::{ITBTCDispatcher, ITBTCDispatcherTrait};
use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, declare, start_cheat_caller_address,
    stop_cheat_caller_address,
};
use starknet::ContractAddress;

// Declare users.
fn OWNER() -> ContractAddress {
    'OWNER'.try_into().expect('')
    //'OWNER'.try_into().unwrap()
}

fn USER_1() -> ContractAddress {
    'USER1'.try_into().expect('')
}

// Constants
const DECIMAL_PRECISION: u256 = 1000000000000000000; // 10^18
const ONE_PERCENT: u256 = DECIMAL_PRECISION / 100; // 1%
const MCR_TBTC: u256 = 110 * ONE_PERCENT; // 110%
const CCR_TBTC: u256 = 150 * ONE_PERCENT; // 150%
const BCR_ALL: u256 = 10 * ONE_PERCENT; // 110%
const SCR_TBTC: u256 = 110 * ONE_PERCENT; // 110%
const LIQUIDATION_PENALTY_SP_TBTC: u256 = 5 * ONE_PERCENT; // 5%
const LIQUIDATION_PENALTY_REDISTRIBUTION_TBTC: u256 = 10 * ONE_PERCENT; // 10%

const ETH_SEPOLIA_FELT: felt252 =
    0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7;

// Util deploy function
fn __deploy__() -> (IBorrowerOperationsDispatcher, ITBTCDispatcher, IBitUSDDispatcher) {
    // declare contract classes
    let borrower_operations_contract_class = declare("BorrowerOperations")
        .unwrap()
        .contract_class();
    let active_pool_contract_class = declare("ActivePool").unwrap().contract_class();
    let addresses_registry_contract_class = declare("AddressesRegistry").unwrap().contract_class();
    let bit_usd_contract_class = declare("BitUSD").unwrap().contract_class();
    let coll_surplus_pool_contract_class = declare("CollSurplusPool").unwrap().contract_class();
    let price_feed_mock_contract_class = declare("PriceFeedMock").unwrap().contract_class();
    let sorted_troves_contract_class = declare("SortedTroves").unwrap().contract_class();
    let trove_manager_contract_class = declare("TroveManager").unwrap().contract_class();
    let default_pool_contract_class = declare("DefaultPool").unwrap().contract_class();
    let stability_pool_contract_class = declare("StabilityPool").unwrap().contract_class();
    let trove_nft_contract_class = declare("TroveNFT").unwrap().contract_class();
    let tbtc_contract_class = declare("TBTC").unwrap().contract_class();
    let collateral_registry_contract_class = declare("CollateralRegistry")
        .unwrap()
        .contract_class();
    let interest_router_contract_class = declare("InterestRouterMock").unwrap().contract_class();

    let ETH_SEPOLIA: ContractAddress = ETH_SEPOLIA_FELT.try_into().unwrap();

    // Deploy BitUSD
    let mut calldata_bit_usd: Array<felt252> = array![];
    // Create ByteArray for name and symbol
    let name_bit_usd: ByteArray = "BitUSD";
    let symbol_bit_usd: ByteArray = "bUSD";
    OWNER().serialize(ref calldata_bit_usd);
    name_bit_usd.serialize(ref calldata_bit_usd);
    symbol_bit_usd.serialize(ref calldata_bit_usd);

    let (bit_usd_contract_address, _) = bit_usd_contract_class
        .deploy(@calldata_bit_usd)
        .expect('Failed to deploy BitUSD');

    // Deploy TBTC
    let mut calldata_tbtc: Array<felt252> = array![];
    let (tbtc_contract_address, _) = tbtc_contract_class
        .deploy(@calldata_tbtc)
        .expect('Failed to deploy TBTC');

    // Deploy AddressRegistry
    let mut calldata_addresses_registry: Array<felt252> = array![];
    OWNER().serialize(ref calldata_addresses_registry);
    CCR_TBTC.serialize(ref calldata_addresses_registry);
    MCR_TBTC.serialize(ref calldata_addresses_registry);
    BCR_ALL.serialize(ref calldata_addresses_registry);
    SCR_TBTC.serialize(ref calldata_addresses_registry);
    LIQUIDATION_PENALTY_SP_TBTC.serialize(ref calldata_addresses_registry);
    LIQUIDATION_PENALTY_REDISTRIBUTION_TBTC.serialize(ref calldata_addresses_registry);
    let (addresses_registry_contract_address, _) = addresses_registry_contract_class
        .deploy(@calldata_addresses_registry)
        .expect('Failed to deploy AR');

    // Deploy TroveManager
    let mut calldata_trove_manager: Array<felt252> = array![];
    addresses_registry_contract_address.serialize(ref calldata_trove_manager);

    let (trove_manager_contract_address, _) = trove_manager_contract_class
        .deploy(@calldata_trove_manager)
        .expect('Failed to deploy TroveManager');

    // Deploy CollateralRegistry
    let mut calldata_collateral_registry: Array<felt252> = array![];
    bit_usd_contract_address.serialize(ref calldata_collateral_registry);
    calldata_collateral_registry.append(1);
    tbtc_contract_address.serialize(ref calldata_collateral_registry);
    calldata_collateral_registry.append(1);
    trove_manager_contract_address.serialize(ref calldata_collateral_registry);

    let (collateral_registry_contract_address, _) = collateral_registry_contract_class
        .deploy(@calldata_collateral_registry)
        .expect('Failed to deploy CR');

    // Deploy TroveNFT
    let mut calldata_trove_nft: Array<felt252> = array![];
    addresses_registry_contract_address.serialize(ref calldata_trove_nft);
    let name_trove_nft: ByteArray = "TroveNFT";
    let symbol_trove_nft: ByteArray = "TNFT";
    let uri_trove_nft: ByteArray = "https://rickroll.com";
    name_trove_nft.serialize(ref calldata_trove_nft);
    symbol_trove_nft.serialize(ref calldata_trove_nft);
    uri_trove_nft.serialize(ref calldata_trove_nft);

    let (trove_nft_contract_address, _) = trove_nft_contract_class
        .deploy(@calldata_trove_nft)
        .expect('Failed to deploy TroveNFT');

    // Deploy StabilityPool
    let mut calldata_stability_pool: Array<felt252> = array![];
    addresses_registry_contract_address.serialize(ref calldata_stability_pool);

    let (stability_pool_contract_address, _) = stability_pool_contract_class
        .deploy(@calldata_stability_pool)
        .expect('Failed to deploy StabilityPool');

    // Deploy ActivePool
    let mut calldata_active_pool: Array<felt252> = array![];
    addresses_registry_contract_address.serialize(ref calldata_active_pool);

    let (active_pool_contract_address, _) = active_pool_contract_class
        .deploy(@calldata_active_pool)
        .expect('Failed to deploy ActivePool');

    // Deploy InterestRouter
    let mut calldata_interest_router: Array<felt252> = array![];
    bit_usd_contract_address.serialize(ref calldata_interest_router);

    let (interest_router_contract_address, _) = interest_router_contract_class
        .deploy(@calldata_interest_router)
        .expect('Failed to deploy InterestRouter');

    // Create and instance of the deployed contract
    let addresses_registry = IAddressesRegistryDispatcher {
        contract_address: addresses_registry_contract_address,
    };

    // Mock caller and set a first batch of addresses
    start_cheat_caller_address(addresses_registry.contract_address, OWNER());
    addresses_registry
        .set_addresses(
            active_pool_contract_address,
            active_pool_contract_address,
            active_pool_contract_address,
            active_pool_contract_address,
            active_pool_contract_address,
            active_pool_contract_address,
            ETH_SEPOLIA,
            active_pool_contract_address,
            trove_manager_contract_address,
            active_pool_contract_address,
            active_pool_contract_address,
            active_pool_contract_address,
            active_pool_contract_address,
            active_pool_contract_address,
            active_pool_contract_address,
            interest_router_contract_address,
            active_pool_contract_address,
            tbtc_contract_address,
        );
    stop_cheat_caller_address(addresses_registry.contract_address);

    // Deploy DefaultPool
    let mut calldata_default_pool: Array<felt252> = array![];
    addresses_registry_contract_address.serialize(ref calldata_default_pool);
    let (default_pool_contract_address, _) = default_pool_contract_class
        .deploy(@calldata_default_pool)
        .expect('Failed to deploy DefaultPool');

    // Deploy CollSurplusPool
    let mut calldata_coll_surplus_pool: Array<felt252> = array![];
    addresses_registry_contract_address.serialize(ref calldata_coll_surplus_pool);
    let (coll_surplus_pool_contract_address, _) = coll_surplus_pool_contract_class
        .deploy(@calldata_coll_surplus_pool)
        .expect('Failed to deploy CSP');

    // Deploy SortedTroves
    let mut calldata_sorted_troves: Array<felt252> = array![];
    addresses_registry_contract_address.serialize(ref calldata_sorted_troves);
    let (sorted_troves_contract_address, _) = sorted_troves_contract_class
        .deploy(@calldata_sorted_troves)
        .expect('Failed to deploy SortedTroves');

    // Deploy PriceFeedMock
    let mut calldata_price_feed_mock: Array<felt252> = array![];
    let (price_feed_mock_contract_address, _) = price_feed_mock_contract_class
        .deploy(@calldata_price_feed_mock)
        .expect('Failed to deploy PriceFeedMock');

    // Mock caller and set a second batch of addresses
    start_cheat_caller_address(addresses_registry.contract_address, OWNER());
    addresses_registry
        .set_addresses(
            active_pool_contract_address,
            default_pool_contract_address,
            price_feed_mock_contract_address,
            active_pool_contract_address,
            active_pool_contract_address,
            active_pool_contract_address,
            ETH_SEPOLIA,
            active_pool_contract_address,
            trove_manager_contract_address,
            trove_nft_contract_address,
            active_pool_contract_address,
            coll_surplus_pool_contract_address,
            sorted_troves_contract_address,
            collateral_registry_contract_address,
            bit_usd_contract_address,
            active_pool_contract_address,
            stability_pool_contract_address,
            tbtc_contract_address,
        );
    stop_cheat_caller_address(addresses_registry.contract_address);

    // Deploy BorrowerOperations
    let mut calldata_borrower_operations: Array<felt252> = array![];
    addresses_registry_contract_address.serialize(ref calldata_borrower_operations);
    let (borrower_operations_contract_address, _) = borrower_operations_contract_class
        .deploy(@calldata_borrower_operations)
        .expect('Failed to deploy BO');

    /////////////////////////////////////////////////////////////////////
    //    Fix to resolve failing deterministic address calculation     //
    /////////////////////////////////////////////////////////////////////
    let active_pool = IActivePoolDispatcher { contract_address: active_pool_contract_address };
    let coll_surplus_pool = ICollSurplusPoolDispatcher {
        contract_address: coll_surplus_pool_contract_address,
    };
    let sorted_troves = ISortedTrovesDispatcher {
        contract_address: sorted_troves_contract_address,
    };
    let trove_manager = ITroveManagerDispatcher {
        contract_address: trove_manager_contract_address,
    };
    let trove_nft = ITroveNFTDispatcher { contract_address: trove_nft_contract_address };
    let stability_pool = IStabilityPoolDispatcher {
        contract_address: stability_pool_contract_address,
    };

    addresses_registry.set_borrower_operations(borrower_operations_contract_address);
    active_pool.set_addresses(addresses_registry.contract_address);
    coll_surplus_pool.set_addresses(addresses_registry.contract_address);
    sorted_troves.set_addresses(addresses_registry.contract_address);
    trove_manager
        .set_addresses(
            active_pool.contract_address,
            default_pool_contract_address,
            price_feed_mock_contract_address,
            ETH_SEPOLIA,
            borrower_operations_contract_address,
            trove_nft_contract_address,
            active_pool.contract_address,
            coll_surplus_pool.contract_address,
            sorted_troves.contract_address,
            collateral_registry_contract_address,
            bit_usd_contract_address,
            stability_pool_contract_address,
        );

    trove_nft.set_addresses(addresses_registry.contract_address);
    stability_pool.set_addresses(addresses_registry.contract_address);

    /////////////////////////////////////////////////////////////////////
    //                          End of fix                             //
    /////////////////////////////////////////////////////////////////////

    let bitusd = IBitUSDDispatcher { contract_address: bit_usd_contract_address };
    start_cheat_caller_address(bitusd.contract_address, OWNER());
    bitusd
        .set_branch_addresses(
            trove_manager.contract_address,
            stability_pool.contract_address,
            borrower_operations_contract_address,
            active_pool.contract_address,
        );
    stop_cheat_caller_address(bitusd.contract_address);

    let borrower_operations = IBorrowerOperationsDispatcher {
        contract_address: borrower_operations_contract_address,
    };

    let tbtc = ITBTCDispatcher { contract_address: tbtc_contract_address };

    return (borrower_operations, tbtc, bitusd);
}

#[test]
fn test_open_trove() {
    let (borrower_operations, tbtc, bitusd) = __deploy__();
    let tbtc_erc20 = IERC20Dispatcher { contract_address: tbtc.contract_address };
    let bitusd_erc20 = IERC20Dispatcher { contract_address: bitusd.contract_address };
    let coll_amount: u256 = 1000000000000000000;
    let bitusd_amount: u256 = 50000000000000000000000;
    let owner_index: u256 = 0;
    let upper_hint: u256 = 0;
    let lower_hint: u256 = 0;
    let annual_interest_rate: u256 = 50000000000000000;
    let max_upfront_fee: u256 = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
    let zero_address: ContractAddress = 0.try_into().unwrap();

    start_cheat_caller_address(tbtc.contract_address, OWNER());
    let owner = OWNER();
    tbtc.mint(owner, coll_amount);
    tbtc_erc20.approve(borrower_operations.contract_address, coll_amount);
    stop_cheat_caller_address(tbtc.contract_address);

    start_cheat_caller_address(borrower_operations.contract_address, OWNER());
    borrower_operations
        .open_trove(
            owner,
            owner_index,
            coll_amount,
            bitusd_amount,
            upper_hint,
            lower_hint,
            annual_interest_rate,
            max_upfront_fee,
            zero_address,
            zero_address,
            zero_address,
        );
    stop_cheat_caller_address(borrower_operations.contract_address);

    assert(bitusd_erc20.balance_of(owner) == bitusd_amount, 'BitUSD balance not correct');
}

