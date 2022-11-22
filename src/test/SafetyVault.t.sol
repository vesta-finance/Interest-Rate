// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.4;

import "./base/BaseTest.t.sol";
import { SafetyVault } from "../main/SafetyVault.sol";

contract SafetyVaultTest is BaseTest {
	address private owner = generateAddress("Owner", false);

	SafetyVault private underTest;

	function setUp() public {
		vm.warp(1666996415);
		underTest = new SafetyVault();

		vm.prank(owner);
		underTest.setUp();
	}

	function test_setup_thenCallerIsOwner() external prankAs(owner) {
		underTest = new SafetyVault();
		underTest.setUp();

		assertEq(underTest.owner(), owner);
	}

	function test_setup_whenAlreadyInitialized_thenReverts() external {
		underTest = new SafetyVault();
		underTest.setUp();

		vm.expectRevert(REVERT_ALREADY_INITIALIZED);
		underTest.setUp();
	}
}
