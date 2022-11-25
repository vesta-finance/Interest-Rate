export interface IDeployConfig {
	TX_CONFIRMATIONS: number;
	configs?: ContractConfig;
}

export interface ContractConfig {
	admin: string;
	vst: string;
	borrowerOperator: string;
	troveManager: string;
	priceFeed: string;
	modules?: ModuleConfig[];
}

export interface ModuleConfig {
	linkedToken: string;
	name: string;
	risk: number;
}

