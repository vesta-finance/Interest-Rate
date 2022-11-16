// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity >=0.8.0;

interface IPriceFeed {
	/// @notice fetchPrice gets external oracles price and update the storage value.
	/// @param _token the token you want to price. Needs to be supported by the wrapper.
	/// @return Return the correct price in 1e18 based on the verifaction contract.
	function fetchPrice(address _token) external returns (uint256);

	/// @notice getExternalPrice gets external oracles price and update the storage value.
	/// @param _token the token you want to price. Needs to be supported by the wrapper.
	/// @return The current price reflected on the external oracle in 1e18 format.
	function getExternalPrice(address _token)
		external
		view
		returns (uint256);
}