use starknet::ContractAddress;

#[starknet::interface]
pub trait IInterestRouterMock<TContractState> {
    fn transfer_interest(ref self: TContractState, receiver: ContractAddress) -> u256;
}

// TODO: We should add specific distribution logic to this contract
#[starknet::contract]
pub mod InterestRouterMock {
    use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use starknet::{ContractAddress, get_contract_address};
    use super::IInterestRouterMock;

    //////////////////////////////////////////////////////////////
    //                          STORAGE                         //
    //////////////////////////////////////////////////////////////

    #[storage]
    struct Storage {
        bitusd: ContractAddress,
    }

    ////////////////////////////////////////////////////////////////
    //                        CONSTRUCTOR                         //
    ////////////////////////////////////////////////////////////////

    #[constructor]
    fn constructor(ref self: ContractState, bitusd: ContractAddress) {
        self.bitusd.write(bitusd);
    }

    ////////////////////////////////////////////////////////////////
    //                    EXTERNAL FUNCTIONS                      //
    ////////////////////////////////////////////////////////////////

    impl IInterestRouterMockImpl of IInterestRouterMock<ContractState> {
        fn transfer_interest(ref self: ContractState, receiver: ContractAddress) -> u256 {
            let bitusd_instance = IERC20Dispatcher { contract_address: self.bitusd.read() };

            let balance = bitusd_instance.balance_of(get_contract_address());

            bitusd_instance.transfer(receiver, balance);
            balance
        }
    }
}

