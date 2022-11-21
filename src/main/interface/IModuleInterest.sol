pragma solidity >=0.8.0;

interface IModuleInterest {
	function increaseDebt(address _vault, uint256 _debt)
		external
		returns (uint256 addedInterest_);

	function decreaseDebt(address _vault, uint256 _debt)
		external
		returns (uint256 addedInterest_);

	function exit(address _vault) external returns (uint256 addedInterest_);

	function updateEIR(uint256 _vstPrice) external;

	function getNotEmittedInterestRate(address user)
		external
		view
		returns (uint256);

	function getDebtOf(address _vault) external view returns (uint256);
}

