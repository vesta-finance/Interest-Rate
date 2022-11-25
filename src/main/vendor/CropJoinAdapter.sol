// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "../interface/ICropJoinAdapter.sol";

import { Math } from "../lib/Math.sol";
import { IERC20 } from "forge-std/interfaces/IERC20.sol";
import { IVatLike } from "../interface/IVatLike.sol";
import { OwnableUpgradeable } from "openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";

abstract contract CropJoinAdapter is ICropJoinAdapter, OwnableUpgradeable {
	string public name;

	uint256 public share; // crops per gem    [ray]
	uint256 public stock; // crop balance     [wad]
	uint256 public totalWeight; // [wad]

	//User => Value
	mapping(address => uint256) public crops; // [wad]
	mapping(address => uint256) public userShares; // [wad]

	uint256 internal to18ConversionFactor;
	uint256 internal toGemConversionFactor;
	uint256 public interestMinted;

	uint256[49] private __gap;

	function __INIT_ADAPTOR(string memory _moduleName)
		internal
		onlyInitializing
	{
		__Ownable_init();

		name = _moduleName;
	}

	function shareOf(address owner) public view override returns (uint256) {
		return userShares[owner];
	}

	function netAssetsPerShareWAD() public view returns (uint256) {
		return
			(totalWeight == 0) ? Math.WAD : Math.wdiv(totalWeight, totalWeight);
	}

	function _crop() internal virtual returns (uint256) {
		return Math.sub(interestMinted, stock);
	}

	function _addShare(address urn, uint256 val) internal virtual {
		if (val > 0) {
			uint256 wad = Math.wdiv(val, netAssetsPerShareWAD());

			require(int256(wad) > 0);

			totalWeight = Math.add(totalWeight, wad);
			userShares[urn] = Math.add(userShares[urn], wad);
		}
		crops[urn] = Math.rmulup(userShares[urn], share);
		emit Join(val);
	}

	function _exitShare(address guy, uint256 val) internal virtual {
		if (val > 0) {
			uint256 wad = Math.wdivup(val, netAssetsPerShareWAD());

			require(int256(wad) > 0);

			totalWeight = Math.sub(totalWeight, wad);
			userShares[guy] = Math.sub(userShares[guy], wad);
		}
		crops[guy] = Math.rmulup(userShares[guy], share);
		emit Exit(val);
	}
}

