// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.17;

import { OwnableUpgradeable } from "openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";

contract SafetyVault is OwnableUpgradeable {
	function setUp() external initializer {
		__Ownable_init();
	}
}

