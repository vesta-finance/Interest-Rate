// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface IInterestManager {
	event ModuleLinked(address indexed token, address indexed module);
	event DebtChanged(
		address indexed token,
		address indexed user,
		uint256 newDebt
	);
	event InterestMinted(address indexed module, uint256 interestMinted);

	error NotTroveManager();
	error ErrorModuleAlreadySet();

	function increaseDebt(
		address _token,
		address _user,
		uint256 _debt
	) external returns (uint256 interestDebt_);

	function decreaseDebt(
		address _token,
		address _user,
		uint256 _debt
	) external returns (uint256 interestDebt_);

	function getUserDebt(address _token, address _user)
		external
		view
		returns (uint256 currentDebt_, uint256 pendingInterest_);

	function getLastVstPrice() external view returns (uint256);
}

