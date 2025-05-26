#[starknet::contract]
pub mod GasPool {
    use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use starknet::ContractAddress;
    use crate::dependencies::Constants::Constants::MAX_UINT256;

    #[storage]
    pub struct Storage {}

    ////////////////////////////////////////////////////////////////
    //                        CONSTRUCTOR                         //
    ////////////////////////////////////////////////////////////////

    #[constructor]
    // TODO: constructor to refactor to addressesRegistry (not necessary)
    fn constructor(
        ref self: ContractState,
        eth_address: ContractAddress,
        borrower_operations_address: ContractAddress,
        trove_manager_address: ContractAddress,
    ) {
        let eth = IERC20Dispatcher { contract_address: eth_address };

        // Allow BorrowerOperations to send refund gas compensation
        eth.approve(borrower_operations_address, MAX_UINT256 - 1);

        // Allow TroveManager to send gas compensation
        eth.approve(trove_manager_address, MAX_UINT256 - 1);
    }
}
