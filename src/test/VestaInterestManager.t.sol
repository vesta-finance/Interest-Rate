pragma solidity ^0.8.17;

import "./base/BaseTest.t.sol";
import { VestaInterestManager } from "../main/VestaInterestManager.sol";

import { IInterestManager } from "../main/interface/IInterestManager.sol";
import { IModuleInterest } from "../main/interface/IModuleInterest.sol";
import { IVSTOperator } from "../main/interface/IVSTOperator.sol";
import { IPriceFeed } from "../main/interface/IPriceFeed.sol";

contract VestaInterestManagerTest is BaseTest {
	event ModuleLinked(address indexed token, address indexed module);

	event InterestMinted(address indexed module, uint256 interestMinted);
	event DebtChanged(
		address indexed module,
		address indexed user,
		uint256 newDebt
	);

	bytes private constant REVERT_ORACLE_FAILED =
		"Oracle Failed to fetch VST price.";

	bytes private constant REVERT_NOT_TROVE_MANAGER =
		abi.encodeWithSignature("NotTroveManager()");
	bytes private constant REVERT_MODULE_ALREADY_SET =
		abi.encodeWithSignature("ErrorModuleAlreadySet()");

	uint256 private constant DEFAULT_VST_PRICE = 0.98e18;

	address owner = generateAddress("Owner", false);
	address user = generateAddress("User", false);

	address mockTokenA = generateAddress("TokenA", true);
	address mockModuleA = generateAddress("Interest ModuleA", true);

	address mockTokenB = generateAddress("TokenB", true);
	address mockModuleB = generateAddress("Interest ModuleB", true);

	address mockVst = generateAddress("VST", true);
	address mockTroveManager = generateAddress("Trove Manager", true);
	address mockPriceFeed = generateAddress("PriceFeed", true);

	VestaInterestManager private underTest;

	function setUp() external {
		underTest = new VestaInterestManager();

		_mockVSTPrice(DEFAULT_VST_PRICE);

		vm.startPrank(owner);
		underTest.setUp(mockVst, mockTroveManager, mockPriceFeed);

		_mockUpdateEIRCall(mockModuleA, DEFAULT_VST_PRICE, 0);
		_mockUpdateEIRCall(mockModuleB, DEFAULT_VST_PRICE, 0);

		underTest.setModuleFor(mockTokenA, mockModuleA);
		underTest.setModuleFor(mockTokenB, mockModuleB);
		vm.stopPrank();

		vm.clearMockedCalls();
		_mockGetDebtOf(mockModuleA, user, 0);
		_mockGetDebtOf(mockModuleB, user, 0);
		_mockVSTPrice(DEFAULT_VST_PRICE);
	}

	function test_setUp_thenSetupCorrectlyContract()
		external
		prankAs(owner)
	{
		underTest = new VestaInterestManager();
		underTest.setUp(mockVst, mockTroveManager, mockPriceFeed);

		assertEq(underTest.owner(), owner);
		assertEq(underTest.vst(), mockVst);
		assertEq(underTest.troveManager(), mockTroveManager);
		assertEq(address(underTest.oracle()), mockPriceFeed);
		assertEq(underTest.getLastVstPrice(), DEFAULT_VST_PRICE);
	}

	function test_setUp_givenOracleFailling_thenReverts() external {
		underTest = new VestaInterestManager();

		vm.expectRevert(REVERT_ORACLE_FAILED);
		_mockVSTPrice(0);
		underTest.setUp(mockVst, mockTroveManager, mockPriceFeed);
	}

	function test_setUp_whenAlreadyInitialized_thenReverts() external {
		underTest = new VestaInterestManager();
		underTest.setUp(mockVst, mockTroveManager, mockPriceFeed);

		vm.expectRevert(REVERT_ALREADY_INITIALIZED);
		underTest.setUp(mockVst, mockTroveManager, mockPriceFeed);
	}

	function test_setModuleFor_asNoOwner_thenReverts() external {
		vm.expectRevert(NOT_OWNER);
		underTest.setModuleFor(mockTokenA, mockModuleA);
	}

	function test_setModuleFor_asOwner_thenLinkTokenModuleAndEmitModuleLinkedEvent()
		external
		prankAs(owner)
	{
		address token = generateAddress("Function Token", true);
		address module = generateAddress("Function Module", true);

		uint256 currentLength = underTest.getModules().length;

		_mockUpdateEIRCall(module, DEFAULT_VST_PRICE, 0);

		vm.expectEmit(true, true, true, true);
		emit ModuleLinked(token, module);

		underTest.setModuleFor(token, module);

		uint256 newLength = underTest.getModules().length;

		assertEq(underTest.getInterestModule(token), module);
		assertEq(newLength - currentLength, 1);
		assertEq(underTest.getModules()[newLength - 1], module);
	}

	function test_setModuleFor_asOwner_whenAlreadyLinked_thenReverts()
		external
		prankAs(owner)
	{
		address token = generateAddress("Function Token", true);
		address module = generateAddress("Function Module", true);

		_mockUpdateEIRCall(module, DEFAULT_VST_PRICE, 0);
		underTest.setModuleFor(token, module);

		vm.expectRevert(REVERT_MODULE_ALREADY_SET);
		underTest.setModuleFor(token, module);
	}

	function test_increaseDebt_asNotTroveManager_thenReverts() external {
		vm.expectRevert(REVERT_NOT_TROVE_MANAGER);
		underTest.increaseDebt(mockTokenA, user, 1e18);
	}

	function test_increaseDebt_asTroveManager_thenUpdateModulesAndCallTokenModule()
		external
		prankAs(mockTroveManager)
	{
		uint256 debt = 300e18;
		uint256 expectedInterest = 99e19;
		uint256 price = 1.99e18;
		_mockVSTPrice(price);
		_expectUpdateEIRCall(mockModuleA, price);
		_expectUpdateEIRCall(mockModuleB, price);

		vm.mockCall(
			mockModuleA,
			abi.encodeWithSelector(
				IModuleInterest.increaseDebt.selector,
				user,
				debt
			),
			abi.encode(expectedInterest)
		);

		uint256 interestAdded = underTest.increaseDebt(mockTokenA, user, debt);

		assertEq(interestAdded, expectedInterest);
	}

	function test_increaseDebt_asTroveManager_givenDifferentModule_thenCallCorrectModules()
		external
		prankAs(mockTroveManager)
	{
		uint256 debt = 300e18;
		uint256 price = 1.99e18;
		_mockVSTPrice(price);
		_expectUpdateEIRCall(mockModuleA, price);
		_expectUpdateEIRCall(mockModuleB, price);

		vm.mockCall(
			mockModuleA,
			abi.encodeWithSelector(
				IModuleInterest.increaseDebt.selector,
				user,
				debt
			),
			abi.encode(119e18)
		);

		assertEq(underTest.increaseDebt(mockTokenA, user, debt), 119e18);

		vm.mockCall(
			mockModuleB,
			abi.encodeWithSelector(
				IModuleInterest.increaseDebt.selector,
				user,
				debt
			),
			abi.encode(11e18)
		);

		assertEq(underTest.increaseDebt(mockTokenB, user, debt), 11e18);
	}

	function test_increaseDebt_asTroveManager_thenEmitsDebtChanged()
		external
		prankAs(mockTroveManager)
	{
		_mockGetDebtOf(mockModuleA, user, 300e18);
		_expectUpdateEIRCall(mockModuleA, DEFAULT_VST_PRICE);
		_expectUpdateEIRCall(mockModuleB, DEFAULT_VST_PRICE);

		vm.mockCall(
			mockModuleA,
			abi.encodeWithSelector(
				IModuleInterest.increaseDebt.selector,
				user,
				300e18
			),
			abi.encode(0)
		);

		vm.expectEmit(true, true, true, true);
		emit DebtChanged(mockTokenA, user, 300e18);

		underTest.increaseDebt(mockTokenA, user, 300e18);
	}

	function test_decreaseDebt_asNotTroveManager_thenReverts() external {
		vm.expectRevert(REVERT_NOT_TROVE_MANAGER);
		underTest.decreaseDebt(mockTokenA, user, 1e18);
	}

	function test_decreaseDebt_asTroveManager_thenUpdateModulesAndCallTokenModule()
		external
		prankAs(mockTroveManager)
	{
		uint256 debt = 300e18;
		uint256 expectedInterest = 99e19;
		uint256 price = 1.99e18;
		_mockVSTPrice(price);
		_expectUpdateEIRCall(mockModuleA, price);
		_expectUpdateEIRCall(mockModuleB, price);

		vm.mockCall(
			mockModuleB,
			abi.encodeWithSelector(
				IModuleInterest.decreaseDebt.selector,
				user,
				debt
			),
			abi.encode(expectedInterest)
		);

		uint256 interestAdded = underTest.decreaseDebt(mockTokenB, user, debt);

		assertEq(interestAdded, expectedInterest);
	}

	function test_decreaseDebt_asTroveManager_givenDifferentModule_thenCallCorrectModules()
		external
		prankAs(mockTroveManager)
	{
		uint256 debt = 300e18;
		uint256 price = 1.99e18;
		_mockVSTPrice(price);
		_expectUpdateEIRCall(mockModuleA, price);
		_expectUpdateEIRCall(mockModuleB, price);

		vm.mockCall(
			mockModuleA,
			abi.encodeWithSelector(
				IModuleInterest.decreaseDebt.selector,
				user,
				debt
			),
			abi.encode(199e18)
		);

		assertEq(underTest.decreaseDebt(mockTokenA, user, debt), 199e18);

		underTest.decreaseDebt(mockTokenA, user, debt);

		vm.mockCall(
			mockModuleB,
			abi.encodeWithSelector(
				IModuleInterest.decreaseDebt.selector,
				user,
				debt
			),
			abi.encode(13e18)
		);

		assertEq(underTest.decreaseDebt(mockTokenB, user, debt), 13e18);
	}

	function test_decreaseDebt_asTroveManager_thenEmitsDebtChanged()
		external
		prankAs(mockTroveManager)
	{
		_mockGetDebtOf(mockModuleA, user, 300e18);
		_expectUpdateEIRCall(mockModuleA, DEFAULT_VST_PRICE);
		_expectUpdateEIRCall(mockModuleB, DEFAULT_VST_PRICE);

		vm.mockCall(
			mockModuleA,
			abi.encodeWithSelector(
				IModuleInterest.decreaseDebt.selector,
				user,
				300e18
			),
			abi.encode(0)
		);

		vm.expectEmit(true, true, true, true);
		emit DebtChanged(mockTokenA, user, 300e18);

		underTest.decreaseDebt(mockTokenA, user, 300e18);
	}

	function test_updateModules_givenTimePassed_thenUpdatesAndEmitsInterestMintedEvent()
		external
		prankAs(mockTroveManager)
	{
		uint256 price = 1.99e18;

		uint256 expectedInterestA = 992.1e18;
		uint256 expectedInterestB = 232.1e18;

		_mockVSTPrice(price);
		_mockUpdateEIRCall(mockModuleA, price, expectedInterestA);
		_mockUpdateEIRCall(mockModuleB, price, expectedInterestB);

		vm.expectEmit(true, true, true, true);
		emit InterestMinted(mockModuleA, expectedInterestA);

		vm.expectEmit(true, true, true, true);
		emit InterestMinted(mockModuleB, expectedInterestB);

		underTest.updateModules();
	}

	function test_getUserDebt_givenTokenA_thenReturnsSameValues() external {
		uint256 expectedDebt = 9928.1e18;
		uint256 expectedInterest = 218.89e18;

		vm.mockCall(
			mockModuleA,
			abi.encodeWithSelector(IModuleInterest.getDebtOf.selector, user),
			abi.encode(expectedDebt)
		);
		vm.mockCall(
			mockModuleA,
			abi.encodeWithSelector(
				IModuleInterest.getNotEmittedInterestRate.selector,
				user
			),
			abi.encode(expectedInterest)
		);

		(uint256 returnedDebt, uint256 returnedNotEmittedInterest) = underTest
			.getUserDebt(mockTokenA, user);

		assertEq(returnedDebt, expectedDebt);
		assertEq(returnedNotEmittedInterest, expectedInterest);
	}

	function test_getUserDebt_givenTokenB_thenReturnsSameValues() external {
		uint256 expectedDebt = 9928.1e18;
		uint256 expectedInterest = 218.89e18;

		vm.mockCall(
			mockModuleB,
			abi.encodeWithSelector(IModuleInterest.getDebtOf.selector, user),
			abi.encode(expectedDebt)
		);
		vm.mockCall(
			mockModuleB,
			abi.encodeWithSelector(
				IModuleInterest.getNotEmittedInterestRate.selector,
				user
			),
			abi.encode(expectedInterest)
		);

		(uint256 returnedDebt, uint256 returnedNotEmittedInterest) = underTest
			.getUserDebt(mockTokenB, user);

		assertEq(returnedDebt, expectedDebt);
		assertEq(returnedNotEmittedInterest, expectedInterest);
	}

	function test_getInterestModule_thenReturnsModules() external {
		assertEq(underTest.getInterestModule(mockTokenA), mockModuleA);
		assertEq(underTest.getInterestModule(mockTokenB), mockModuleB);
	}

	function test_getModules_thenReturnsModules() external {
		address[] memory modules = underTest.getModules();

		assertEq(modules[0], mockModuleA);
		assertEq(modules[1], mockModuleB);
	}

	function test_getLastVstPrice_thenReturnsVSTPrice() external {
		assertEq(underTest.getLastVstPrice(), DEFAULT_VST_PRICE);
	}

	function _mockVSTPrice(uint256 _price) internal {
		vm.mockCall(
			mockPriceFeed,
			abi.encodeWithSelector(IPriceFeed.fetchPrice.selector, mockVst),
			abi.encode(_price)
		);

		vm.mockCall(
			mockPriceFeed,
			abi.encodeWithSelector(
				IPriceFeed.getExternalPrice.selector,
				mockVst
			),
			abi.encode(_price)
		);
	}

	function _expectUpdateEIRCall(address module, uint256 _vstPrice)
		internal
	{
		_mockUpdateEIRCall(module, _vstPrice, 0);

		vm.expectCall(
			module,
			abi.encodeWithSelector(IModuleInterest.updateEIR.selector, _vstPrice)
		);
	}

	function _mockUpdateEIRCall(
		address module,
		uint256 _vstPrice,
		uint256 _response
	) internal {
		vm.mockCall(
			module,
			abi.encodeWithSelector(
				IModuleInterest.updateEIR.selector,
				_vstPrice
			),
			abi.encode(_response)
		);
	}

	function _mockGetDebtOf(
		address _module,
		address _user,
		uint256 _answer
	) internal {
		vm.mockCall(
			_module,
			abi.encodeWithSelector(IModuleInterest.getDebtOf.selector, _user),
			abi.encode(_answer)
		);
	}
}

