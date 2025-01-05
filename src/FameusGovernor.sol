// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.22;

import {Governor} from "@openzeppelin5/contracts/governance/Governor.sol";
import {GovernorCountingSimple} from "@openzeppelin5/contracts/governance/extensions/GovernorCountingSimple.sol";
import {GovernorSettings} from "@openzeppelin5/contracts/governance/extensions/GovernorSettings.sol";
import {GovernorStorage} from "@openzeppelin5/contracts/governance/extensions/GovernorStorage.sol";
import {GovernorTimelockControl} from "@openzeppelin5/contracts/governance/extensions/GovernorTimelockControl.sol";
import {GovernorVotes} from "@openzeppelin5/contracts/governance/extensions/GovernorVotes.sol";
import {IVotes} from "@openzeppelin5/contracts/governance/utils/IVotes.sol";
import {TimelockController} from "@openzeppelin5/contracts/governance/TimelockController.sol";
import {GovSociety} from "./GovSociety.sol";
import {FameusGovernorQuorum} from "./FameusGovernorQuorum.sol";
interface IFameusGovernorQuorum {
    function quorum(uint256 blockNumber) external view returns (uint256);
}

contract FAMEusGovernor is
    Governor,
    GovernorSettings,
    GovernorCountingSimple,
    GovernorStorage,
    GovernorVotes,
    GovernorTimelockControl
{
    GovSociety private _societyToken;
    IFameusGovernorQuorum private _quorum;

    constructor(
        GovSociety _token,
        TimelockController _timelock,
        uint48 _votingDelay,
        uint32 _votingPeriod,
        uint256 _proposalThreshold
    )
        Governor("FAMEusGovernor")
        GovernorSettings(_votingDelay, _votingPeriod, _proposalThreshold)
        GovernorVotes(IVotes(_token))
        GovernorTimelockControl(_timelock)
    {
        _societyToken = _token;
        _quorum = IFameusGovernorQuorum(
            address(new FameusGovernorQuorum(_token))
        );
    }

    function quorum(
        uint256 blockNumber
    ) public view override returns (uint256) {
        return _quorum.quorum(blockNumber);
    }

    modifier onlyTimelock() {
        require(
            msg.sender == address(timelock()),
            "Only timelock can call this"
        );
        _;
    }

    function setQuorum(IFameusGovernorQuorum newQuorum) public onlyTimelock {
        _quorum = newQuorum;
    }

    function getQuorum() public view returns (IFameusGovernorQuorum) {
        return _quorum;
    }

    // The following functions are overrides required by Solidity.
    function votingDelay()
        public
        view
        override(Governor, GovernorSettings)
        returns (uint256)
    {
        return super.votingDelay();
    }

    function votingPeriod()
        public
        view
        override(Governor, GovernorSettings)
        returns (uint256)
    {
        return super.votingPeriod();
    }

    function state(
        uint256 proposalId
    )
        public
        view
        override(Governor, GovernorTimelockControl)
        returns (ProposalState)
    {
        return super.state(proposalId);
    }

    function proposalNeedsQueuing(
        uint256 proposalId
    ) public view override(Governor, GovernorTimelockControl) returns (bool) {
        return super.proposalNeedsQueuing(proposalId);
    }

    function proposalThreshold()
        public
        view
        override(Governor, GovernorSettings)
        returns (uint256)
    {
        return super.proposalThreshold();
    }

    function _propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description,
        address proposer
    ) internal override(Governor, GovernorStorage) returns (uint256) {
        return
            super._propose(targets, values, calldatas, description, proposer);
    }

    function _queueOperations(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) returns (uint48) {
        return
            super._queueOperations(
                proposalId,
                targets,
                values,
                calldatas,
                descriptionHash
            );
    }

    function _executeOperations(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) {
        super._executeOperations(
            proposalId,
            targets,
            values,
            calldatas,
            descriptionHash
        );
    }

    function _cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) returns (uint256) {
        return super._cancel(targets, values, calldatas, descriptionHash);
    }

    function _executor()
        internal
        view
        override(Governor, GovernorTimelockControl)
        returns (address)
    {
        return super._executor();
    }
}
