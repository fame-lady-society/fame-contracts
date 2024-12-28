// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import "@openzeppelin5/contracts/governance/TimelockController.sol";
import {FAMEusGovernor} from "./FameusGovernor.sol";
import {GovSociety} from "./GovSociety.sol";

contract FAMEusTimelockController is TimelockController {
    FAMEusGovernor public governor;
    constructor(
        GovSociety _token,
        uint256 timelockDelay,
        address canceller,
        uint48 _votingDelay,
        uint32 _votingPeriod,
        uint256 _proposalThreshold
    )
        TimelockController(
            timelockDelay,
            new address[](0),
            new address[](0),
            address(0)
        )
    {
        governor = new FAMEusGovernor(
            _token,
            TimelockController(payable(address(this))),
            _votingDelay,
            _votingPeriod,
            _proposalThreshold
        );
        _grantRole(PROPOSER_ROLE, address(governor));
        _grantRole(CANCELLER_ROLE, address(governor));
        _grantRole(EXECUTOR_ROLE, address(governor));
        _grantRole(CANCELLER_ROLE, canceller);
    }
}
