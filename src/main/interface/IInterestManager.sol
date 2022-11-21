pragma solidity >=0.8.0;

interface IInterestManager {
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

