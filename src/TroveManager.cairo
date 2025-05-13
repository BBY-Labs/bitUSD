use starknet::ContractAddress;
use starknet::storage::Vec;

#[starknet::interface]
pub trait ITroveManager<TContractState> {
    // View functions
    fn get_unbacked_portion_price_and_redeemability(ref self: TContractState) -> (u256, u256, bool);
    fn get_entire_branch_debt(self: @TContractState) -> u256;
    fn get_trove_ids_count(self: @TContractState) -> u256;
    fn get_trove_from_trove_ids_array(self: @TContractState, index: u256) -> u256;
    fn get_trove_nft(self: @TContractState) -> ContractAddress;
    fn get_borrower_operations(self: @TContractState) -> ContractAddress;
    fn get_stability_pool(self: @TContractState) -> ContractAddress;
    fn get_sorted_troves(self: @TContractState) -> ContractAddress;
    fn get_CCR(self: @TContractState) -> u256;

    // External functions
    fn redeem_collateral(
        ref self: TContractState,
        msg_sender: ContractAddress,
        redeem_amount: u256,
        price: u256,
        redemption_rate: u256,
        max_iterations: u256,
    ) -> u256;
    fn batch_liquidate_troves(ref self: TContractState, trove_array: Span<u256>);
}
