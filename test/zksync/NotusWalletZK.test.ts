import { Deployer } from "@matterlabs/hardhat-zksync-deploy";
import { expect } from "chai";
import { ethers } from "ethers";
import * as hre from "hardhat";
import { EIP712Signer, Provider, Wallet, types, utils } from "zksync-web3";

describe.only("NotusWalletZK", () => {
  it("Should execute batch transaction and use paymaster", async () => {
    const provider = new Provider("http://0.0.0.0:8011");
    const wallet = new Wallet(
      "0x7726827caac94a7f9e1b160f7ea819f172f7b6f9d2a97f992c38edeab82d4110",
      provider
    );

    const deployer = new Deployer(hre, wallet);

    const factoryArtifact = await deployer.loadArtifact("NotusWalletFactoryZK");
    const aaArtifact = await deployer.loadArtifact("NotusWalletZK");
    const tokenArtifact = await deployer.loadArtifact("MockToken");
    const paymasterArtifact = await deployer.loadArtifact("NotusPaymasterZK");

    const bytecodeHash = utils.hashBytecode(aaArtifact.bytecode);
    const factory = await deployer.deploy(
      factoryArtifact,
      [bytecodeHash],
      undefined,
      [aaArtifact.bytecode]
    );

    const salt = ethers.constants.HashZero;
    const tx = await factory.createAccount(salt, wallet.address);
    await tx.wait();

    const token = await deployer.deploy(tokenArtifact, [
      "Mock Token",
      "mToken",
      18,
    ]);

    const paymaster = await deployer.deploy(paymasterArtifact, [
      token.address,
      factory.address,
    ]);

    // Send Eth to Paymaster
    await wallet.sendTransaction({
      to: paymaster.address,
      value: ethers.utils.parseEther("0.1"),
    });

    const abiCoder = new ethers.utils.AbiCoder();
    // Address of AA
    const walletContractAddress = utils.create2Address(
      factory.address,
      await factory.aaBytecodeHash(),
      salt,
      abiCoder.encode(["address"], [wallet.address])
    );

    await (
      await token.mint(walletContractAddress, (5e6).toString())
    ).wait();

    const transferTx = await token.populateTransaction.mint(
      wallet.address,
      ethers.utils.parseEther("1")
    );
    const transferTx2 = await token.populateTransaction.mint(
      wallet.address,
      ethers.utils.parseEther("1")
    );

    let ABI = [
      "function executeBatchTransaction(bytes[] calldata datas, address[] calldata callers)",
    ];
    let iface = new ethers.utils.Interface(ABI);
    
    const data = iface.encodeFunctionData("executeBatchTransaction", [
      [transferTx.data, transferTx2.data],
      [token.address, token.address],
    ]);

    const gasPrice = await provider.getGasPrice();
    let multOpTx = {
      from: walletContractAddress,
      to: walletContractAddress,
      value: ethers.BigNumber.from("0"),
      gasLimit: ethers.BigNumber.from("97578666"),
      gasPrice: gasPrice,
      chainId: (await provider.getNetwork()).chainId,
      nonce: await provider.getTransactionCount(walletContractAddress),
      type: 113,
      customData: {
        paymasterParams: utils.getPaymasterParams(paymaster.address, {
          type: "ApprovalBased",
          token: token.address,
          minimalAllowance: ethers.BigNumber.from((1e6).toString()),
          innerInput: new Uint8Array(),
        }),
        gasPerPubdata: utils.DEFAULT_GAS_PER_PUBDATA_LIMIT,
      } as types.Eip712Meta,
      data,
    };

    const signedTxHash = EIP712Signer.getSignedDigest(multOpTx);
    const signature = ethers.utils.joinSignature(
      wallet._signingKey().signDigest(signedTxHash)
    );

    multOpTx.customData = {
      ...multOpTx.customData,
      customSignature: signature,
    };

    const initialBalance = await token.balanceOf(wallet.address)
    const initialAABalanceMockToken = await token.balanceOf(walletContractAddress)
    console.log(`Before tx: Balance Wallet Contract of ERC20 token to pay fee ${initialAABalanceMockToken.div((1e6.toString())).toString()}`)
    const initialETHBalance = await provider.getBalance(walletContractAddress)
    console.log(`Before tx: Balance Wallet Contract of ETH ${initialETHBalance.div((1e18).toString()).toString()}`)
    const initialPaymasterBalance = await token.balanceOf(paymaster.address)
    console.log(`Before tx: Balance Paymaster of ERC20 token before tx${initialPaymasterBalance.div((1e6).toString()).toString()}`)
    console.log('')
    console.log('Execute tx...')
    console.log('')
    const sentTx = await provider.sendTransaction(utils.serialize(multOpTx));
    await sentTx.wait();

    console.log(initialBalance.toString())
    const finalAABalanceMockToken = await token.balanceOf(walletContractAddress)
    console.log(`After tx: Balance Wallet Contract of ERC20 token to pay fee ${finalAABalanceMockToken.div((1e6).toString()).toString()}`)
    const finalETHBalance = await provider.getBalance(walletContractAddress)
    console.log(`After tx: Balance Wallet Contract of ETH ${finalETHBalance.div((1e18).toString()).toString()}`)
    const finalPaymasterBalance = await token.balanceOf(paymaster.address)
    console.log(`After tx: Balance Paymaster of ERC20 token ${finalPaymasterBalance.div((1e6).toString()).toString()}`)

    const finalBalance = await token.balanceOf(wallet.address)
    expect(finalBalance.sub(initialBalance).eq((2e18).toString())).true
    expect(initialAABalanceMockToken.sub((1e6).toString()).eq(finalAABalanceMockToken)).true
    expect(initialPaymasterBalance.add((1e6).toString()).eq(finalPaymasterBalance)).true
    expect(initialETHBalance.eq(finalETHBalance)).true
  });
});
