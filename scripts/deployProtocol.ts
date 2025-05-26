import dotenv from 'dotenv';
import fs from 'fs';
import {
  RpcProvider,
  Account,
  CallData,
  constants,
  Calldata,
  Contract,
  hash,
  num,
  stark,
} from 'starknet';

import { getSierraAndCasm, deployContract, connectToContract } from './utils';

import {
  CCR_TBTC,
  MCR_TBTC,
  SCR_TBTC,
  BCR_ALL,
  LIQUIDATION_PENALTY_SP_TBTC,
  LIQUIDATION_PENALTY_REDISTRIBUTION_TBTC,
} from './constants';

dotenv.config();

// Get Account Address, account private Key, and RPC URL from .env
const accountAddress = process.env.ACCOUNT_ADDRESS || '';
const accountPrivateKey = process.env.ACCOUNT_PRIVATE_KEY || '';
const rpcUrl = process.env.RPC_URL || '';
const network = process.env.NETWORK || 'devnet';
const provider = new RpcProvider({ nodeUrl: rpcUrl });

const UDC_ADDRESS =
  '0x041a78e741e5af2fec34b695679bc6891742439f7afb8484ecd7766661ad02bf';
const ETH_SEPOLIA =
  '0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7';

async function deployProtocol() {
  const deployerAccount = new Account(
    provider,
    accountAddress,
    accountPrivateKey,
    undefined,
    constants.TRANSACTION_VERSION.V3
  );

  console.log(`👷 Deploying protocol...`);
  console.log(`🛄 Deployer account: ${deployerAccount.address}`);

  let bitusd = await deployBitUSD(deployerAccount);
  let tbtc = await deployTBTC(deployerAccount);

  // One per collateral

  // TBTC
  const troveManagerParams: TroveManagerParams = {
    ccr: CCR_TBTC,
    mcr: MCR_TBTC,
    bcr: BCR_ALL,
    scr: SCR_TBTC,
    liquidation_penalty_sp: LIQUIDATION_PENALTY_SP_TBTC,
    liquidation_penalty_redistribution: LIQUIDATION_PENALTY_REDISTRIBUTION_TBTC,
  };

  // Deploy AddressRegistry
  let addressesRegistry = await deployAddressesRegistry(
    deployerAccount,
    troveManagerParams
  );

  // Deploy TroveManager
  let troveManager = await deployTroveManager(
    deployerAccount,
    addressesRegistry
  );

  const collaterals = [tbtc];
  const troveManagers = [troveManager];

  let collateralRegistry = await deployCollateralRegistry(
    deployerAccount,
    bitusd,
    collaterals,
    troveManagers
  );

  // let hintHelpers = await deployHintHelpers(
  //   deployerAccount,
  //   collateralRegistry
  // );
  // let multiTroveGetter = await deployMultiTroveGetter(
  //   deployerAccount,
  //   collateralRegistry
  // );

  let contracts = await deployAndConnectCollateralContracts(
    deployerAccount,
    tbtc,
    bitusd,
    collateralRegistry,
    addressesRegistry,
    troveManager
    // hintHelpers
    // multiTroveGetter
  );

  let bitusd_instance = connectToContract(
    deployerAccount,
    bitusd.address,
    'BitUSD'
  );

  await bitusd_instance.set_collateral_registry(collateralRegistry.address);

  // deployAndConnectContracts
  let deploymentVars: DeploymentVars = {
    numCollaterals: 1,
    collaterals: [tbtc],
    addressesRegistries: [addressesRegistry],
    troveManagers: [troveManager],
    contracts: contracts,
  };
}

type TroveManagerParams = {
  ccr: BigInt;
  mcr: BigInt;
  bcr: BigInt;
  scr: BigInt;
  liquidation_penalty_sp: BigInt;
  liquidation_penalty_redistribution: BigInt;
};

type DeploymentVars = {
  numCollaterals: number;
  collaterals: Contract[];
  addressesRegistries: Contract[];
  troveManagers: Contract[];
  contracts: Contracts;
};

type Contracts = {
  addressesRegistry: Contract;
  activePool: Contract;
  borrowerOperations: Contract;
  collSurplusPool: Contract;
  defaultPool: Contract;
  sortedTroves: Contract;
  stabilityPool: Contract;
  troveManager: Contract;
  troveNFT: Contract;
  // metadataNFT: Contract;
  priceFeed: Contract;
  //gasPool: Contract;
  // interestRouter: Contract;
  collToken: Contract;
};

async function deployAndConnectCollateralContracts(
  deployerAccount: Account,
  collToken: Contract,
  bitusd: Contract,
  collateralRegistry: Contract,
  addressesRegistry: Contract,
  troveManager: Contract
  // hintHelpers: Contract
  // multiTroveGetter: Contract
): Promise<Contracts> {
  const troveNFT = await deployTroveNFT(
    deployerAccount,
    addressesRegistry,
    'TroveNFT',
    'TNFT',
    'https://rickroll.com'
  );

  const stabilityPool = await deployStabilityPool(
    deployerAccount,
    addressesRegistry
  );

  const activePool = await deployActivePool(deployerAccount, addressesRegistry);

  const interestRouter = await deployInterestRouter(deployerAccount, bitusd);

  // Declare instance before deploying through UDC

  //let borrowerOperationsClassHash = "0x756d9145a4271a72f0a02a73d82629c1d2b12564b3d3722c96afd0bca22a6c5";
  //await declareBorrowerOperations(deployerAccount);

  /*   const salt = "0x22222311111111112234";
    const boConstructorCalldata = CallData.compile([addressesRegistry.address]);
    const borrowerOperationsAddress = hash.calculateContractAddressFromHash(
     salt,
     borrowerOperationsClassHash,
     boConstructorCalldata,
     deployerAccount.address
  ); */

  /*   console.log("bo address computed below:");
    console.log(borrowerOperationsAddress); */

  const addressesRegistryInstance = connectToContract(
    deployerAccount,
    addressesRegistry.address,
    'AddressesRegistry'
  );

  const tx = await addressesRegistryInstance.set_addresses(
    activePool.address,
    activePool.address,
    activePool.address,
    activePool.address,
    activePool.address,
    activePool.address,
    ETH_SEPOLIA,
    activePool.address,
    troveManager.address,
    activePool.address,
    activePool.address,
    activePool.address,
    activePool.address,
    activePool.address,
    activePool.address,
    interestRouter.address,
    activePool.address,
    collToken.address
  );

  await provider.waitForTransaction(tx.transaction_hash);

  const defaultPool = await deployDefaultPool(
    deployerAccount,
    addressesRegistry
  );

  //const gasPool = await deployGasPool(deployerAccount, ETH_SEPOLIA, borrowerOperationsAddress, troveManager.address);

  const collSurplusPool = await deployCollSurplusPool(
    deployerAccount,
    addressesRegistry
  );

  const sortedTroves = await deploySortedTroves(
    deployerAccount,
    addressesRegistry
  );

  const priceFeed = await deployPriceFeed(deployerAccount);

  // update addresses registry with new deployed contracts.
  const tx2 = await addressesRegistryInstance.set_addresses(
    activePool.address,
    defaultPool.address,
    priceFeed.address,
    activePool.address,
    activePool.address,
    activePool.address,
    ETH_SEPOLIA,
    activePool.address,
    troveManager.address,
    troveNFT.address,
    activePool.address,
    collSurplusPool.address,
    sortedTroves.address,
    collateralRegistry.address,
    bitusd.address,
    activePool.address,
    stabilityPool.address,
    collToken.address
  );

  await provider.waitForTransaction(tx2.transaction_hash);

  console.log('set_addresses Done');

  const borrowerOperations = await deployBorrowerOperations(
    deployerAccount,
    addressesRegistry
  );

  // Deploy BorrowerOperations to precomputed address

  /*   const tx3 = await deployerAccount.deployContract({
      classHash: borrowerOperationsClassHash,
      constructorCalldata: boConstructorCalldata,
      salt: salt,
    });
    
    const receipt = await provider.waitForTransaction(tx3.transaction_hash);
    console.log("Deployed BO address:", tx3.contract_address); */

  /*   const udcCalldata = CallData.compile({
      classHash: borrowerOperationsClassHash,
      salt,
      unique: false,
      calldata: boConstructorCalldata,
    });
    
    const tx3 = await deployerAccount.execute({
      contractAddress: UDC_ADDRESS,
      entrypoint: "deployContract",
      calldata: udcCalldata,
    }); */

  // Deploy directly using account.deployContract
  /*   const tx3 = await deployerAccount.deployContract({
      classHash: borrowerOperationsClassHash,
      constructorCalldata: boConstructorCalldata,
      salt: salt,
    }); */

  /*   await provider.waitForTransaction(tx3.transaction_hash);
    console.log("transaction hash");
    console.log(tx3.transaction_hash); */

  /*   const borrowerOperations = await deployBorrowerOperations(
      deployerAccount,
      addressesRegistry
    ); */

  const contracts: Contracts = {
    addressesRegistry,
    activePool,
    borrowerOperations,
    collSurplusPool,
    defaultPool,
    sortedTroves,
    stabilityPool,
    troveManager,
    troveNFT,
    // metadataNFT,
    priceFeed,
    // gasPool
    // interestRouter,
    collToken,
  };

  /////////////////////////////////////////////////////////////////////
  // Fix to resolve failing deterministic address calculation for BO //
  /////////////////////////////////////////////////////////////////////
  let tx_ar_fix = await addressesRegistryInstance.set_borrower_operations(
    borrowerOperations.address
  );
  await provider.waitForTransaction(tx_ar_fix.transaction_hash);

  const activePoolInstance = connectToContract(
    deployerAccount,
    activePool.address,
    'ActivePool'
  );

  let tx_ap_fix = await activePoolInstance.set_addresses(
    addressesRegistry.address
  );
  await provider.waitForTransaction(tx_ap_fix.transaction_hash);

  const collSurplusPoolInstance = connectToContract(
    deployerAccount,
    collSurplusPool.address,
    'CollSurplusPool'
  );

  let tx_csp_fix = await collSurplusPoolInstance.set_addresses(
    addressesRegistry.address
  );
  await provider.waitForTransaction(tx_csp_fix.transaction_hash);

  const sortedTrovesInstance = connectToContract(
    deployerAccount,
    sortedTroves.address,
    'SortedTroves'
  );

  let tx_st_fix = await sortedTrovesInstance.set_addresses(
    addressesRegistry.address
  );
  await provider.waitForTransaction(tx_st_fix.transaction_hash);

  const troveManagerInstance = connectToContract(
    deployerAccount,
    troveManager.address,
    'TroveManager'
  );

  let tx_tm_fix = await troveManagerInstance.set_addresses(
    activePool.address,
    defaultPool.address,
    priceFeed.address,
    ETH_SEPOLIA,
    borrowerOperations.address,
    troveNFT.address,
    activePool.address,
    collSurplusPool.address,
    sortedTroves.address,
    collateralRegistry.address,
    bitusd.address,
    stabilityPool.address
  );
  await provider.waitForTransaction(tx_tm_fix.transaction_hash);

  const troveNFTInstance = connectToContract(
    deployerAccount,
    troveNFT.address,
    'TroveNFT'
  );

  let tx_tnft_fix = await troveNFTInstance.set_addresses(
    addressesRegistry.address
  );
  await provider.waitForTransaction(tx_tnft_fix.transaction_hash);

  const stabilityPoolInstance = connectToContract(
    deployerAccount,
    stabilityPool.address,
    'StabilityPool'
  );

  let tx_sp_fix = await stabilityPoolInstance.set_addresses(
    addressesRegistry.address
  );
  await provider.waitForTransaction(tx_sp_fix.transaction_hash);

  /////////////////////////////////////////////////////////////////////
  //                          End of fix                             //
  /////////////////////////////////////////////////////////////////////

  const bitusd_instance = connectToContract(
    deployerAccount,
    bitusd.address,
    'BitUSD'
  );

  const tx4 = await bitusd_instance.set_branch_addresses(
    troveManager.address,
    stabilityPool.address,
    borrowerOperations.address,
    activePool.address
  );

  await provider.waitForTransaction(tx4.transaction_hash);

  console.log('BorrowerOperations');
  console.log(borrowerOperations.address);
  console.log('SP');
  console.log(stabilityPool.address);
  console.log('TM');
  console.log(troveManager.address);

  return contracts;
}

async function deployPriceFeed(deployerAccount: Account) {
  const { compiledSierra, compiledCasm } = getSierraAndCasm('PriceFeed');
  const callData: CallData = new CallData(compiledSierra.abi);
  const constructorCalldata: string[] = [];

  return await deployContract(
    deployerAccount,
    'PriceFeed',
    constructorCalldata
  );
}

async function deployBorrowerOperations(
  deployerAccount: Account,
  addressesRegistry: Contract
) {
  const { compiledSierra, compiledCasm } =
    getSierraAndCasm('BorrowerOperations');

  const callData: CallData = new CallData(compiledSierra.abi);
  const constructorCalldata: Calldata = callData.compile('constructor', {
    addresses_registry: addressesRegistry.address,
  });

  return await deployContract(
    deployerAccount,
    'BorrowerOperations',
    constructorCalldata
  );
}

async function deployTroveNFT(
  deployerAccount: Account,
  addressesRegistry: Contract,
  name: string,
  symbol: string,
  uri: string
) {
  const { compiledSierra, compiledCasm } = getSierraAndCasm('TroveNFT');

  const callData: CallData = new CallData(compiledSierra.abi);
  const constructorCalldata: Calldata = callData.compile('constructor', {
    addresses_registry: addressesRegistry.address,
    name: name,
    symbol: symbol,
    uri: uri,
  });

  return await deployContract(deployerAccount, 'TroveNFT', constructorCalldata);
}

async function deployStabilityPool(
  deployerAccount: Account,
  addressesRegistry: Contract
) {
  const { compiledSierra, compiledCasm } = getSierraAndCasm('StabilityPool');

  const callData: CallData = new CallData(compiledSierra.abi);
  const constructorCalldata: Calldata = callData.compile('constructor', {
    addresses_registry: addressesRegistry.address,
  });

  return await deployContract(
    deployerAccount,
    'StabilityPool',
    constructorCalldata
  );
}

async function deployActivePool(
  deployerAccount: Account,
  addressesRegistry: Contract
) {
  const { compiledSierra, compiledCasm } = getSierraAndCasm('ActivePool');
  const callData: CallData = new CallData(compiledSierra.abi);
  const constructorCalldata: Calldata = callData.compile('constructor', {
    addresses_registry: addressesRegistry.address,
  });

  return await deployContract(
    deployerAccount,
    'ActivePool',
    constructorCalldata
  );
}

async function deployInterestRouter(
  deployerAccount: Account,
  bitusd: Contract
) {
  const { compiledSierra, compiledCasm } =
    getSierraAndCasm('InterestRouterMock');
  const callData: CallData = new CallData(compiledSierra.abi);
  const constructorCalldata: Calldata = callData.compile('constructor', {
    bitusd: bitusd.address,
  });

  return await deployContract(
    deployerAccount,
    'InterestRouterMock',
    constructorCalldata
  );
}

async function deployDefaultPool(
  deployerAccount: Account,
  addressesRegistry: Contract
) {
  const { compiledSierra, compiledCasm } = getSierraAndCasm('DefaultPool');
  const callData: CallData = new CallData(compiledSierra.abi);
  const constructorCalldata: Calldata = callData.compile('constructor', {
    addresses_registry: addressesRegistry.address,
  });

  return await deployContract(
    deployerAccount,
    'DefaultPool',
    constructorCalldata
  );
}

async function deployGasPool(
  deployerAccount: Account,
  eth: string,
  borrowerOperations: string,
  troveManager: string
) {
  const { compiledSierra, compiledCasm } = getSierraAndCasm('GasPool');
  const callData: CallData = new CallData(compiledSierra.abi);
  const constructorCalldata: Calldata = callData.compile('constructor', {
    eth_address: eth,
    borrower_operations_address: borrowerOperations,
    trove_manager_address: troveManager,
  });

  return await deployContract(deployerAccount, 'GasPool', constructorCalldata);
}

async function deployCollSurplusPool(
  deployerAccount: Account,
  addressesRegistry: Contract
) {
  const { compiledSierra, compiledCasm } = getSierraAndCasm('CollSurplusPool');
  const callData: CallData = new CallData(compiledSierra.abi);
  const constructorCalldata: Calldata = callData.compile('constructor', {
    addresses_registry: addressesRegistry.address,
  });

  return await deployContract(
    deployerAccount,
    'CollSurplusPool',
    constructorCalldata
  );
}

async function deploySortedTroves(
  deployerAccount: Account,
  addressesRegistry: Contract
) {
  const { compiledSierra, compiledCasm } = getSierraAndCasm('SortedTroves');
  const callData: CallData = new CallData(compiledSierra.abi);
  const constructorCalldata: Calldata = callData.compile('constructor', {
    addresses_registry: addressesRegistry.address,
  });

  return await deployContract(
    deployerAccount,
    'SortedTroves',
    constructorCalldata
  );
}

async function deployCollateralRegistry(
  deployerAccount: Account,
  bitusd: Contract,
  collaterals: Contract[],
  troveManagers: Contract[]
) {
  const { compiledSierra, compiledCasm } =
    getSierraAndCasm('CollateralRegistry');

  const callData: CallData = new CallData(compiledSierra.abi);
  const constructorCalldata: Calldata = callData.compile('constructor', {
    bit_usd: bitusd.address,
    collateral_tokens: collaterals.map((collateral) => collateral.address),
    trove_managers: troveManagers.map((troveManager) => troveManager.address),
  });

  return await deployContract(
    deployerAccount,
    'CollateralRegistry',
    constructorCalldata
  );
}

async function deployAddressesRegistry(
  deployerAccount: Account,
  troveManagerParams: TroveManagerParams
): Promise<Contract> {
  const { compiledSierra, compiledCasm } =
    getSierraAndCasm('AddressesRegistry');

  const callData: CallData = new CallData(compiledSierra.abi);
  const constructorCalldata: Calldata = callData.compile('constructor', {
    owner: deployerAccount.address,
    ccr: troveManagerParams.ccr,
    mcr: troveManagerParams.mcr,
    bcr: troveManagerParams.bcr,
    scr: troveManagerParams.scr,
    liquidation_penalty_sp: troveManagerParams.liquidation_penalty_sp,
    liquidation_penalty_redistribution:
      troveManagerParams.liquidation_penalty_redistribution,
  });

  return await deployContract(
    deployerAccount,
    'AddressesRegistry',
    constructorCalldata
  );
}

async function deployHintHelpers(
  deployerAccount: Account,
  collateralRegistry: Contract
): Promise<Contract> {
  const { compiledSierra, compiledCasm } = getSierraAndCasm('MultiTroveGetter'); // TODO change to real HintHelpers

  const callData: CallData = new CallData(compiledSierra.abi);
  const constructorCalldata: Calldata = callData.compile('constructor', {
    collateral_registry: collateralRegistry.address,
  });

  return await deployContract(
    deployerAccount,
    'HintHelpers',
    constructorCalldata
  );
}

async function deployMultiTroveGetter(
  deployerAccount: Account,
  collateralRegistry: Contract
) {
  const { compiledSierra, compiledCasm } = getSierraAndCasm('MultiTroveGetter');

  const callData: CallData = new CallData(compiledSierra.abi);
  const constructorCalldata: Calldata = callData.compile('constructor', {
    collateral_registry: collateralRegistry.address,
  });

  return await deployContract(
    deployerAccount,
    'MultiTroveGetter',
    constructorCalldata
  );
}

async function deployTroveManager(
  deployerAccount: Account,
  addressesRegistry: Contract
): Promise<Contract> {
  const { compiledSierra, compiledCasm } = getSierraAndCasm('TroveManager');

  const callData: CallData = new CallData(compiledSierra.abi);
  const constructorCalldata: Calldata = callData.compile('constructor', {
    addresses_registry: addressesRegistry.address,
  });

  return await deployContract(
    deployerAccount,
    'TroveManager',
    constructorCalldata
  );
}

async function deployBitUSD(deployerAccount: Account): Promise<Contract> {
  const { compiledSierra, compiledCasm } = getSierraAndCasm('BitUSD');

  const callData: CallData = new CallData(compiledSierra.abi);
  const constructorCalldata: Calldata = callData.compile('constructor', {
    owner: deployerAccount.address,
    name: 'bitUSD',
    symbol: 'bitUSD',
  });

  return await deployContract(deployerAccount, 'BitUSD', constructorCalldata);
}

async function deployTBTC(deployerAccount: Account): Promise<Contract> {
  const { compiledSierra, compiledCasm } = getSierraAndCasm('TBTC');

  const callData: CallData = new CallData(compiledSierra.abi);
  const constructorCalldata: string[] = [];

  return await deployContract(deployerAccount, 'TBTC', constructorCalldata);
}

async function declareBorrowerOperations(deployerAccount: Account) {
  const { compiledSierra, compiledCasm } =
    getSierraAndCasm('BorrowerOperations');

  // Use account.declare which handles details automatically
  const declareResult = await deployerAccount.declare({
    contract: compiledSierra,
    casm: compiledCasm,
  });

  console.log(
    'BorrowerOperations declared with class hash:',
    declareResult.class_hash
  );

  // Wait for declaration transaction
  await deployerAccount.waitForTransaction(declareResult.transaction_hash);

  return declareResult.class_hash;
}

async function openTrove() {
  const deployerAccount = new Account(
    provider,
    accountAddress,
    accountPrivateKey,
    undefined,
    constants.TRANSACTION_VERSION.V3
  );

  // Use Starknet's standard representation for the zero address
  const ZERO_ADDRESS = constants.ZERO;

  const BORROWER_OPERATIONS_ADDRESS =
    '0x7362108a497aac0328a1df2b2699cb07df805bb05a180b69c6431e8c0443c03';
  const TBTC_ADDRESS =
    '0x25e09b7c20159bcbbc483f45f356f3fc792052a1ebc0fa0a2563259499d964a';

  const TBTC = connectToContract(deployerAccount, TBTC_ADDRESS, 'TBTC');

  // Define amounts with proper BigInt handling according to ABI
  const coll_amount = BigInt('1000000000000000000'); // 1e18
  const bitusd_amount = BigInt('50000000000000000000000'); // 50,000 * 1e18
  const owner_index = BigInt('0'); // u256
  const upper_hint = BigInt('0'); // u256
  const lower_hint = BigInt('0'); // u256
  const annual_interest_rate = BigInt('50000000000000000'); // 5% annual rate (0.05 * 1e18)
  const max_upfront_fee = BigInt(
    '0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff'
  ); // Max uint256 // Max upfront fee

  console.log('Collateral amount:', coll_amount.toString());
  console.log('BitUSD amount:', bitusd_amount.toString());
  console.log('Annual interest rate:', annual_interest_rate.toString());
  console.log('Max upfront fee:', max_upfront_fee.toString());

  console.log('Collateral amount:', coll_amount.toString());
  console.log('BitUSD amount:', bitusd_amount.toString());

  try {
    // Mint tokens
    console.log('Minting tokens...');
    const tx1 = await TBTC.mint(deployerAccount.address, coll_amount);
    await provider.waitForTransaction(tx1.transaction_hash);
    console.log('Tokens minted successfully');

    // Approve tokens
    console.log('Approving tokens...');
    const tx2 = await TBTC.approve(BORROWER_OPERATIONS_ADDRESS, coll_amount);
    await provider.waitForTransaction(tx2.transaction_hash);
    console.log('Tokens approved successfully');

    // Connect to BorrowerOperations contract
    const borrowerOperations = connectToContract(
      deployerAccount,
      BORROWER_OPERATIONS_ADDRESS,
      'BorrowerOperations'
    );

    // Open trove
    console.log('Opening trove...');
    const tx3 = await borrowerOperations.open_trove(
      deployerAccount.address, // owner: ContractAddress
      owner_index, // owner_index: u256
      coll_amount, // coll_amount: u256
      bitusd_amount, // bitusd_amount: u256
      upper_hint, // upper_hint: u256
      lower_hint, // lower_hint: u256
      annual_interest_rate, // annual_interest_rate: u256
      max_upfront_fee, // max_upfront_fee: u256
      ZERO_ADDRESS, // add_manager: ContractAddress
      ZERO_ADDRESS, // remove_manager: ContractAddress
      ZERO_ADDRESS // receiver: ContractAddress - Set to owner's address
    );

    await provider.waitForTransaction(tx3.transaction_hash);
    console.log('Transaction hash:', tx3.transaction_hash);
    console.log('TROVE OPENED SUCCESSFULLY');

    return tx3.transaction_hash;
  } catch (error) {
    console.error('Error opening trove:', error);
    throw error;
  }
}

deployProtocol()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
