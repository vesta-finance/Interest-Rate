// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import { IInterestManager } from "./interface/IInterestManager.sol";

import { IModuleInterest } from "./interface/IModuleInterest.sol";
import { IPriceFeed } from "./interface/IPriceFeed.sol";

import { OwnableUpgradeable } from "openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";

contract VestaInterestManager is IInterestManager, OwnableUpgradeable {
	uint256 private vstPrice;

	address public vst;
	address public troveManager;
	IPriceFeed public oracle;

	mapping(address => address) private interestByTokens;
	address[] private interestModules;

	modifier onlyTroveManager() {
		if (msg.sender != troveManager) revert NotTroveManager();

		_;
	}

	function setUp(
		address _vst,
		address _troveManager,
		address _priceFeed
	) external initializer {
		__Ownable_init();

		vst = _vst;
		troveManager = _troveManager;
		oracle = IPriceFeed(_priceFeed);
		vstPrice = oracle.getExternalPrice(vst);

		require(vstPrice > 0, "Oracle Failed to fetch VST price.");
	}

	function setModuleFor(address _token, address _module)
		external
		onlyOwner
	{
		if (getInterestModule(_token) != address(0)) {
			revert ErrorModuleAlreadySet();
		}

		interestByTokens[_token] = _module;
		interestModules.push(_module);

		IModuleInterest(_module).updateEIR(vstPrice);
	}

	function increaseDebt(
		address _token,
		address _user,
		uint256 _debt
	) external override onlyTroveManager returns (uint256 interestDebt_) {
		_updateModules();

		return
			IModuleInterest(getInterestModule(_token)).increaseDebt(
				_user,
				_debt
			);
	}

	function decreaseDebt(
		address _token,
		address _user,
		uint256 _debt
	) external override onlyTroveManager returns (uint256 interestDebt_) {
		_updateModules();

		return
			IModuleInterest(getInterestModule(_token)).decreaseDebt(
				_user,
				_debt
			);
	}

	function _updateModules() internal {
		vstPrice = oracle.fetchPrice(vst);
		uint256 totalModules = interestModules.length;

		for (uint256 i = 0; i < totalModules; ++i) {
			IModuleInterest(interestModules[i]).updateEIR(vstPrice);
		}
	}

	function getUserDebt(address _token, address _user)
		external
		view
		override
		returns (uint256 currentDebt_, uint256 pendingInterest_)
	{
		IModuleInterest module = IModuleInterest(getInterestModule(_token));

		return (
			module.getDebtOf(_user),
			module.getNotEmittedInterestRate(_user)
		);
	}

	function getInterestModule(address _token)
		public
		view
		returns (address)
	{
		return interestByTokens[_token];
	}

	function getModules() external view returns (address[] memory) {
		return interestModules;
	}

	function getLastVstPrice() external view override returns (uint256) {
		return vstPrice;
	}
}

