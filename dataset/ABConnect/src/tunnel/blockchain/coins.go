package blockchain

// coins

var CoinsName = map[BlockChain]string{
	Dogecoin: "Dogecoin",
	Ethereum: "Ethereum",
}

var CoinsSymbol = map[BlockChain]string{
	Dogecoin: "DOGE",
	Ethereum: "ETH",
}

var CoinsDecimals = map[BlockChain]uint8{
	Dogecoin: 18,
	Ethereum: 18,
}
