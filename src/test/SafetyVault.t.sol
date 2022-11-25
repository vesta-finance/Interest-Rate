// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.4;

import "./base/BaseTest.t.sol";

import { SafetyVault } from "../main/SafetyVault.sol";
import { IERC20 } from "forge-std/interfaces/IERC20.sol";

contract SafetyVaultTest is BaseTest {
	address private owner = generateAddress("Owner", false);
	address private user = generateAddress("User", false);
	address private mockVST = generateAddress("VST", true);

	SafetyVault private underTest;

	function setUp() public {
		vm.warp(1666996415);
		underTest = new SafetyVault();

		vm.prank(owner);
		underTest.setUp(mockVST);
	}

	function test_setup_thenContractSetuped() external prankAs(owner) {
		underTest = new SafetyVault();
		underTest.setUp(mockVST);

		assertEq(underTest.owner(), owner);
		assertEq(underTest.vst(), mockVST);
	}

	function test_setup_whenAlreadyInitialized_thenReverts() external {
		underTest = new SafetyVault();
		underTest.setUp(mockVST);

		vm.expectRevert(REVERT_ALREADY_INITIALIZED);
		underTest.setUp(mockVST);
	}

	function test_transfer_asUser_thenReverts() external prankAs(user) {
		vm.expectRevert(NOT_OWNER);
		underTest.transfer(user, 0);
	}

	function test_transfer_asOwner_thenTransferVST()
		external
		prankAs(owner)
	{
		uint256 sendingAmount = 39.18e18;

		vm.expectCall(
			mockVST,
			abi.encodeWithSelector(IERC20.transfer.selector, user, sendingAmount)
		);

		vm.mockCall(
			mockVST,
			abi.encodeWithSelector(
				IERC20.transfer.selector,
				user,
				sendingAmount
			),
			abi.encode(true)
		);

		underTest.transfer(user, sendingAmount);
	}
}
