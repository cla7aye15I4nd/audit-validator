package types

import (
	"math/big"
)

// FeeRetriever interface for retrieving market fees
// This matches the v1 FeeRetriever interface for compatibility
type FeeRetriever interface {
	// GetMarketFees returns the maker and taker fees for a given market
	// Parameters:
	//   base: base token ID
	//   quote: quote token ID
	// Returns:
	//   makerFee: fee charged to maker (in basis points)
	//   takerFee: fee charged to taker (in basis points)
	//   error: any error that occurred
	GetMarketFees(base, quote uint64) (*big.Int, *big.Int, error)
}