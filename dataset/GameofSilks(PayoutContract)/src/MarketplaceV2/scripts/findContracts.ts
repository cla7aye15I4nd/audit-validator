import axios from "axios";

const ETHERSCAN_API_KEY = "7S9SQXR41HNGWWI25MM83S28HQY5HM6CPT"; // Replace with your Etherscan API Key
// const WALLET_ADDRESS = "0xC656670E47eEB2a77cDC330Fbcb0b8A4Ca953e1C"; // MAINNET
// const WALLET_ADDRESS = "0x7edAC4f0251a484a28F757d8f6e83783a1f38285"; // MAINNET
const WALLET_ADDRESS = "0x4a40e425a8d1ee6279f860d8fd5db3d3661558d6"; // GOERLI
// const ETHERSCAN_API_URL = "https://api.etherscan.io/api";
const ETHERSCAN_API_URL = "https://api-goerli.etherscan.io/api";

const fetchTransactions = async (address: string) => {
	try {
		const response = await axios.get(ETHERSCAN_API_URL, {
			params: {
				module: "account",
				action: "txlist",
				address: address,
				startblock: 8530082,
				endblock: 99999999,
				sort: "asc",
				apiKey: ETHERSCAN_API_KEY,
			},
		});

		return response.data.result;
	} catch (error) {
		console.error("Error fetching transactions:", error);
		return [];
	}
};

const filterContractCreations = (transactions: any[]) => {
	return transactions.filter((tx) => tx.to === "" && tx.input !== "0x");
};

const main = async () => {
	const transactions = await fetchTransactions(WALLET_ADDRESS);
	const contractCreations = filterContractCreations(transactions);

	console.log("Contract Creation Transactions:", contractCreations);
	const contractAddresses = contractCreations.map((tx) => tx.contractAddress);
	console.log("Contract Addresses: ", contractAddresses);
};

main();
