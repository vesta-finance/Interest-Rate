// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.17;

import "./lib/FullMath.sol";
import "./CropJoinAdapter.sol";
import "./interface/IVSTOperator.sol";
import "./interface/IERC20.sol";
import "./interface/IPriceFeed.sol";

import "prb-math/PRBMathSD59x18.sol";
import "prb-math/PRBMathUD60x18.sol";

contract VestaEIR is CropJoinAdapter {
	using PRBMathSD59x18 for int256;
	using PRBMathUD60x18 for uint256;

	uint256 public constant PRECISION = 1e18;
	uint256 private YEAR_MINUTE = 1.901285e6;
	uint256 private constant COMPOUND = 2.71828e18;

	uint256 public currentEIR;
	uint256 public lastUpdate;
	uint256 public totalDebt;
	uint8 public currentRisk;

	mapping(address => uint256) public balances;

	IERC20 public vst;
	IVSTOperator public vstOperator;
	IPriceFeed public oracle;
	address public safetyVault;
	uint8 public risk;

	function setUp(
		address _vst,
		address _vstOperator,
		address _priceFeed,
		address _safetyVault,
		string memory _moduleName,
		string memory _moduleSymbol,
		uint8 _defaultRisk
	) external initializer {
		__INIT_ADAPTOR(_moduleName, _moduleSymbol, _vst);

		vst = IERC20(_vst);
		vstOperator = IVSTOperator(_vstOperator);
		oracle = IPriceFeed(_priceFeed);
		risk = _defaultRisk;
		safetyVault = _safetyVault;
		lastUpdate = block.timestamp;
	}

	function increaseDebt(uint256 _debt)
		external
		returns (uint256 addedInterest_)
	{
		updateEIR();
		uint256 newShare = PRECISION;
		addedInterest_ = _distributeInterestRate(msg.sender);

		balances[msg.sender] += _debt;

		if (total > 0) {
			newShare = (total * (_debt + addedInterest_)) / totalDebt;
		}

		mint(msg.sender, newShare);
		totalDebt += _debt;

		return addedInterest_;
	}

	function decreaseDebt(uint256 _debt)
		external
		returns (uint256 addedInterest_)
	{
		updateEIR();
		addedInterest_ = _distributeInterestRate(msg.sender);

		uint256 newShare = 0;
		uint256 balanceTotal = balances[msg.sender];

		if (_debt > balanceTotal) _debt = balanceTotal;

		balanceTotal = balances[msg.sender] -= _debt;

		if (total > 0 && balanceTotal > 0) {
			newShare = (total * balanceTotal) / totalDebt;
		}
		burn(msg.sender, balanceOf(msg.sender));
		mint(msg.sender, newShare);

		totalDebt -= _debt;
		return addedInterest_;
	}

	function updateEIR() public {
		uint256 newEIR = getEIR(risk, oracle.fetchPrice(address(vst)));
		uint256 oldEIR = currentEIR;

		uint256 lastDebt = totalDebt;
		uint256 minuteDifference = (block.timestamp - lastUpdate) / 1 minutes;
		currentEIR = newEIR;

		if (minuteDifference == 0) return;

		lastUpdate = block.timestamp;

		totalDebt += compound(
			oldEIR,
			totalDebt,
			minuteDifference * YEAR_MINUTE
		);

		vstOperator.mint(address(this), totalDebt - lastDebt);
	}

	function _distributeInterestRate(address _user)
		internal
		returns (uint256 emittedFee_)
	{
		if (total > 0) share = Math.add(share, Math.rdiv(crop(), total));

		uint256 last = crops[_user];
		uint256 curr = Math.rmul(stake[_user], share);
		if (curr > last) {
			emittedFee_ = curr - last;
			balances[_user] += emittedFee_;
			vst.transfer(safetyVault, emittedFee_);
		}
		stock = bonus.balanceOf(address(this));

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
		public
		view
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
		uint256 crop = Math.sub(
			vst.balanceOf(address(this)) + incomingMinting,
			stock
		);
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
}

