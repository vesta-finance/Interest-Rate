import { IDeployConfig } from "../../config/DeployConfig"
import { DeploymentHelper } from "../../utils/DeploymentHelper"
import { HardhatRuntimeEnvironment } from "hardhat/types/runtime"
import { HardhatEthersHelpers } from "@nomiclabs/hardhat-ethers/types"
import { colorLog, Colors } from "../../utils/ColorConsole"
import { Contract } from "ethers"

export class Deployer {
	config: IDeployConfig
	helper: DeploymentHelper
	ethers: HardhatEthersHelpers
	hre: HardhatRuntimeEnvironment

	constructor(config: IDeployConfig, hre: HardhatRuntimeEnvironment) {
		this.hre = hre
		this.ethers = hre.ethers
		this.config = config
		this.helper = new DeploymentHelper(config, hre)
	}

	async run() {}

	async deployModule() {}
}

