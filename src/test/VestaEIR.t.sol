// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.4;

import "./base/BaseTest.t.sol";
import { VestaEIR } from "../main/VestaEIR.sol";
import { IPriceFeed } from "../main/interface/IPriceFeed.sol";
import { MockERC20 } from "./mock/MockERC20.sol";

contract VestaEIRTest is BaseTest {
	using stdJson for string;

	struct JsonSimulation {
		uint256[] users;
		Sequence[] sequences;
	}

	struct Sequence {
		uint256 vstPrice;
		uint256 minutePassed;
		uint256[] callers;
		uint256[] deposits;
		uint256[] withdrawals;
		uint256[] expectedInterestByUsers;
		uint256 expectedEIR;
	}

	string private constant KEY_USERS = ".users";
	string private constant KEY_SEQUENCES = ".sequences";
	string private constant KEY_SEQUENCES_COUNT = ".sequencesCount";
	string private constant KEY_VST_PRICE = ".vstPrice";
	string private constant KEY_MINUTE_PASSED = ".minutePassed";
	string private constant KEY_CALLERS = ".callers";
	string private constant KEY_DEPOSITS = ".deposits";
	string private constant KEY_WITHDRAWALS = ".withdrawals";
	string private constant KEY_EXPECTED_INTEREST_BY_USERS =
		".expectedInterestByUsers";
	string private constant KEY_EXPECTED_EIR = ".expectedEIR";

	uint256 private constant YEAR_MINUTE = 1.901285e6;
	uint256 private constant TOLERANCE = 3; //0.003%

	address private userA = generateAddress("userA", false);
	address private userB = generateAddress("userB", false);
	address private userC = generateAddress("userC", false);
	address private mockSafetyVault = generateAddress("Safety Vault", true);
	address private mockPriceFeed = generateAddress("Price Feed", true);
	address private mockVST;
	address private mockVSTOperator;

	VestaEIR private underTest;

	function setUp() public {
		vm.warp(1666996415);

		mockVST = address(new MockERC20("VST", "VST", 18));
		mockVSTOperator = address(new VSTOperatorMock(mockVST));

		underTest = new VestaEIR();

		underTest.setUp(
			mockVST,
			mockVSTOperator,
			mockPriceFeed,
			mockSafetyVault,
			"Vesta EIR Test Module",
			"vETM",
			0
		);
	}

	function test_getEIR_thenIsValid() external {
		assertEq(underTest.getEIR(0, 0.95e18), 9051);
		assertEq(underTest.getEIR(0, 0.98e18), 400);
		assertEq(underTest.getEIR(0, 1e18), 50);

		assertEq(underTest.getEIR(1, 0.98e18), 600);
		assertEq(underTest.getEIR(1, 1e18), 75);

		assertEq(underTest.getEIR(2, 0.98e18), 1000);
		assertEq(underTest.getEIR(2, 1e18), 125);
		assertEq(underTest.getEIR(2, 1.03e18), 6);
		assertEq(underTest.getEIR(2, 1.05e18), 1);
	}

	function test_getUserInterest_givenSpecificNumber_thenEqualsNumbers()
		external
	{
		uint256 timePassedRaw = 30240;
		uint256 debtOne = 308.279e18;
		uint256 debtTwo = 26877.3e18;

		_mockVSTPrice(1e18);

		vm.prank(userA);
		underTest.increaseDebt(debtOne);

		vm.prank(userB);
		underTest.increaseDebt(debtTwo);

		skip(timePassedRaw * 1 minutes);

		assertEq(
			underTest.getNotEmittedInterestRate(userA),
			88634967169682938
		);
		assertEq(
			underTest.getNotEmittedInterestRate(userB),
			7727638285805128626
		);
	}

	function test_getUserInterest_thenReturnsAccurateAmount()
		external
		prankAs(userA)
	{
		uint256 timePassedRaw = 52858980;
		uint256 yearlyTime = _minuteToYear(timePassedRaw);
		uint256 debt = 100e18;
		uint256 rate = 400;

		_mockVSTPrice(0.98e18);
		underTest.increaseDebt(debt);

		skip(timePassedRaw * 1 minutes);

		assertEq(
			underTest.getNotEmittedInterestRate(userA),
			underTest.compound(rate, debt, yearlyTime)
		);
	}

	function test_getUserInterest_decimals_thenReturnsAccurateAmount()
		external
		prankAs(userA)
	{
		uint256 timePassedRaw = 52858980;
		uint256 yearlyTime = _minuteToYear(timePassedRaw);
		uint256 debt = 100.23e18;
		uint256 rate = 400;

		_mockVSTPrice(0.98e18);
		underTest.increaseDebt(debt);

		skip(timePassedRaw * 1 minutes);

		assertEq(
			underTest.getNotEmittedInterestRate(userA),
			underTest.compound(rate, debt, yearlyTime)
		);
	}

	function test_EIR_singleTime() external prankAs(userA) {
		uint256 rawMinuteA = 788940;
		uint256 rawMinuteB = 262980;
		uint256 rawMinuteC = 522111;

		uint256 userA_timePassed = _minuteToYear(rawMinuteA);
		uint256 userB_timePassed = _minuteToYear(rawMinuteB);
		uint256 userC_timePassed = _minuteToYear(rawMinuteC);
		uint256 total_timePassed = userA_timePassed +
			userB_timePassed +
			userC_timePassed;

		uint256 userA_debt = 1902821.29e18;
		uint256 userB_debt = 302.99e18;
		uint256 userC_debt = 3212.19e18;
		uint256 rate = 400;
		_mockVSTPrice(0.98e18);

		changePrank(userA);
		underTest.increaseDebt(userA_debt);

		skip(rawMinuteA * 1 minutes);

		changePrank(userB);
		underTest.increaseDebt(userB_debt);

		skip(rawMinuteB * 1 minutes);

		changePrank(userC);
		underTest.increaseDebt(userC_debt);

		skip(rawMinuteC * 1 minutes);

		assertEqTolerance(
			underTest.getNotEmittedInterestRate(userA),
			underTest.compound(rate, userA_debt, total_timePassed),
			TOLERANCE
		);

		assertEqTolerance(
			underTest.getNotEmittedInterestRate(userB),
			underTest.compound(
				rate,
				userB_debt,
				userB_timePassed + userC_timePassed
			),
			TOLERANCE
		);
		assertEqTolerance(
			underTest.getNotEmittedInterestRate(userC),
			underTest.compound(rate, userC_debt, userC_timePassed),
			TOLERANCE
		);
	}

	function test_json_simulation_01() external prankAs(userA) {
		JsonSimulation memory simulation = _loadSimulation(
			"/src/test/data/simulation_01.json"
		);
		Sequence memory sequence;
		uint256 length = simulation.sequences.length;
		uint256 usersLength = simulation.users.length;
		uint256[] memory balances = new uint256[](usersLength + 1);

		for (uint256 i = 0; i < length; ++i) {
			sequence = simulation.sequences[i];

			skip(sequence.minutePassed * 1 minutes);
			_mockVSTPrice(sequence.vstPrice);

			uint256 callersLength = sequence.callers.length;
			for (uint256 x = 0; x < callersLength; ++x) {
				uint256 amount = 0;
				uint256 callerId = sequence.callers[x];
				address caller = vm.addr(callerId);

				changePrank(caller);
				if (sequence.deposits[x] != 0) {
					amount = sequence.deposits[x];

					underTest.increaseDebt(amount);
					balances[callerId] += amount;
				} else if (sequence.withdrawals[x] != 0) {
					amount = sequence.withdrawals[x];

					balances[callerId] += underTest.getNotEmittedInterestRate(
						caller
					);
					underTest.decreaseDebt(amount);
					balances[callerId] -= amount;
				}

				assertEq(underTest.balances(caller), balances[callerId]);
			}

			for (uint256 u = 0; u < usersLength; ++u) {
				address user = vm.addr(simulation.users[u]);
				assertEq(
					underTest.getNotEmittedInterestRate(user),
					sequence.expectedInterestByUsers[u]
				);
			}

			assertEq(underTest.currentEIR(), sequence.expectedEIR);
		}
	}

	function _mockVSTPrice(uint256 _price) internal {
		vm.mockCall(
			mockPriceFeed,
			abi.encodeWithSelector(IPriceFeed.fetchPrice.selector, mockVST),
			abi.encode(_price)
		);

		vm.mockCall(
			mockPriceFeed,
			abi.encodeWithSelector(
				IPriceFeed.getExternalPrice.selector,
				mockVST
			),
			abi.encode(_price)
		);

		underTest.updateEIR();
	}

	function _loadSimulation(string memory _jsonPath)
		internal
		view
		returns (JsonSimulation memory jsonSimulation_)
	{
		string memory root = vm.projectRoot();
		string memory path = string.concat(root, _jsonPath);
		string memory json = vm.readFile(path);

		uint256 totalSequence = json.readUint(KEY_SEQUENCES_COUNT);

		jsonSimulation_.users = json.readUintArray(KEY_USERS);
		jsonSimulation_.sequences = new Sequence[](totalSequence);

		string memory key;

		for (uint256 i = 0; i < totalSequence; ++i) {
			key = string.concat(KEY_SEQUENCES, ".[");
			key = string.concat(key, uint2str(i));
			key = string.concat(key, "]");

			Sequence memory sequence = Sequence({
				vstPrice: json.readUint(string.concat(key, KEY_VST_PRICE)),
				minutePassed: json.readUint(string.concat(key, KEY_MINUTE_PASSED)),
				callers: json.readUintArray(string.concat(key, KEY_CALLERS)),
				deposits: _stringArrayToUintArray(
					json.readStringArray(string.concat(key, KEY_DEPOSITS))
				),
				withdrawals: _stringArrayToUintArray(
					json.readStringArray(string.concat(key, KEY_WITHDRAWALS))
				),
				expectedInterestByUsers: _stringArrayToUintArray(
					json.readStringArray(
						string.concat(key, KEY_EXPECTED_INTEREST_BY_USERS)
					)
				),
				expectedEIR: json.readUint(string.concat(key, KEY_EXPECTED_EIR))
			});

			jsonSimulation_.sequences[i] = sequence;
		}

		return jsonSimulation_;
	}

	function _stringArrayToUintArray(string[] memory _stringArray)
		internal
		pure
		returns (uint256[] memory array_)
	{
		uint256 length = _stringArray.length;
		array_ = new uint256[](length);

		for (uint256 i = 0; i < length; ++i) {
			array_[i] = _st2num(_stringArray[i]);
		}

		return array_;
	}

	function _minuteToYear(uint256 minutePassed)
		internal
		pure
		returns (uint256)
	{
		return minutePassed * YEAR_MINUTE;
	}

	function _st2num(string memory numString)
		internal
		pure
		returns (uint256)
	{
		uint256 val = 0;
		bytes memory stringBytes = bytes(numString);
		for (uint256 i = 0; i < stringBytes.length; i++) {
			uint256 exp = stringBytes.length - i;
			bytes1 ival = stringBytes[i];
			uint8 uval = uint8(ival);
			uint256 jval = uval - uint256(0x30);

			val += (uint256(jval) * (10**(exp - 1)));
		}
		return val;
	}

	function uint2str(uint256 _i)
		internal
		pure
		returns (string memory _uintAsString)
	{
		if (_i == 0) {
			return "0";
		}
		uint256 j = _i;
		uint256 len;
		while (j != 0) {
			len++;
			j /= 10;
		}
		bytes memory bstr = new bytes(len);
		uint256 k = len;
		while (_i != 0) {
			k = k - 1;
			uint8 temp = (48 + uint8(_i - (_i / 10) * 10));
			bytes1 b1 = bytes1(temp);
			bstr[k] = b1;
			_i /= 10;
		}
		return string(bstr);
	}
}

contract VSTOperatorMock {
	MockERC20 private mockVST;

	constructor(address _vst) {
		mockVST = MockERC20(_vst);
	}

	function mint(address _to, uint256 _amount) external {
		mockVST.mint(_to, _amount);
	}
}
