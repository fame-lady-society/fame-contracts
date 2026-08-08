// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {Fame} from "../src/Fame.sol";
import {FameMirror} from "../src/FameMirror.sol";

/// @notice Executes one receipt-ordered FAME burn-pool turn.
/// @dev Use script/dig-fame-burn-pool.sh for the bounded, canonical-state loop.
contract DigFameBurnPool is Script {
    struct DigState {
        Fame fame;
        FameMirror mirror;
        address primary;
        address secondary;
        uint256 primaryPrivateKey;
        uint256 secondaryPrivateKey;
        uint256 transferAmount;
        uint256 primaryBalance;
        uint256 secondaryBalance;
        uint256 primaryNftBalance;
    }

    error WrongChain(uint256 expected, uint256 actual);
    error InvalidFameContract(address fame);
    error InvalidMirrorContract(address mirror);
    error InvalidPrivateKey();
    error WalletHasNoNativeGas(address wallet);
    error WalletsMustDiffer();
    error InvalidUnit(uint256 unit);
    error InvalidTargetTokenId(uint256 tokenId, uint256 maxTokenId);
    error TargetOwnedElsewhere(uint256 tokenId, address owner);
    error PrimarySkipsNFTs(address primary);
    error PrimaryBalanceTooLow(uint256 balance, uint256 required);
    error SecondaryBalanceMustBeZero(uint256 balance);
    error InterruptedTurnRequiresRecovery(address secondary, uint256 balance);
    error NoInterruptedTurnToRecover(uint256 secondaryBalance);
    error OutboundTransferWouldNotBurn(address primary, uint256 nftBalance, uint256 supportedAfterTransfer);
    error TransferFailed(address from, address to, uint256 amount);
    error UnexpectedNftBalance(address owner, uint256 expected, uint256 actual);
    error UnexpectedFameBalance(address owner, uint256 expected, uint256 actual);

    event TurnCompleted(uint256 indexed targetTokenId, address targetOwner);
    event InterruptedTurnRecovered(uint256 indexed targetTokenId, address targetOwner);
    event TargetAlreadyAcquired(uint256 indexed tokenId, address indexed owner);

    function run() external returns (bool found) {
        uint256 expectedChainId = vm.envUint("BASE_CHAIN_ID");
        if (block.chainid != expectedChainId) revert WrongChain(expectedChainId, block.chainid);

        uint256 primaryPrivateKey = vm.envUint("FAME_DIG_PRIMARY_PRIVATE_KEY");
        uint256 secondaryPrivateKey = vm.envUint("FAME_DIG_SECONDARY_PRIVATE_KEY");
        if (primaryPrivateKey == 0 || secondaryPrivateKey == 0) revert InvalidPrivateKey();
        _requireNativeGas(vm.addr(primaryPrivateKey));
        _requireNativeGas(vm.addr(secondaryPrivateKey));

        return _executeTurn(
            vm.envAddress("BASE_FAME_ADDRESS"),
            primaryPrivateKey,
            secondaryPrivateKey,
            vm.envUint("FAME_DIG_TOKEN_ID"),
            vm.envOr("FAME_DIG_RECOVER_INTERRUPTED", false)
        );
    }

    function check() external view {
        uint256 expectedChainId = vm.envUint("BASE_CHAIN_ID");
        if (block.chainid != expectedChainId) revert WrongChain(expectedChainId, block.chainid);

        address fameAddress = vm.envAddress("BASE_FAME_ADDRESS");
        if (fameAddress.code.length == 0) revert InvalidFameContract(fameAddress);

        uint256 primaryPrivateKey = vm.envUint("FAME_DIG_PRIMARY_PRIVATE_KEY");
        uint256 secondaryPrivateKey = vm.envUint("FAME_DIG_SECONDARY_PRIVATE_KEY");
        if (primaryPrivateKey == 0 || secondaryPrivateKey == 0) revert InvalidPrivateKey();

        Fame fame = Fame(payable(fameAddress));
        FameMirror mirror = fame.fameMirror();
        if (address(mirror).code.length == 0) revert InvalidMirrorContract(address(mirror));

        uint256 targetTokenId = vm.envUint("FAME_DIG_TOKEN_ID");
        bool acquired = mirror.ownerAt(targetTokenId) == vm.addr(primaryPrivateKey);
        bool recoveryPossible = fame.balanceOf(vm.addr(secondaryPrivateKey)) == fame.unit() - 1;
        console2.log("FAME_DIG_STATUS_BLOCK", block.number);
        console2.log(acquired ? "FAME_DIG_TARGET_ACQUIRED=true" : "FAME_DIG_TARGET_ACQUIRED=false");
        console2.log(recoveryPossible ? "FAME_DIG_RECOVERY_POSSIBLE=true" : "FAME_DIG_RECOVERY_POSSIBLE=false");
    }

    function _executeTurn(
        address fameAddress,
        uint256 primaryPrivateKey,
        uint256 secondaryPrivateKey,
        uint256 targetTokenId,
        bool recoverInterrupted
    ) internal returns (bool found) {
        DigState memory state = _prepare(fameAddress, primaryPrivateKey, secondaryPrivateKey, targetTokenId);
        address targetOwner = state.mirror.ownerAt(targetTokenId);

        if (recoverInterrupted) {
            if (state.secondaryBalance != state.transferAmount) {
                revert NoInterruptedTurnToRecover(state.secondaryBalance);
            }
            _recoverInterruptedTurn(state);
            targetOwner = state.mirror.ownerAt(targetTokenId);
            emit InterruptedTurnRecovered(targetTokenId, targetOwner);
            return targetOwner == state.primary;
        }
        if (state.secondaryBalance == state.transferAmount) {
            revert InterruptedTurnRequiresRecovery(state.secondary, state.secondaryBalance);
        }

        if (targetOwner == state.primary) {
            emit TargetAlreadyAcquired(targetTokenId, state.primary);
            return true;
        }
        if (targetOwner != address(0)) revert TargetOwnedElsewhere(targetTokenId, targetOwner);

        if (state.secondaryBalance != 0) revert SecondaryBalanceMustBeZero(state.secondaryBalance);
        if (state.primaryBalance < state.transferAmount) {
            revert PrimaryBalanceTooLow(state.primaryBalance, state.transferAmount);
        }

        uint256 supportedAfterOutbound = (state.primaryBalance - state.transferAmount) / state.fame.unit();
        if (state.primaryNftBalance <= supportedAfterOutbound) {
            revert OutboundTransferWouldNotBurn(state.primary, state.primaryNftBalance, supportedAfterOutbound);
        }

        _runTurn(state);
        targetOwner = state.mirror.ownerAt(targetTokenId);
        emit TurnCompleted(targetTokenId, targetOwner);
        return targetOwner == state.primary;
    }

    function _requireNativeGas(address wallet) private view {
        if (wallet.balance == 0) revert WalletHasNoNativeGas(wallet);
    }

    function _prepare(
        address fameAddress,
        uint256 primaryPrivateKey,
        uint256 secondaryPrivateKey,
        uint256 targetTokenId
    ) private view returns (DigState memory state) {
        if (fameAddress.code.length == 0) revert InvalidFameContract(fameAddress);
        if (primaryPrivateKey == 0 || secondaryPrivateKey == 0) revert InvalidPrivateKey();

        state.primaryPrivateKey = primaryPrivateKey;
        state.secondaryPrivateKey = secondaryPrivateKey;
        state.primary = vm.addr(primaryPrivateKey);
        state.secondary = vm.addr(secondaryPrivateKey);
        if (state.primary == state.secondary) revert WalletsMustDiffer();

        state.fame = Fame(payable(fameAddress));
        uint256 fameUnit = state.fame.unit();
        if (fameUnit <= 1) revert InvalidUnit(fameUnit);

        uint256 maxTokenId = state.fame.totalSupply() / fameUnit;
        if (targetTokenId == 0 || targetTokenId > maxTokenId) {
            revert InvalidTargetTokenId(targetTokenId, maxTokenId);
        }

        state.mirror = state.fame.fameMirror();
        if (address(state.mirror).code.length == 0) revert InvalidMirrorContract(address(state.mirror));
        if (state.fame.getSkipNFT(state.primary)) revert PrimarySkipsNFTs(state.primary);

        state.transferAmount = fameUnit - 1;
        state.primaryBalance = state.fame.balanceOf(state.primary);
        state.secondaryBalance = state.fame.balanceOf(state.secondary);
        state.primaryNftBalance = state.mirror.balanceOf(state.primary);
    }

    function _runTurn(DigState memory state) private {
        vm.startBroadcast(state.primaryPrivateKey);
        bool outboundSucceeded = state.fame.transfer(state.secondary, state.transferAmount);
        vm.stopBroadcast();
        if (!outboundSucceeded) revert TransferFailed(state.primary, state.secondary, state.transferAmount);

        uint256 nftBalanceAfterOutbound = state.mirror.balanceOf(state.primary);
        if (nftBalanceAfterOutbound != state.primaryNftBalance - 1) {
            revert UnexpectedNftBalance(state.primary, state.primaryNftBalance - 1, nftBalanceAfterOutbound);
        }

        vm.startBroadcast(state.secondaryPrivateKey);
        bool returnSucceeded = state.fame.transfer(state.primary, state.transferAmount);
        vm.stopBroadcast();
        if (!returnSucceeded) revert TransferFailed(state.secondary, state.primary, state.transferAmount);

        _assertBalances(state, state.primaryBalance, state.secondaryBalance, state.primaryNftBalance);
    }

    function _recoverInterruptedTurn(DigState memory state) private {
        vm.startBroadcast(state.secondaryPrivateKey);
        bool returnSucceeded = state.fame.transfer(state.primary, state.transferAmount);
        vm.stopBroadcast();
        if (!returnSucceeded) revert TransferFailed(state.secondary, state.primary, state.transferAmount);

        _assertBalances(state, state.primaryBalance + state.transferAmount, 0, state.primaryNftBalance + 1);
    }

    function _assertBalances(
        DigState memory state,
        uint256 expectedPrimaryBalance,
        uint256 expectedSecondaryBalance,
        uint256 expectedPrimaryNftBalance
    ) private view {
        uint256 actualPrimaryBalance = state.fame.balanceOf(state.primary);
        if (actualPrimaryBalance != expectedPrimaryBalance) {
            revert UnexpectedFameBalance(state.primary, expectedPrimaryBalance, actualPrimaryBalance);
        }

        uint256 actualSecondaryBalance = state.fame.balanceOf(state.secondary);
        if (actualSecondaryBalance != expectedSecondaryBalance) {
            revert UnexpectedFameBalance(state.secondary, expectedSecondaryBalance, actualSecondaryBalance);
        }

        uint256 actualPrimaryNftBalance = state.mirror.balanceOf(state.primary);
        if (actualPrimaryNftBalance != expectedPrimaryNftBalance) {
            revert UnexpectedNftBalance(state.primary, expectedPrimaryNftBalance, actualPrimaryNftBalance);
        }
    }
}
