#[starknet::interface]
pub trait IPriceFeedMock<TContractState> {
    fn fetch_price(self: @TContractState) -> u256;
    fn fetch_redemption_price(self: @TContractState) -> u256;
    // TODO: what to do with this Mock?
}

// TODO: Work still needed on PriceFeed to handle shutdown and validate returned prices.
#[starknet::contract]
pub mod PriceFeedMock {
    use crate::dependencies::Constants::Constants::DECIMAL_PRECISION;
    use super::IPriceFeedMock;
    //////////////////////////////////////////////////////////////
    //                          CONSTANTS                     //
    //////////////////////////////////////////////////////////////

    //////////////////////////////////////////////////////////////
    //                          STORAGE                         //
    //////////////////////////////////////////////////////////////

    #[storage]
    pub struct Storage {}

    ////////////////////////////////////////////////////////////////
    //                     EXTERNAL FUNCTIONS                     //
    ////////////////////////////////////////////////////////////////

    #[abi(embed_v0)]
    impl IPriceFeedMockImpl of IPriceFeedMock<ContractState> {
        fn fetch_price(self: @ContractState) -> u256 {
            let price = 100_000 * DECIMAL_PRECISION;
            price
        }

        fn fetch_redemption_price(self: @ContractState) -> u256 {
            let price = 100_000 * DECIMAL_PRECISION;
            price
        }
    }
}
