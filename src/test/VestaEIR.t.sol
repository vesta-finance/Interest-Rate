// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.4;

import "./base/BaseTest.t.sol";
import { VestaEIR } from "../main/VestaEIR.sol";
import { IInterestManager } from "../main/interface/IInterestManager.sol";
import { IVSTOperator } from "../main/interface/IVSTOperator.sol";
import { MockERC20 } from "./mock/MockERC20.sol";

contract VestaEIRTest is BaseTest {
	using stdJson for string;

	event InterestMinted(uint256 interest);
	event DebtChanged(address user, uint256 debt);
	event SystemDebtChanged(uint256 debt);
	event RiskChanged(uint8 risk);

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

	bytes private constant REVERT_NOT_INTERET_MANAGER =
		abi.encodeWithSignature("NotInterestManager()");
	bytes private constant REVERT_CANNOT_BE_ZERO =
		abi.encodeWithSignature("CannotBeZero()");
	bytes private constant REVERT_NO_DEBT_FOUND =
		abi.encodeWithSignature("NoDebtFound()");

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

	address private owner = generateAddress("Owner", false);
	address private userA = generateAddress("userA", false);
	address private userB = generateAddress("userB", false);
	address private userC = generateAddress("userC", false);
	address private mockSafetyVault = generateAddress("Safety Vault", true);
	address private mockInterestManager =
		generateAddress("Interest Manager", true);
	address private mockVST;
	address private mockVSTOperator;

	VestaEIR private underTest;

	function setUp() public {
		vm.warp(1666996415);

		mockVST = address(new MockERC20("VST", "VST", 18));
		mockVSTOperator = address(new VSTOperatorMock(mockVST));

		vm.mockCall(
			mockInterestManager,
			abi.encodeWithSelector(IInterestManager.getLastVstPrice.selector),
			abi.encode(1e18)
		);

		underTest = new VestaEIR();

		vm.prank(owner);
		underTest.setUp(
			mockVST,
			mockVSTOperator,
			mockSafetyVault,
			mockInterestManager,
			"Vesta EIR Test Module",
			"vETM",
			0
		);
	}

	function test_setup_thenCallerIsOwner() external prankAs(owner) {
		underTest = new VestaEIR();
		underTest.setUp(
			mockVST,
			mockVSTOperator,
			mockSafetyVault,
			mockInterestManager,
			"Vesta EIR Test Module",
			"vETM",
			0
		);

		assertEq(underTest.owner(), owner);
	}

	function test_setup_whenAlreadyInitialized_thenReverts() external {
		underTest = new VestaEIR();
		underTest.setUp(
			mockVST,
			mockVSTOperator,
			mockSafetyVault,
			mockInterestManager,
			"Vesta EIR Test Module",
			"vETM",
			0
		);

		vm.expectRevert(REVERT_ALREADY_INITIALIZED);
		underTest.setUp(
			mockVST,
			mockVSTOperator,
			mockSafetyVault,
			mockInterestManager,
			"Vesta EIR Test Module",
			"vETM",
			0
		);
	}

	function test_setup_thenContractCorrectlyConfigured()
		external
		prankAs(owner)
	{
		underTest = new VestaEIR();

		underTest.setUp(
			mockVST,
			mockVSTOperator,
			mockSafetyVault,
			mockInterestManager,
			"Vesta EIR Test Module",
			"vETM",
			1
		);

		assertEq(address(underTest.vst()), mockVST);
		assertEq(address(underTest.vstOperator()), mockVSTOperator);
		assertEq(underTest.safetyVault(), mockSafetyVault);
		assertEq(underTest.interestManager(), mockInterestManager);
		assertEq(underTest.lastUpdate(), block.timestamp);
		assertEq(underTest.risk(), 1);
		assertEq(underTest.currentEIR(), 75);
	}

	function test_setup_thenAbstractContractsConfigured()
		external
		prankAs(owner)
	{
		underTest = new VestaEIR();
		underTest.setUp(
			mockVST,
			mockVSTOperator,
			mockSafetyVault,
			mockInterestManager,
			"Vesta EIR Test Module",
			"vETM",
			1
		);

		assertEq(underTest.name(), "Vesta EIR Test Module");
		assertEq(underTest.symbol(), "vETM");
		assertTrue(address(underTest.vat()) != address(0));
		assertEq(underTest.ilk(), bytes32("VESTA.EIR"));
		assertTrue(address(underTest.gem()) != address(0));
	}

	function test_setRisk_asUser_thenReverts() external prankAs(userA) {
		vm.expectRevert(NOT_OWNER);
		underTest.setRisk(0);
	}

	function test_setRisk_asOwner_thenUpdateSystemAndEmitsRiskChanged()
		external
		prankAs(owner)
	{
		vm.expectEmit(true, true, true, true);
		emit RiskChanged(2);
		underTest.setRisk(2);

		assertEq(underTest.risk(), 2);
	}

	function test_setSafetyVault_asUser_thenReverts()
		external
		prankAs(userA)
	{
		vm.expectRevert(NOT_OWNER);
		underTest.setSafetyVault(address(this));
	}

	function test_setSafetyVault_asOwner_thenUpdatesSystem()
		external
		prankAs(owner)
	{
		underTest.setSafetyVault(address(this));
		assertEq(underTest.safetyVault(), address(this));
	}

	function test_increaseDebt_asUser_thenReverts() external prankAs(userA) {
		vm.expectRevert(REVERT_NOT_INTERET_MANAGER);
		underTest.increaseDebt(userA, 1e18);
	}

	function test_increaseDebt_asInterestManager_thenCallUpdateEIR()
		external
		prankAs(mockInterestManager)
	{
		_skipAndUpdateInterest(0, 0.95e18);
		underTest.increaseDebt(userA, 1e18);

		assertEq(underTest.currentEIR(), 9051);
	}

	function test_increaseDebt_asInterestManager_givenUserA_whenSystemEmpty_thenUpdateSystemAndEmitUserAndSystemDebtChanged()
		external
		prankAs(mockInterestManager)
	{
		uint256 debt = 992.18e18;
		uint256 expectedShare = 1e18;

		vm.expectEmit(true, true, true, true);
		emit DebtChanged(userA, debt);

		vm.expectEmit(true, true, true, true);
		emit SystemDebtChanged(debt);

		uint256 emittedInterest = underTest.increaseDebt(userA, debt);

		assertEq(underTest.stake(userA), expectedShare);
		assertEq(underTest.getDebtOf(userA), debt);
		assertEq(underTest.balanceOf(userA), expectedShare);
		assertEq(underTest.totalDebt(), debt);
		assertEq(emittedInterest, 0);
	}

	function test_increaseDebt_asInterestManager_givenUserB_whenSystemIsNotEmpty_thenGivesCorrectShare()
		external
		prankAs(mockInterestManager)
	{
		uint256 debtUserA = 9823.1e18;
		uint256 debtUserB = 772e18;

		underTest.increaseDebt(userA, debtUserA);
		underTest.increaseDebt(userB, debtUserB);

		uint256 expectShareA = 1e18;
		uint256 expectShareB = ((expectShareA * debtUserB) / debtUserA);

		assertEq(underTest.total(), expectShareA + expectShareB);
		assertEq(underTest.stake(userB), expectShareB);
	}

	function test_increaseDebt_asInterestManager_givenUserA_whenNotFirstTimeTimeAndTimePassed_thenApplyInterestRate()
		external
		prankAs(mockInterestManager)
	{
		uint256 debt = 764.23e18;
		underTest.increaseDebt(userA, debt);

		_skipAndUpdateInterest(1 hours, 1e18);

		uint256 interestRateAdded = underTest.increaseDebt(userA, 1e18);

		assertTrue(interestRateAdded != 0);
	}

	function test_decreaseDebt_asUser_thenReverts() external prankAs(userA) {
		vm.expectRevert(REVERT_NOT_INTERET_MANAGER);
		underTest.decreaseDebt(userA, 1e18);
	}

	function test_decreaseDebt_asInterestManager_givenZeroDebt_thenReverts()
		external
		prankAs(mockInterestManager)
	{
		vm.expectRevert(REVERT_CANNOT_BE_ZERO);
		underTest.decreaseDebt(userA, 0);
	}

	function test_decreaseDebt_asInterestManager_givenUserWithNoDebt_thenReverts()
		external
		prankAs(mockInterestManager)
	{
		vm.expectRevert(stdError.arithmeticError);
		underTest.decreaseDebt(userA, 1e18);
	}

	function test_decreaseDebt_asInterestManager_givenUserAWithDebt_thenDistributeAndUpdateShareAndEmitsUserAndSystemDebtsChanged()
		external
		prankAs(mockInterestManager)
	{
		uint256 debtA = 764.23e18;
		uint256 withdrawalA = 100.23e18;
		uint256 debtB = 76.23e18;
		uint256 expectedInterest = 435905541768641;
		uint256 totalExpectedInterest = 479386011586659;

		underTest.increaseDebt(userA, debtA);
		underTest.increaseDebt(userB, debtB);

		_skipAndUpdateInterest(1 hours, 1e18);

		uint256 pendingEIRUserA = underTest.getNotEmittedInterestRate(userA);
		uint256 totalDebt = underTest.totalDebt();
		uint256 total = underTest.total();

		vm.expectEmit(true, true, true, true);
		emit DebtChanged(userA, (debtA + expectedInterest) - withdrawalA);

		vm.expectEmit(true, true, true, true);
		emit SystemDebtChanged(
			(debtA + debtB + totalExpectedInterest) - withdrawalA
		);

		uint256 interestRateAdded = underTest.decreaseDebt(userA, withdrawalA);

		assertEq(
			underTest.stake(userA),
			(total * ((debtA + pendingEIRUserA) - withdrawalA)) / totalDebt
		);
		assertEq(interestRateAdded, expectedInterest);
	}

	function test_exit_asUser_thenReverts() external prankAs(userA) {
		vm.expectRevert(REVERT_NOT_INTERET_MANAGER);
		underTest.exit(userA);
	}

	function test_exit_asInterestManager_givenNonExistantUser_thenReverts()
		external
		prankAs(mockInterestManager)
	{
		vm.expectRevert(REVERT_NO_DEBT_FOUND);
		underTest.exit(userA);
	}

	function test_exit_asInterestManager_givenDebtUser_thenExitsAndReturnsAddedInterestRate()
		external
		prankAs(mockInterestManager)
	{
		uint256 debtA = 764.23e18;
		underTest.increaseDebt(userA, debtA);

		_skipAndUpdateInterest(63 days, 0.98e18);

		uint256 addedInterestRate = underTest.exit(userA);

		assertEq(addedInterestRate, 659373279427298707);
		assertEq(underTest.getDebtOf(userA), 0);
		assertEq(underTest.stake(userA), 0);
	}

	function test_updateEIR_asUser_thenReverts() external prankAs(userA) {
		vm.expectRevert(REVERT_NOT_INTERET_MANAGER);
		underTest.updateEIR(0);
	}

	function test_updateEIR_asInterestManager_whenNotMinutePassed_thenUpdateEIR()
		external
		prankAs(mockInterestManager)
	{
		uint256 price = 0.92e18;
		uint256 expectedEIR = underTest.getEIR(0, price);
		uint256 oldEIR = underTest.currentEIR();
		uint256 lastUpdate = underTest.lastUpdate();

		skip(59 seconds);
		underTest.updateEIR(price);

		assertTrue(oldEIR != expectedEIR);
		assertEq(underTest.currentEIR(), expectedEIR);
		assertEq(underTest.lastUpdate(), lastUpdate);
	}

	function test_updateEIR_asInterestManager_whenMinutePassed_thenUpdateSystemAndEmitsInterestMinted()
		external
		prankAs(mockInterestManager)
	{
		underTest.increaseDebt(userA, 300e18);

		uint256 price = 0.92e18;
		uint256 lastUpdate = underTest.lastUpdate();
		uint256 expectedMintedInterest = 2851925595000;

		skip(1 minutes);

		vm.expectEmit(true, true, true, true);
		emit InterestMinted(expectedMintedInterest);

		vm.expectCall(
			mockVSTOperator,
			abi.encodeWithSelector(
				IVSTOperator.mint.selector,
				mockSafetyVault,
				expectedMintedInterest
			)
		);

		underTest.updateEIR(price);

		assertEq(underTest.lastUpdate(), lastUpdate + 1 minutes);
		assertEq(underTest.totalDebt(), 300e18 + expectedMintedInterest);
	}

	function test_getNotEmmitedInterestRate_whenSystemIsZero_thenReturnsZero()
		external
	{
		assertEq(underTest.getNotEmittedInterestRate(userA), 0);
	}

	function test_getNotEmmitedInterestRate_whenUserHasZeroDebt_thenReturnsZero()
		external
	{
		vm.prank(mockInterestManager);
		underTest.increaseDebt(userA, 1000e18);

		skip(6 hours);

		assertEq(underTest.getNotEmittedInterestRate(userB), 0);
	}

	function test_getNotEmmitedInterestRate_whenUserHasDebtButNoMinutePassedSinceLastUpdate_thenReturnsZero()
		external
	{
		vm.prank(mockInterestManager);
		underTest.increaseDebt(userA, 1000e18);

		skip(59 seconds);

		assertEq(underTest.getNotEmittedInterestRate(userA), 0);
	}

	function test_getNotEmmitedInterestRate_whenUserHasDebtAndMinutesPassedSinceLastUpdate_thenReturnsInterestRate()
		external
	{
		uint256 expectedInterest = 1711156813013000;

		vm.prank(mockInterestManager);
		underTest.increaseDebt(userA, 1000e18);

		skip(3 hours);

		assertEq(underTest.getNotEmittedInterestRate(userA), expectedInterest);
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

	function test_getEIR_whenLowerOrHigherThanLimit_thenReturnsMinMaxValue()
		external
	{
		assertEq(underTest.getEIR(0, 0.8e18), 9051);
		assertEq(underTest.getEIR(0, 2e18), 1);
	}

	function test_getDebtOf_thenReturnsSameDebt() external {
		uint256 debt = 3023.2e18;

		vm.prank(mockInterestManager);
		underTest.increaseDebt(userA, debt);

		assertEq(underTest.getDebtOf(userA), debt);
		assertEq(underTest.getDebtOf(userB), 0);
	}

	function test_getUserInterest_givenSpecificNumber_thenEqualsNumbers()
		external
		prankAs(mockInterestManager)
	{
		uint256 timePassedRaw = 30240;
		uint256 debtOne = 308.279e18;
		uint256 debtTwo = 26877.3e18;

		underTest.increaseDebt(userA, debtOne);
		underTest.increaseDebt(userB, debtTwo);

		_skipAndUpdateInterest(timePassedRaw * 1 minutes, 1e18);

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
		prankAs(mockInterestManager)
	{
		uint256 timePassedRaw = 52858980;
		uint256 yearlyTime = _minuteToYear(timePassedRaw);
		uint256 debt = 100e18;
		uint256 rate = 400;

		_skipAndUpdateInterest(0, 0.98e18);
		underTest.increaseDebt(userA, debt);
		_skipAndUpdateInterest(timePassedRaw * 1 minutes, 0.98e18);

		assertEq(
			underTest.getNotEmittedInterestRate(userA),
			underTest.compound(rate, debt, yearlyTime)
		);
	}

	function test_getUserInterest_decimals_thenReturnsAccurateAmount()
		external
		prankAs(mockInterestManager)
	{
		uint256 timePassedRaw = 52858980;
		uint256 yearlyTime = _minuteToYear(timePassedRaw);
		uint256 debt = 100.23e18;
		uint256 rate = 400;

		_skipAndUpdateInterest(0, 0.98e18);
		underTest.increaseDebt(userA, debt);

		_skipAndUpdateInterest(timePassedRaw * 1 minutes, 0.98e18);

		assertEq(
			underTest.getNotEmittedInterestRate(userA),
			underTest.compound(rate, debt, yearlyTime)
		);
	}

	function test_EIR_singleTime() external prankAs(mockInterestManager) {
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

		_skipAndUpdateInterest(0, 0.98e18);

		underTest.increaseDebt(userA, userA_debt);

		_skipAndUpdateInterest(rawMinuteA * 1 minutes, 0.98e18);

		underTest.increaseDebt(userB, userB_debt);

		_skipAndUpdateInterest(rawMinuteB * 1 minutes, 0.98e18);

		underTest.increaseDebt(userC, userC_debt);

		_skipAndUpdateInterest(rawMinuteC * 1 minutes, 0.98e18);

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

	function test_json_simulation_01()
		external
		prankAs(mockInterestManager)
	{
		JsonSimulation memory simulation = _loadSimulation(
			"/src/test/data/simulation_01.json"
		);
		Sequence memory sequence;
		uint256 length = simulation.sequences.length;
		uint256 usersLength = simulation.users.length;
		uint256[] memory balances = new uint256[](usersLength + 1);

		for (uint256 i = 0; i < length; ++i) {
			sequence = simulation.sequences[i];

			_skipAndUpdateInterest(
				sequence.minutePassed * 1 minutes,
				sequence.vstPrice
			);

			uint256 callersLength = sequence.callers.length;
			for (uint256 x = 0; x < callersLength; ++x) {
				uint256 amount = 0;
				uint256 callerId = sequence.callers[x];
				address caller = vm.addr(callerId);

				if (sequence.deposits[x] != 0) {
					amount = sequence.deposits[x];

					underTest.increaseDebt(caller, amount);
					balances[callerId] += amount;
				} else if (sequence.withdrawals[x] != 0) {
					amount = sequence.withdrawals[x];

					balances[callerId] += underTest.getNotEmittedInterestRate(
						caller
					);
					underTest.decreaseDebt(caller, amount);
					balances[callerId] -= amount;
				}

				assertEq(underTest.getDebtOf(caller), balances[callerId]);
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

	function _skipAndUpdateInterest(uint256 _time, uint256 _vstPrice)
		internal
	{
		skip(_time);
		underTest.updateEIR(_vstPrice);
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
