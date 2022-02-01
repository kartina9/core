import '@nomiclabs/hardhat-ethers';
import { BytesLike, Signer, Wallet, ContractTransaction, BaseContract, Contract } from 'ethers';
import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { LensHub__factory } from '../../typechain-types';
import fs from 'fs';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';

export const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000';

export enum ProtocolState {
  Unpaused,
  PublishingPaused,
  Paused,
}

export function getAddrs(): any {
  const json = fs.readFileSync('addresses.json', 'utf8');
  const addrs = JSON.parse(json);
  return addrs;
}

export async function waitForTx(tx: Promise<ContractTransaction>) {
  await (await tx).wait();
}

export async function deployContract(tx: any): Promise<Contract> {
  const result = await tx;
  await result.deployTransaction.wait();
  return result;
}

export async function deployWithVerify(
  tx: any,
  args: any,
  contractPath: string,
  hre: HardhatRuntimeEnvironment
): Promise<any> {
  const deployedContract = await deployContract(tx);
  let count = 0;
  let maxTries = 5;
  while (true) {
    try {
      console.log('Verifying contract at', deployedContract.address);
      await hre.run('verify:verify', {
        address: deployedContract.address,
        constructorArguments: args,
        contract: contractPath,
      });
      break;
    } catch (error) {
      if (++count == maxTries) {
        console.log(
          `Failed to verify contract at ${contractPath} at address ${deployedContract.address}, error: ${error}`
        );
        break;
      }
      console.log(`Retrying... Retry #${count}`)
    }
    await delay(5000);
  }

  return deployContract;
}

export async function initEnv(hre: HardhatRuntimeEnvironment): Promise<SignerWithAddress[]> {
  const ethers = hre.ethers; // This allows us to access the hre (Hardhat runtime environment)'s injected ethers instance easily

  const accounts = await ethers.getSigners(); // This returns an array of the default signers connected to the hre's ethers instance
  const governance = accounts[1];
  const treasury = accounts[2];
  const user = accounts[3];

  return [governance, treasury, user];
}

async function delay(ms: number) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
