// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {VmSafe} from "forge-std/Vm.sol";
import "forge-std/console.sol";
import {IERC20} from "@openzeppelin5/contracts/token/ERC20/IERC20.sol";
import {Fame} from "../src/Fame.sol";
import {ClaimToFame} from "../src/ClaimToFame.sol";
import {AirdropHelper, IAirdropSource} from "./utils/AirdropHelper.sol";
import {IGasliteDrop} from "../src/IGasliteDrop.sol";
import {FameLadySocietyOwners} from "./holders/FameLadySocietyOwners.sol";
import {HunnysOwners} from "./holders/HunnysOwners.sol";
import {MermaidPowerOwners} from "./holders/MermaidPowerOwners.sol";
import {MetavixenOwners} from "./holders/MetavixenOwners.sol";
import {OnChainCheckGasOwners} from "./holders/OnChainCheckGasOwners.sol";
import {OnChainGasOwners} from "./holders/OnChainGasOwners.sol";

interface IWETH {
    function deposit() external payable;
    function transfer(address to, uint value) external returns (bool);
    function withdraw(uint) external;
}

contract DeployLaunch is Script {
    address private gasliteAddress = 0x09350F89e2D7B6e96bA730783c2d76137B045FEF;

    Fame private fame;
    IGasliteDrop public gaslite;
    FameLadySocietyOwners private societyOwners;
    HunnysOwners private hunnysOwners;
    MermaidPowerOwners private mermaidPowerOwners;
    MetavixenOwners private metavixenOwners;
    OnChainCheckGasOwners private onChainCheckGasOwners;
    OnChainGasOwners private onChainGasOwners;

    AirdropHelper private airdropHelper;

    function run() external {
        // Setup the deployer wallet
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        VmSafe.Wallet memory wallet = vm.createWallet(deployerPrivateKey);
        address fameAddress = vm.envAddress("FAME_ADDRESS");
        fame = Fame(payable(fameAddress));
        gaslite = IGasliteDrop(gasliteAddress);

        // Utility to help with the airdrop
        airdropHelper = new AirdropHelper();
        // These are the holders of the airdrop tokens
        hunnysOwners = new HunnysOwners();
        mermaidPowerOwners = new MermaidPowerOwners();
        metavixenOwners = new MetavixenOwners();
        societyOwners = new FameLadySocietyOwners();
        onChainCheckGasOwners = new OnChainCheckGasOwners();
        onChainGasOwners = new OnChainGasOwners();

        vm.startBroadcast(deployerPrivateKey);

        uint256 signerPrivateKey = vm.envUint("SIGNER_PRIVATE_KEY");
        VmSafe.Wallet memory signerWallet = vm.createWallet(signerPrivateKey);
        ClaimToFame ctf = new ClaimToFame(address(fame), signerWallet.addr);
        ctf.grantRoles(wallet.addr, ctf.roleSigner() | ctf.roleClaimPrimer());

        // Calculate the total airdrop amount
        uint256 totalAmount = 0;
        uint256 societyAmount = 0;
        uint256 hunnysAmount = 0;
        uint256 mermaidPowerAmount = 0;
        uint256 metavixenAmount = 0;
        uint256 onChainCheckGasAmount = 0;
        uint256 onChainGasAmount = 0;

        uint256 allocationPerSisterToken = airdropHelper
            .allocationPerSisterToken(fame.totalSupply());

        societyAmount = airdropHelper.totalFromContract(
            IAirdropSource(address(societyOwners))
        );
        totalAmount += societyAmount;
        console.log("Society amount: %d", societyAmount);

        // fame.launchPublic();
        fame.approve(gasliteAddress, societyAmount);

        console.log("Airdropping to society");
        airdrop(
            IERC20(address(fame)),
            IAirdropSource(address(societyOwners)),
            1
        );
        console.log(
            "Leftover allowance for society: %d",
            fame.allowance(
                vm.createWallet(vm.envUint("DEPLOYER_PRIVATE_KEY")).addr,
                gasliteAddress
            )
        );

        hunnysAmount =
            airdropHelper.totalFromContract(
                IAirdropSource(address(hunnysOwners))
            ) *
            allocationPerSisterToken;
        totalAmount += hunnysAmount;
        console.log("Hunnys amount: %d", hunnysAmount);

        mermaidPowerAmount =
            airdropHelper.totalFromContract(
                IAirdropSource(address(mermaidPowerOwners))
            ) *
            allocationPerSisterToken;
        totalAmount += mermaidPowerAmount;
        console.log("Mermaid Power amount: %d", mermaidPowerAmount);

        metavixenAmount =
            airdropHelper.totalFromContract(
                IAirdropSource(address(metavixenOwners))
            ) *
            allocationPerSisterToken *
            airdropHelper.METAVIXEN_BOOST();
        totalAmount += metavixenAmount;
        console.log("Metavixen amount: %d", metavixenAmount);

        console.log(
            "Total sister amount: %d",
            metavixenAmount + mermaidPowerAmount + hunnysAmount
        );
        console.log("Total amount: %d", totalAmount);

        fame.approve(gasliteAddress, hunnysAmount);
        console.log("Airdropping to hunnys");
        airdrop(
            IERC20(address(fame)),
            IAirdropSource(address(hunnysOwners)),
            allocationPerSisterToken
        );
        console.log(
            "Leftover allowance for hunnys: %d",
            fame.allowance(
                vm.createWallet(vm.envUint("DEPLOYER_PRIVATE_KEY")).addr,
                gasliteAddress
            )
        );
        require(
            fame.allowance(
                vm.createWallet(vm.envUint("DEPLOYER_PRIVATE_KEY")).addr,
                gasliteAddress
            ) == 0,
            "Allowance not reset for hunnys"
        );

        fame.approve(gasliteAddress, mermaidPowerAmount);
        console.log("Airdropping to mermaid power");
        airdrop(
            IERC20(address(fame)),
            IAirdropSource(address(mermaidPowerOwners)),
            allocationPerSisterToken
        );
        console.log(
            "Leftover allowance for mermaid power: %d",
            fame.allowance(
                vm.createWallet(vm.envUint("DEPLOYER_PRIVATE_KEY")).addr,
                gasliteAddress
            )
        );
        require(
            fame.allowance(
                vm.createWallet(vm.envUint("DEPLOYER_PRIVATE_KEY")).addr,
                gasliteAddress
            ) == 0,
            "Allowance not reset for mermaid power"
        );

        fame.approve(gasliteAddress, metavixenAmount);
        console.log("Airdropping to metavixen");
        airdrop(
            IERC20(address(fame)),
            IAirdropSource(address(metavixenOwners)),
            allocationPerSisterToken * airdropHelper.METAVIXEN_BOOST()
        );
        console.log(
            "Leftover allowance for metavixen: %d",
            fame.allowance(
                vm.createWallet(vm.envUint("DEPLOYER_PRIVATE_KEY")).addr,
                gasliteAddress
            )
        );
        require(
            fame.allowance(
                vm.createWallet(vm.envUint("DEPLOYER_PRIVATE_KEY")).addr,
                gasliteAddress
            ) == 0,
            "Allowance not reset for metavixen"
        );

        fame.approve(gasliteAddress, onChainCheckGasAmount);
        console.log("Airdropping to onChainCheckGas");
        airdrop(
            IERC20(address(fame)),
            IAirdropSource(address(onChainCheckGasOwners)),
            airdropHelper.sisterTokenAmount(fame.totalSupply()) / 1870
        );
        console.log(
            "Leftover allowance for onChainCheckGas: %d",
            fame.allowance(
                vm.createWallet(vm.envUint("DEPLOYER_PRIVATE_KEY")).addr,
                gasliteAddress
            )
        );

        fame.approve(gasliteAddress, onChainGasAmount);
        console.log("Airdropping to onChainGas");
        airdrop(
            IERC20(address(fame)),
            IAirdropSource(address(onChainGasOwners)),
            airdropHelper.sisterTokenAmount(fame.totalSupply()) / 1000
        );
        console.log(
            "Leftover allowance for onChainGas: %d",
            fame.allowance(
                vm.createWallet(vm.envUint("DEPLOYER_PRIVATE_KEY")).addr,
                gasliteAddress
            )
        );

        fame.transfer(
            address(ctf),
            airdropHelper.baseTokenAmount(fame.totalSupply()) + societyAmount
        );
        console.log("Transferred %d to CTF", fame.balanceOf(address(ctf)));
        ctf.primeClaim(
            0x6cF4328f1Ea83B5d592474F9fCDC714FAAfd1574,
            convertToUint16Array(societyOwners.allTokenIds())
        );
        ctf.primeClaim(
            0x6cF4328f1Ea83B5d592474F9fCDC714FAAfd1574,
            convertToUint16Array(societyOwners.allBannedTokenIds())
        );

        address multisigAddress = vm.envAddress("MULTISIG_ADDRESS");
        fame.transfer(
            multisigAddress,
            fame.balanceOf(
                vm.createWallet(vm.envUint("DEPLOYER_PRIVATE_KEY")).addr
            )
        );
        console.log(
            "Transferred %d to multisig",
            fame.balanceOf(multisigAddress)
        );
        vm.stopBroadcast();
    }

    function airdrop(
        IERC20 token,
        IAirdropSource airdropSource,
        uint256 multiplier
    ) public {
        address[] memory allOwners = airdropSource.allOwners();
        uint256 totalOwners = allOwners.length;
        uint256 batchSize = 500;
        uint256 processed = 0;

        do {
            uint256 batchEnd = processed + batchSize > totalOwners
                ? totalOwners
                : processed + batchSize;
            address[] memory batchOwners = new address[](batchEnd - processed);
            uint256[] memory amounts = new uint256[](batchEnd - processed);
            uint256 totalAmount = 0;

            for (uint256 i = processed; i < batchEnd; i++) {
                address owner = allOwners[i];
                require(owner != address(0), "Invalid owner");
                require(airdropSource.balanceOf(owner) > 0, "Invalid amount");
                uint256 amount = airdropSource.balanceOf(owner) * multiplier;
                batchOwners[i - processed] = owner;
                amounts[i - processed] = amount;
                totalAmount += amount;
            }

            console.log(
                "Airdropping %s tokens to %d addresses",
                totalAmount,
                batchOwners.length
            );

            gaslite.airdropERC20(
                address(token),
                batchOwners,
                amounts,
                totalAmount
            );
            processed += batchOwners.length;
        } while (processed < totalOwners);
    }

    function convertToUint16Array(
        uint256[] memory inputArray
    ) public pure returns (uint16[] memory) {
        uint16[] memory outputArray = new uint16[](inputArray.length);

        for (uint256 i = 0; i < inputArray.length; i++) {
            // Ensure the uint256 value is within the uint16 range
            require(inputArray[i] <= 0xFFFF, "Value exceeds uint16 range");
            outputArray[i] = uint16(inputArray[i]);
        }

        return outputArray;
    }
}
