#[starknet::interface]
pub trait IPriceFeedMock<TContractState> {
    fn fetch_price(self: @TContractState) -> (u256, bool);
    fn fetch_redemption_price(self: @TContractState) -> (u256, u256);
    // TODO: what to do with this Mock?
}
