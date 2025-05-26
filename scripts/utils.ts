import fs from 'fs';
import { Account, Calldata, json, Contract, RpcProvider } from 'starknet';

export function getSierraAndCasm(fileName: string) {
  const compiledSierra = JSON.parse(
    fs
      .readFileSync(`./target/dev/bit_usd_${fileName}.contract_class.json`)
      .toString()
  );
  const compiledCasm = JSON.parse(
    fs
      .readFileSync(
        `./target/dev/bit_usd_${fileName}.compiled_contract_class.json`
      )
      .toString()
  );
  return { compiledSierra, compiledCasm };
}

export function connectToContract(
  signerOrProvider: Account | RpcProvider,
  contractAddress: string,
  fileName: string
): Contract {
  console.log(`🔍 Connecting to contract ${fileName} at ${contractAddress}...`);
  const contractClass = json.parse(
    fs
      .readFileSync(`./target/dev/bit_usd_${fileName}.contract_class.json`)
      .toString()
  );

  const contract = new Contract(contractClass.abi, contractAddress, signerOrProvider);
  console.log(`✅ Connected to ${fileName}`);
  return contract;
}

export async function deployContract(
  deployerAccount: Account,
  fileName: string,
  constructorCalldata: Calldata
): Promise<Contract> {
  console.log(`👷 Deploying contract ${fileName}...`);
  try {
    const { compiledSierra, compiledCasm } = getSierraAndCasm(fileName);

    // Deploy the contract
    const deployResponse = await deployerAccount.declareAndDeploy({
      contract: compiledSierra,
      casm: compiledCasm,
      constructorCalldata: constructorCalldata,
    });

    console.log(
      `✅ Contract ${fileName} deployed at ${deployResponse.deploy.contract_address}\n`
    );
    let address = deployResponse.deploy.contract_address;
    return new Contract(compiledSierra.abi, address);
  } catch (error) {
    console.error(`❌ Error deploying contract ${fileName}:`, error);
    throw error;
  }
}
