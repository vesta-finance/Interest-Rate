// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "./vendor/CropJoin.sol";

// NOTE! - this is not an ERC20 token. transfer is not supported.
abstract contract CropJoinAdapter is CropJoin {
	uint256 public constant decimals = 18;
	string public name;
	string public symbol;

	uint256[49] private __gap;

	event Transfer(
		address indexed _from,
		address indexed _to,
		uint256 _value
	);

	function __INIT_ADAPTOR(
		string memory _moduleName,
		string memory _moduleSymbol,
		address _distributedToken
	) internal onlyInitializing {
		__INIT_CROP(
			address(new Dummy()),
			"VESTA.EIR",
			address(new DummyGem()),
			_distributedToken
		);
		name = _moduleName;
		symbol = _moduleSymbol;
	}

	function netAssetValuation() public view override returns (uint256) {
		return total;
	}

	function totalSupply() public view returns (uint256) {
		return total;
	}

	function balanceOf(address owner) public view returns (uint256 balance) {
		balance = stake[owner];
	}

	function mint(address to, uint256 value) internal virtual {
		join(to, value);
		emit Transfer(address(0), to, value);
	}

	function burn(address owner, uint256 value) internal virtual {
		exit(owner, value);
		emit Transfer(owner, address(0), value);
	}
}

contract Dummy {
	fallback() external {}
}

contract DummyGem is Dummy {
	function transfer(address, uint256) external pure returns (bool) {
		return true;
	}

	function transferFrom(
		address,
		address,
		uint256
	) external pure returns (bool) {
		return true;
	}

	function decimals() external pure returns (uint256) {
		return 18;
	}
}

