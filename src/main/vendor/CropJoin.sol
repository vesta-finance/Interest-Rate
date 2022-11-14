// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2021 Dai Foundation
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

pragma solidity ^0.8.17;

import { Math } from "./lib/Math.sol";
import { IERC20 } from "./interface/IERC20.sol";
import { IVatLike } from "./interface/IVatLike.sol";

// receives tokens and shares them among holders
abstract contract CropJoin {
	IVatLike public immutable vat; // cdp engine
	bytes32 public immutable ilk; // collateral type
	IERC20 public immutable gem; // collateral token
	uint256 public immutable dec; // gem decimals
	IERC20 public immutable bonus; // rewards token

	uint256 public share; // crops per gem    [ray]
	uint256 public total; // total gems       [wad]
	uint256 public stock; // crop balance     [wad]

	mapping(address => uint256) public crops; // crops per user  [wad]
	mapping(address => uint256) public stake; // gems per user   [wad]

	uint256 internal immutable to18ConversionFactor;
	uint256 internal immutable toGemConversionFactor;

	// --- Events ---
	event Join(uint256 val);
	event Exit(uint256 val);
	event Flee();
	event Tack(address indexed src, address indexed dst, uint256 wad);

	constructor(
		address vat_,
		bytes32 ilk_,
		address gem_,
		address bonus_
	) {
		vat = IVatLike(vat_);
		ilk = ilk_;
		gem = IERC20(gem_);
		uint256 dec_ = IERC20(gem_).decimals();
		require(dec_ <= 18);
		dec = dec_;
		to18ConversionFactor = 10**(18 - dec_);
		toGemConversionFactor = 10**dec_;

		bonus = IERC20(bonus_);
	}

	// Net Asset Valuation [wad]
	function netAssetValuation() public virtual returns (uint256) {
		uint256 _netAssetValuation = gem.balanceOf(address(this));
		return Math.mul(_netAssetValuation, to18ConversionFactor);
	}

	// Net Assets per Share [wad]
	function netAssetsPerShare() public returns (uint256) {
		if (total == 0) return Math.WAD;
		else return Math.wdiv(netAssetValuation(), total);
	}

	function crop() internal virtual returns (uint256) {
		return Math.sub(bonus.balanceOf(address(this)), stock);
	}

	function harvest(address from, address to) internal {
		if (total > 0) share = Math.add(share, Math.rdiv(crop(), total));

		uint256 last = crops[from];
		uint256 curr = Math.rmul(stake[from], share);
		if (curr > last) require(bonus.transfer(to, curr - last));
		stock = bonus.balanceOf(address(this));
	}

	function join(address urn, uint256 val) internal virtual {
		harvest(urn, urn);
		if (val > 0) {
			uint256 wad = Math.wdiv(
				Math.mul(val, to18ConversionFactor),
				netAssetsPerShare()
			);

			// Overflow check for int256(wad) cast below
			// Also enforces a non-zero wad
			require(int256(wad) > 0);

			require(gem.transferFrom(msg.sender, address(this), val));
			vat.slip(ilk, urn, int256(wad));

			total = Math.add(total, wad);
			stake[urn] = Math.add(stake[urn], wad);
		}
		crops[urn] = Math.rmulup(stake[urn], share);
		emit Join(val);
	}

	function exit(address guy, uint256 val) internal virtual {
		harvest(msg.sender, guy);
		if (val > 0) {
			uint256 wad = Math.wdivup(
				Math.mul(val, to18ConversionFactor),
				netAssetsPerShare()
			);

			// Overflow check for int256(wad) cast below
			// Also enforces a non-zero wad
			require(int256(wad) > 0);

			require(gem.transfer(guy, val));
			vat.slip(ilk, msg.sender, -int256(wad));

			total = Math.sub(total, wad);
			stake[msg.sender] = Math.sub(stake[msg.sender], wad);
		}
		crops[msg.sender] = Math.rmulup(stake[msg.sender], share);
		emit Exit(val);
	}
}

