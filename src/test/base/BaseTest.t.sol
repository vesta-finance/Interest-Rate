// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/console.sol";

contract BaseTest is Test {
	bytes internal constant NOT_OWNER = "Ownable: caller is not the owner";
	bytes internal constant ERC20_INVALID_BALANCE =
		"ERC20: transfer amount exceeds balance";

	bytes internal constant REVERT_ALREADY_INITIALIZED =
		"Initializable: contract is already initialized";

	uint256 private seed;

	modifier prankAs(address caller) {
		vm.startPrank(caller);
		_;
		vm.stopPrank();
	}

	function generateAddress(string memory _name, bool _isContract)
		internal
		returns (address)
	{
		return generateAddress(_name, _isContract, 0);
	}

	function generateAddress(
		string memory _name,
		bool _isContract,
		uint256 _eth
	) internal returns (address newAddress_) {
		seed++;
		newAddress_ = vm.addr(seed);

		vm.label(newAddress_, _name);

		if (_isContract) {
			vm.etch(newAddress_, "Generated Contract Address");
		}

		vm.deal(newAddress_, _eth);

		return newAddress_;
	}

	function assertEqTolerance(
		uint256 a,
		uint256 b,
		uint256 tolerancePercentage //4 decimals
	) internal {
		uint256 diff = b > a ? b - a : a - b;
		uint256 maxForgivness = (b * tolerancePercentage) / 100_000;

		if (maxForgivness < diff) {
			emit log("Error: a == b not satisfied [with tolerance]");
			emit log_named_uint("  A", a);
			emit log_named_uint("  B", b);
			emit log_named_uint("  Max tolerance", maxForgivness);
			emit log_named_uint("    Actual Difference", diff);
			fail();
		}
	}
}

