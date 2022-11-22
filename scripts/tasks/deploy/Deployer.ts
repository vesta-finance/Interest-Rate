import {
	ContractConfig,
	IDeployConfig,
	ModuleConfig,
} from "../../config/DeployConfig";
import { DeploymentHelper } from "../../utils/DeploymentHelper";
import { HardhatRuntimeEnvironment } from "hardhat/types/runtime";
import { HardhatEthersHelpers } from "@nomiclabs/hardhat-ethers/types";
import { Contract } from "ethers";

export class Deployer {
	config: IDeployConfig;
	helper: DeploymentHelper;
	ethers: HardhatEthersHelpers;
	hre: HardhatRuntimeEnvironment;
	safetyVault?: Contract;
	interestManager?: Contract;

	constructor(config: IDeployConfig, hre: HardhatRuntimeEnvironment) {
		this.hre = hre;
		this.ethers = hre.ethers;
		this.config = config;
		this.helper = new DeploymentHelper(config, hre);
	}

	async run() {
		const contractsConfig = this.config.configs!;

		if (contractsConfig == undefined) throw "Config Not found";

		this.safetyVault = await this.helper.deployUpgradeableContractWithName(
			"SafetyVault",
			"SafetyVault"
		);

		this.interestManager =
			await this.helper.deployUpgradeableContractWithName(
				"VestaInterestManager",
				"VestaInterestManager",
				"setUp",
				contractsConfig.vst,
				contractsConfig.troveManager,
				contractsConfig.priceFeed
			);
	}

	async deployModule(contractConfig: ContractConfig) {
		const modules: ModuleConfig[] = contractConfig.modules!;

		if (modules == undefined) throw "No module found";
		if (this.safetyVault == undefined) throw "SafetyVault undefined";
		if (this.interestManager == undefined) {
			throw "InterestManager undefined";
		}

		for (const module of modules) {
			const contract = await this.helper.deployUpgradeableContractWithName(
				"VestaEIR",
				module.name,
				"setUp",
				contractConfig.vst,
				contractConfig.borrowerOperator,
				this.safetyVault!.address,
				this.interestManager!.address,
				module.name,
				module.symbole,
				module.risk
			);

			await this.helper.sendAndWaitForTransaction(
				this.interestManager!.setModuleFor(
					module.linkedToken,
					contract.address
				)
			);
		}
	}
}

