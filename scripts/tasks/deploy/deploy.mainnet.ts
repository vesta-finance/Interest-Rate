import { IDeployConfig } from "../../config/DeployConfig";
import { Deployer } from "./Deployer";
import { colorLog, Colors, addColor } from "../../utils/ColorConsole";
import { HardhatRuntimeEnvironment } from "hardhat/types/runtime";
import readline from "readline-sync";

const config: IDeployConfig = {
	TX_CONFIRMATIONS: 3,
	configs: {
		admin: "0x4A4651B31d747D1DdbDDADCF1b1E24a5f6dcc7b0",
		vst: "0x64343594Ab9b56e99087BfA6F2335Db24c2d1F17",
		troveManager: "0x100EC08129e0FD59959df93a8b914944A3BbD5df",
		borrowerOperator: "0x3eEDF348919D130954929d4ff62D626f26ADBFa2",
		priceFeed: "0xd218Ba424A6166e37A454F8eCe2bf8eB2264eCcA",
		modules: [
			//ETH
			{
				linkedToken: "0x0000000000000000000000000000000000000000",
				name: "Module ETH",
				risk: 0,
			},
			//gOHM
			{
				linkedToken: "0x8D9bA570D6cb60C7e3e0F31343Efe75AB8E65FB1",
				name: "Module gOHM",
				risk: 1,
			},
			//GMX
			{
				linkedToken: "0xfc5A1A6EB076a2C7aD06eD22C90d7E710E35ad0a",
				name: "Module GMX",
				risk: 2,
			},
			//DPX
			{
				linkedToken: "0x6c2c06790b3e3e3c38e12ee22f8183b37a13ee55",
				name: "Module DPX",
				risk: 1,
			},
			//GLP
			{
				linkedToken: "0x2F546AD4eDD93B956C8999Be404cdCAFde3E89AE",
				name: "Module GLP",
				risk: 2,
			},
		],
	},
};

export async function execute(hre: HardhatRuntimeEnvironment) {
	var userinput: string = "0";

	userinput = readline.question(
		addColor(
			Colors.yellow,
			`\nYou are about to deploy on the mainnet, is it fine? [y/N]\n`
		)
	);

	if (userinput.toLowerCase() !== "y") {
		colorLog(Colors.blue, `User cancelled the deployment!\n`);
		return;
	}

	colorLog(Colors.green, `User approved the deployment\n`);

	await new Deployer(config, hre).run();
}

