// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.17;

import "./lib/FullMath.sol";
import "./CropJoinAdapter.sol";
import "./interface/IVSTOperator.sol";
import "./interface/IERC20.sol";

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
	mapping(address => uint256) public emitedRate;

	IERC20 public vst;
	IVSTOperator public vstOperator;
	address public vestaSafe;

	function setUp(
		address _vst,
		address _vstOperator,
		string memory _moduleName,
		string memory _moduleSymbol
	) external initializer {
		__INIT_ADAPTOR(_moduleName, _moduleSymbol, _vst);

		vst = IERC20(_vst);
		vstOperator = IVSTOperator(_vstOperator);
	}

	function increaseDebt(uint256 _debt) external {
		this.updateEIR(currentEIR);
		balances[msg.sender] += _debt;
		uint256 newShare = PRECISION;

		if (total > 0) {
			newShare = (total * _debt) / totalDebt;
		}

		mint(msg.sender, newShare);
		totalDebt += _debt;
	}

	function decreaseDebt(uint256 _debt) external {
		this.updateEIR(currentEIR);

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
	}

	function updateEIR(uint256 _eir) external {
		if (_eir == 0) return;

		uint256 lastDebt = totalDebt;
		uint256 minuteDifference = (block.timestamp - lastUpdate) / 1 minutes;

		if (minuteDifference == 0 && currentEIR != _eir) {
			lastUpdate = block.timestamp;
			currentEIR = _eir;
			return;
		}

		totalDebt += _compound(
			currentEIR,
			totalDebt,
			minuteDifference * YEAR_MINUTE
		);

		lastUpdate = block.timestamp;
		currentEIR = _eir;

		vstOperator.mint(address(this), totalDebt - lastDebt);
	}

	function harvest(address from, address to) internal override {
		if (total > 0) share = Math.add(share, Math.rdiv(crop(), total));

		uint256 last = crops[from];
		uint256 curr = Math.rmul(stake[from], share);
		if (curr > last) {
			vst.transfer(vestaSafe, curr - last);
		}
		stock = bonus.balanceOf(address(this));
	}

	function _compound(
		uint256 _eir,
		uint256 _debt,
		uint256 _timeInYear
	) internal pure returns (uint256) {
		return
			FullMath.mulDiv(
				_debt,
				COMPOUND.pow((_eir * 100) * _timeInYear),
				1e18
			);
	}

	function getUnclaimedEIR(address user) public returns (uint256) {
		this.updateEIR(currentEIR);

		if (total == 0) return 0;

		// duplicate harvest logic
		uint256 crop = Math.sub(vst.balanceOf(address(this)), stock);
		uint256 share = Math.add(share, Math.rdiv(crop, total));

		uint256 last = this.crops(user);
		uint256 curr = Math.rmul(this.stake(user), share);
		if (curr > last) return curr - last;
		return 0;
	}

	function getEIR(uint8 _risk, uint256 _price)
		external
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

