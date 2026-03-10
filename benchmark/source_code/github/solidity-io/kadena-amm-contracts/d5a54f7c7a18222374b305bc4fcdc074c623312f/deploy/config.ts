import dotenv from "dotenv";

dotenv.config();

if (!process.env.NETWORK_ID || !process.env.CHAIN_ID || !process.env.PUB_KEY || !process.env.SECRET_KEY) {
	throw new Error("Missing required environment variables: NETWORK_ID, CHAIN_ID, PUB_KEY, SECRET_KEY");
}

export const config = {
	networkId: process.env.NETWORK_ID || "testnet04",
	chainId: process.env.CHAIN_ID || "0",
	apiHost: `https://api${process.env.IS_MAINNET ? "" : ".testnet"}.chainweb.com/chainweb/0.0/`,
	gasLimit: 80300,
	gasPrice: 0.0000001,
	pubKey: process.env.PUB_KEY,
	secretKey: process.env.SECRET_KEY,
};
