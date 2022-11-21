pragma solidity ^0.8.17;

import "./interface/IModuleInterest.sol";
import "./interface/IPriceFeed.sol";
import "./interface/IInterestManager.sol";
import { OwnableUpgradeable } from "openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";

contract VestaInterestManager is IInterestManager, OwnableUpgradeable {
	error NotInterestManager();
	error ErrorModuleAlreadySet();

	address public vst;
	address public troveManager;
	IPriceFeed public oracle;

	uint256 private vstPrice;

	mapping(address => address) private interestByTokens;
	address[] private interestModules;

	modifier onlyTroveManager() {
		if (msg.sender != troveManager) revert NotInterestManager();

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
		if (_getInterestModule(_token) != address(0)) {
			revert ErrorModuleAlreadySet();
		}

		interestByTokens[_token] = _module;
		interestModules.push(_module);
	}

	function increaseDebt(
		address _token,
		address _user,
		uint256 _debt
	) external override onlyTroveManager returns (uint256 interestDebt_) {
		_updateModules();

		return
			IModuleInterest(_getInterestModule(_token)).increaseDebt(
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
			IModuleInterest(_getInterestModule(_token)).decreaseDebt(
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
		IModuleInterest module = IModuleInterest(_getInterestModule(_token));

		return (
			module.getDebtOf(_user),
			module.getNotEmittedInterestRate(_user)
		);
	}

	function _getInterestModule(address _token)
		internal
		view
		returns (address)
	{
		return interestByTokens[_token];
	}

	function getLastVstPrice() external view override returns (uint256) {
		return vstPrice;
	}
}

