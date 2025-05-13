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
