pragma solidity ^0.8.17;

import "./lib/FullMath.sol";
import "./VST.sol";
import "./CropJoinAdapter.sol";
import "./interface/IPriceFeedV2.sol";

import "prb-math/PRBMathSD59x18.sol";
import "prb-math/PRBMathUD60x18.sol";

contract EIR {
	using PRBMathSD59x18 for int256;
	using PRBMathUD60x18 for uint256;

	error OnlyModule();

	struct ModuleData {
		uint256 totalDebt;
		uint232 lastUpdate;
		uint16 eir;
		uint8 risk;
	}

	uint256 public constant PRECISION = 1e18;
	uint256 private YEAR_MINUTE = 1.901285e6;
	uint256 private constant COMPOUND = 2.71828e18;
	uint256 private constant MINUTE = 1 minutes;

	mapping(address => ModuleData) private modules;
	mapping(address => bool) private activeModules;

	VST public vst;
	IPriceFeedV2 public oracle;

	modifier onlyModule() {
		if (!activeModules[msg.sender]) revert OnlyModule();
		_;
	}

	constructor(address _vst, address _oracle) {
		vst = VST(_vst);
		oracle = IPriceFeedV2(_oracle);
	}

	function updateEIR() external onlyModule {
		ModuleData storage module = modules[msg.sender];

		uint16 oldEIR = module.eir;
		uint256 currentDebt = module.totalDebt;
		uint256 lastDebt = currentDebt;
		uint256 minuteDifference = (block.timestamp - module.lastUpdate) /
			MINUTE;

		module.eir = _updateEIR(module.risk);
		module.lastUpdate = uint232(block.timestamp);

		if (minuteDifference == 0) return;

		currentDebt += _compound(
			oldEIR,
			currentDebt,
			minuteDifference * YEAR_MINUTE
		);

		module.totalDebt = currentDebt;
		vst.mint(msg.sender, currentDebt - lastDebt);
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
			) - _debt;
	}

	function _updateEIR(uint8 _risk) internal returns (uint16) {
		uint256 price = oracle.fetchPrice(address(vst));

		if (price < 0.95e18) {
			price = 0.95e18;
		} else if (price > 1.05e18) {
			price = 1.05e18;
		}

		int256 P = ((int256(price) - 1 ether)) / 1e2;

		uint256 a;

		if (_risk == 0) {
			a = 0.5e4;
		} else if (_risk == 1) {
			a = 0.75e4;
		} else {
			a = 1.25e4;
		}

		int256 exp = (-1.0397e4 * P);
		return uint16(FullMath.mulDivRoundingUp(a, uint256(exp.exp()), 1e20)); // Scale to BPS
	}
}

