#[starknet::contract]
pub mod GasPool {
    use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use starknet::ContractAddress;
    use crate::AddressesRegistry::{IAddressesRegistryDispatcher, IAddressesRegistryDispatcherTrait};
    use crate::dependencies::Constants::Constants::MAX_UINT256;

    #[storage]
    pub struct Storage {}

    ////////////////////////////////////////////////////////////////
    //                        CONSTRUCTOR                         //
    ////////////////////////////////////////////////////////////////

    #[constructor]
    fn constructor(ref self: ContractState, addresses_registry_address: ContractAddress) {
        let addresses_registry = IAddressesRegistryDispatcher {
            contract_address: addresses_registry_address,
        };
        let eth_address = addresses_registry.get_eth();
        let eth = IERC20Dispatcher { contract_address: eth_address };
        let borrower_operations_address = addresses_registry.get_borrower_operations();
        let trove_manager_address = addresses_registry.get_trove_manager();

        // Allow BorrowerOperations to send refund gas compensation
        eth.approve(borrower_operations_address, MAX_UINT256);

        // Allow TroveManager to send gas compensation
        eth.approve(trove_manager_address, MAX_UINT256);
    }
}
