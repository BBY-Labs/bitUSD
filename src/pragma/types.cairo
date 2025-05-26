use openzeppelin::token::erc20::interface::ERC20ABIDispatcher;
use starknet::{ClassHash, ContractAddress};

#[derive(Serde, Drop, Copy, PartialEq, starknet::Store)]
#[allow(starknet::store_no_default_variant)]
pub enum RequestStatus {
    UNINITIALIZED,
    RECEIVED,
    FULFILLED,
    CANCELLED,
    OUT_OF_GAS,
    REFUNDED,
}

#[derive(Serde, Drop, Copy, starknet::Store)]
pub struct YieldPoint {
    expiry_timestamp: u64,
    capture_timestamp: u64, // timestamp of data capture
    // (1 day for overnight rates and expiration date for futures)
    rate: u128, // The calculated yield rate: either overnight rate
    // or max(0, ((future/spot) - 1) * (365/days to future expiry))
    source: felt252 // An indicator for the source (str_to_felt encode uppercase one of:
    // "ON" (overnight rate),
// "FUTURE/SPOT" (future/spot rate),
// "OTHER" (for future additional data sources))
}

#[derive(Serde, Drop, Copy, starknet::Store)]
pub struct FutureKeyStatus {
    is_active: bool,
    expiry_timestamp: u64,
}

#[derive(Copy, Drop, Serde, PartialEq, starknet::Store)]
pub struct BaseEntry {
    timestamp: u64,
    source: felt252,
    publisher: felt252,
}

#[derive(Serde, Drop, Copy)]
pub struct GenericEntryStorage {
    timestamp__value: u256,
}

#[derive(Copy, Drop, Serde)]
pub struct SpotEntry {
    base: BaseEntry,
    price: u128,
    pair_id: felt252,
    volume: u128,
}
#[derive(Copy, Drop, Serde)]
pub struct GenericEntry {
    base: BaseEntry,
    key: felt252,
    value: u128,
}

#[derive(Copy, Drop, PartialEq, Serde)]
pub struct FutureEntry {
    base: BaseEntry,
    price: u128,
    pair_id: felt252,
    volume: u128,
    expiration_timestamp: u64,
}


#[derive(Serde, Drop, Copy)]
pub struct EntryStorage {
    timestamp: u64,
    volume: u128,
    price: u128,
}

#[derive(Drop, Serde, starknet::Store, Copy, Hash, PartialEq, Debug)]
pub struct OptionsFeedData {
    instrument_name: felt252,
    base_currency_id: felt252,
    current_timestamp: u64,
    mark_price: u128,
}


/// Data Types
/// The value is the `pair_id` of the data
/// For future option, pair_id and expiration timestamp
///
/// * `Spot` - Spot price
/// * `Future` - Future price
/// * `Option` - Option price
#[derive(Drop, Copy, Serde)]
pub enum DataType {
    SpotEntry: felt252,
    FutureEntry: (felt252, u64),
    GenericEntry: felt252,
    // OptionEntry: (felt252, felt252),
}

#[derive(Drop, Copy)]
pub enum PossibleEntryStorage {
    Spot: u256, //structure SpotEntryStorage
    Future: u256 //structure FutureEntryStorage
    //  Option: OptionEntryStorage, //structure OptionEntryStorage
}

#[derive(Drop, Copy, Serde)]
pub enum SimpleDataType {
    SpotEntry,
    FutureEntry,
    //  OptionEntry: (),
}

#[derive(Drop, Copy, Serde)]
pub enum PossibleEntries {
    Spot: SpotEntry,
    Future: FutureEntry,
    Generic: GenericEntry,
    //  Option: OptionEntry,
}


pub enum ArrayEntry {
    SpotEntry: Array<SpotEntry>,
    FutureEntry: Array<FutureEntry>,
    GenericEntry: Array<GenericEntry>,
    //  OptionEntry: Array<OptionEntry>,
}


#[derive(Serde, Drop, Copy, starknet::Store)]
pub struct Pair {
    id: felt252, // same as key currently (e.g. str_to_felt("ETH/USD") - force uppercase)
    quote_currency_id: felt252, // currency id - str_to_felt encode the ticker
    base_currency_id: felt252 // currency id - str_to_felt encode the ticker
}

#[derive(Serde, Drop, Copy, starknet::Store)]
pub struct Currency {
    id: felt252,
    decimals: u32,
    is_abstract_currency: bool, // True (1) if not a specific token but abstract, e.g. USD or ETH as a whole
    starknet_address: ContractAddress, // optional, e.g. can have synthetics for non-bridged assets
    ethereum_address: ContractAddress // optional
}

#[derive(Serde, Drop)]
pub struct Checkpoint {
    timestamp: u64,
    value: u128,
    aggregation_mode: AggregationMode,
    num_sources_aggregated: u32,
}

#[derive(Serde, Drop, Copy, starknet::Store)]
pub struct FetchCheckpoint {
    pair_id: felt252,
    type_of: felt252,
    index: u64,
    expiration_timestamp: u64,
    aggregation_mode: u8,
}

#[derive(Serde, Drop, Copy)]
pub struct PragmaPricesResponse {
    pub price: u128,
    pub decimals: u32,
    pub last_updated_timestamp: u64,
    pub num_sources_aggregated: u32,
    pub expiration_timestamp: Option<u64>,
}

#[derive(Serde, Drop, Copy)]
pub enum AggregationMode {
    Median: (),
    Mean: (),
    ConversionRate,
    Error: (),
}

#[derive(starknet::Store, Drop, Serde, Copy)]
pub struct EscalationManagerSettings {
    pub arbitrate_via_escalation_manager: bool,
    pub discard_oracle: bool,
    pub validate_disputers: bool,
    pub asserting_caller: ContractAddress,
    pub escalation_manager: ContractAddress,
}

#[derive(starknet::Store, Drop, Serde, Copy)]
pub struct Assertion {
    pub escalation_manager_settings: EscalationManagerSettings,
    pub asserter: ContractAddress,
    pub assertion_time: u64,
    pub settled: bool,
    pub currency: ERC20ABIDispatcher,
    pub expiration_time: u64,
    pub settlement_resolution: bool,
    pub domain_id: u256,
    pub identifier: felt252,
    pub bond: u256,
    pub callback_recipient: ContractAddress,
    pub disputer: ContractAddress,
}
