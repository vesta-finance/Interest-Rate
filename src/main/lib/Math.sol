// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

library Math {
	uint256 constant WAD = 10**18;
	uint256 constant RAY = 10**27;

	function add(uint256 x, uint256 y) internal pure returns (uint256 z) {
		require((z = x + y) >= x, "ds-math-add-overflow");
	}

	function sub(uint256 x, uint256 y) internal pure returns (uint256 z) {
		require((z = x - y) <= x, "ds-math-sub-underflow");
	}

	function mul(uint256 x, uint256 y) internal pure returns (uint256 z) {
		require(y == 0 || (z = x * y) / y == x, "ds-math-mul-overflow");
	}

	function divup(uint256 x, uint256 y) internal pure returns (uint256 z) {
		z = add(x, sub(y, 1)) / y;
	}

	function wmul(uint256 x, uint256 y) internal pure returns (uint256 z) {
		z = mul(x, y) / WAD;
	}

	function wdiv(uint256 x, uint256 y) internal pure returns (uint256 z) {
		z = mul(x, WAD) / y;
	}

	function wdivup(uint256 x, uint256 y) internal pure returns (uint256 z) {
		z = divup(mul(x, WAD), y);
	}

	function rmul(uint256 x, uint256 y) internal pure returns (uint256 z) {
		z = mul(x, y) / RAY;
	}

	function rmulup(uint256 x, uint256 y) internal pure returns (uint256 z) {
		z = divup(mul(x, y), RAY);
	}

	function rdiv(uint256 x, uint256 y) internal pure returns (uint256 z) {
		z = mul(x, RAY) / y;
	}
}

