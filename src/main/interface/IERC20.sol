// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface IERC20 {
	function balanceOf(address owner) external view returns (uint256);

	function transfer(address dst, uint256 amount) external returns (bool);

	function transferFrom(
		address src,
		address dst,
		uint256 amount
	) external returns (bool);

	function approve(address spender, uint256 amount)
		external
		returns (bool);

	function allowance(address owner, address spender)
		external
		view
		returns (uint256);

	function decimals() external returns (uint8);
}

