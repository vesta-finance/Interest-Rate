// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.17;

import { IModuleInterest } from "./interface/IModuleInterest.sol";
import { IVSTOperator } from "./interface/IVSTOperator.sol";
import { IERC20 } from "./interface/IERC20.sol";
import { IInterestManager } from "./interface/IInterestManager.sol";

import { CropJoinAdapter, Math } from "./vendor/CropJoinAdapter.sol";
import { FullMath } from "./lib/FullMath.sol";

import { PRBMathSD59x18 } from "prb-math/PRBMathSD59x18.sol";
import { PRBMathUD60x18 } from "prb-math/PRBMathUD60x18.sol";

contract VestaEIR is CropJoinAdapter, IModuleInterest {
	using PRBMathSD59x18 for int256;
	using PRBMathUD60x18 for uint256;

	uint256 public constant PRECISION = 1e18;
	uint256 private YEAR_MINUTE = 1.901285e6;
	uint256 private constant COMPOUND = 2.71828e18;

	uint256 public currentEIR;
	uint256 public lastUpdate;
	uint256 public totalDebt;
	uint8 public currentRisk;

	IERC20 public vst;
	IVSTOperator public vstOperator;
	address public safetyVault;
	uint8 public risk;

	address public interestManager;
	mapping(address => uint256) private balances;

	modifier onlyInterestManager() {
		if (msg.sender != interestManager) {
			revert NotInterestManager();
		}

		_;
	}

	function setUp(
		address _vst,
		address _vstOperator,
		address _safetyVault,
		address _interestManager,
		string memory _moduleName,
		string memory _moduleSymbol,
		uint8 _defaultRisk
	) external initializer {
		__INIT_ADAPTOR(_moduleName, _moduleSymbol);

		vst = IERC20(_vst);
		vstOperator = IVSTOperator(_vstOperator);
		safetyVault = _safetyVault;
		interestManager = _interestManager;
		risk = _defaultRisk;

		lastUpdate = block.timestamp;
		_updateEIR(IInterestManager(_interestManager).getLastVstPrice());
	}

	function setRisk(uint8 _newRisk) external onlyOwner {
		risk = _newRisk;
		_updateEIR(IInterestManager(interestManager).getLastVstPrice());

		emit RiskChanged(_newRisk);
	}

	function setSafetyVault(address _newSafetyVault) external onlyOwner {
		safetyVault = _newSafetyVault;
	}

	function increaseDebt(address _vault, uint256 _debt)
		external
		override
		onlyInterestManager
		returns (uint256 addedInterest_)
	{
		uint256 newShare = PRECISION;
		addedInterest_ = _distributeInterestRate(_vault);

		uint256 totalBalance = balances[_vault] += _debt;

		if (total > 0) {
			newShare = (total * (_debt + addedInterest_)) / totalDebt;
		}

		_mint(_vault, newShare);
		totalDebt += _debt;

		emit DebtChanged(_vault, totalBalance);
		emit SystemDebtChanged(totalDebt);

		return addedInterest_;
	}

	function decreaseDebt(address _vault, uint256 _debt)
		external
		override
		onlyInterestManager
		returns (uint256 addedInterest_)
	{
		if (_debt == 0) revert CannotBeZero();

		addedInterest_ = _distributeInterestRate(_vault);

		uint256 newShare = 0;
		uint256 balanceTotal = balances[_vault];

		balanceTotal = balances[_vault] -= _debt;
		if (total > 0 && balanceTotal > 0) {
			newShare = (total * balanceTotal) / totalDebt;
		}
		_burn(_vault, balanceOf(_vault));
		_mint(_vault, newShare);

		totalDebt -= _debt;

		emit DebtChanged(_vault, balanceTotal);
		emit SystemDebtChanged(totalDebt);

		return addedInterest_;
	}

	function exit(address _vault)
		external
		override
		onlyInterestManager
		returns (uint256 addedInterest_)
	{
		if (balances[_vault] == 0) revert NoDebtFound();

		addedInterest_ = _distributeInterestRate(_vault);

		balances[_vault] = 0;

		_burn(_vault, balanceOf(_vault));

		return addedInterest_;
	}

	function updateEIR(uint256 _vstPrice)
		external
		override
		onlyInterestManager
		returns (uint256 mintedInterest_)
	{
		return _updateEIR(_vstPrice);
	}

	function _updateEIR(uint256 _vstPrice)
		internal
		returns (uint256 mintedInterest_)
	{
		uint256 newEIR = getEIR(risk, _vstPrice);
		uint256 oldEIR = currentEIR;

		uint256 lastDebt = totalDebt;
		uint256 minuteDifference = (block.timestamp - lastUpdate) / 1 minutes;
		currentEIR = newEIR;

		if (minuteDifference == 0) return 0;

		lastUpdate = block.timestamp;

		totalDebt += compound(
			oldEIR,
			totalDebt,
			minuteDifference * YEAR_MINUTE
		);

		uint256 interest = totalDebt - lastDebt;

		interestMinted += interest;

		vstOperator.mint(address(safetyVault), interest);
		emit InterestMinted(interest);

		return interest;
	}

	function _distributeInterestRate(address _user)
		internal
		returns (uint256 emittedFee_)
	{
		if (total > 0) share = Math.add(share, Math.rdiv(_crop(), total));

		uint256 last = crops[_user];
		uint256 curr = Math.rmul(stake[_user], share);
		if (curr > last) {
			emittedFee_ = curr - last;
			balances[_user] += emittedFee_;
			interestMinted -= emittedFee_;
		}

		stock = interestMinted;
		return emittedFee_;
	}

	function compound(
		uint256 _eir,
		uint256 _debt,
		uint256 _timeInYear
	) public pure returns (uint256) {
		return
			FullMath.mulDiv(
				_debt,
				COMPOUND.pow((_eir * 100) * _timeInYear),
				1e18
			) - _debt;
	}

	function getNotEmittedInterestRate(address user)
		external
		view
		override
		returns (uint256)
	{
		if (total == 0) return 0;

		uint256 minuteDifference = (block.timestamp - lastUpdate) / 1 minutes;
		uint256 incomingMinting = 0;

		if (minuteDifference != 0) {
			incomingMinting = compound(
				currentEIR,
				totalDebt,
				minuteDifference * YEAR_MINUTE
			);
		}

		// duplicate harvest logic
		uint256 crop = Math.sub(interestMinted + incomingMinting, stock);
		uint256 share = Math.add(share, Math.rdiv(crop, total));

		uint256 last = this.crops(user);
		uint256 curr = Math.rmul(this.stake(user), share);
		if (curr > last) return curr - last;
		return 0;
	}

	function getEIR(uint8 _risk, uint256 _price)
		public
		pure
		returns (uint256)
	{
		if (_price < 0.95e18) {
			_price = 0.95e18;
		} else if (_price > 1.05e18) {
			_price = 1.05e18;
		}

		int256 P = ((int256(_price) - 1 ether)) / 1e2;

		uint256 a;

		if (_risk == 0) {
			a = 0.5e4;
		} else if (_risk == 1) {
			a = 0.75e4;
		} else {
			a = 1.25e4;
		}

		int256 exp = (-1.0397e4 * P);
		return uint256(FullMath.mulDivRoundingUp(a, uint256(exp.exp()), 1e20)); // Scale to BPS
	}

	function getDebtOf(address _vault)
		external
		view
		override
		returns (uint256)
	{
		return balances[_vault];
	}
}

