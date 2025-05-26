#[starknet::interface]
pub trait IPriceFeed<TContractState> {
    fn fetch_price(self: @TContractState) -> u256;
    fn fetch_redemption_price(self: @TContractState) -> u256;
}

// TODO: Work still needed on PriceFeed to handle shutdown and validate returned prices.
#[starknet::contract]
pub mod PriceFeed {
    use pragma_lib::abi::{IPragmaABIDispatcher, IPragmaABIDispatcherTrait};
    use pragma_lib::types::{DataType, PragmaPricesResponse};
    use starknet::ContractAddress;
    use super::IPriceFeed;
    //////////////////////////////////////////////////////////////
    //                          CONSTANTS                     //
    //////////////////////////////////////////////////////////////

    const PRICE_FEED_BTC_USD: felt252 = 18669995996566340; // felt252 conversion of "BTC/USD"
    const PRICE_SCALING_FACTOR: u256 = 10_000_000_000; // 10^10
    const ORACLE_ADDRESS: felt252 =
        0x36031daa264c24520b11d93af622c848b2499b66b41d611bac95e13cfca131a;
    //////////////////////////////////////////////////////////////
    //                          STORAGE                         //
    //////////////////////////////////////////////////////////////

    #[storage]
    pub struct Storage {}

    ////////////////////////////////////////////////////////////////
    //                     EXTERNAL FUNCTIONS                     //
    ////////////////////////////////////////////////////////////////

    #[abi(embed_v0)]
    impl IPriceFeedImpl of IPriceFeed<ContractState> {
        fn fetch_price(self: @ContractState) -> u256 {
            let oracle_address: ContractAddress = ORACLE_ADDRESS.try_into().unwrap();
            let price = _get_asset_price_median(
                oracle_address, DataType::SpotEntry(PRICE_FEED_BTC_USD),
            );
            // Price is returned with 8 decimals, so we need to scale it up to 18 decimals
            let price_scaled: u256 = price * PRICE_SCALING_FACTOR;
            price_scaled
        }

        fn fetch_redemption_price(self: @ContractState) -> u256 {
            let oracle_address: ContractAddress = ORACLE_ADDRESS.try_into().unwrap();
            let price = _get_asset_price_median(
                oracle_address, DataType::SpotEntry(PRICE_FEED_BTC_USD),
            );
            // Price is returned with 8 decimals, so we need to scale it up to 18 decimals
            let price_scaled: u256 = price * PRICE_SCALING_FACTOR;
            price_scaled
        }
    }

    ////////////////////////////////////////////////////////////////
    //                     INTERNAL FUNCTIONS                     //
    ////////////////////////////////////////////////////////////////

    fn _get_asset_price_median(oracle_address: ContractAddress, asset: DataType) -> u256 {
        let oracle_dispatcher = IPragmaABIDispatcher { contract_address: oracle_address };
        let output: PragmaPricesResponse = oracle_dispatcher.get_data_median(asset);
        return output.price.into();
    }
}
