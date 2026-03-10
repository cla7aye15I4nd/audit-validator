package types

// GetTokens returns base and quote tokens for a symbol
// Format: "ETH/USDT" -> ("ETH", "USDT")
func GetTokens(symbol Symbol) (baseToken, quoteToken string) {
	tokens := splitSymbol(string(symbol))
	if len(tokens) == 2 {
		return tokens[0], tokens[1]
	}
	// Fallback - should not happen with valid symbols
	return "BASE", "QUOTE"
}

// splitSymbol splits a trading pair symbol
func splitSymbol(symbol string) []string {
	// Look for common separators
	for _, sep := range []string{"/", "-", "_"} {
		if idx := indexOf(symbol, sep); idx != -1 {
			return []string{symbol[:idx], symbol[idx+1:]}
		}
	}
	return []string{symbol}
}

// indexOf finds index of substring
func indexOf(s, substr string) int {
	for i := 0; i < len(s)-len(substr)+1; i++ {
		if s[i:i+len(substr)] == substr {
			return i
		}
	}
	return -1
}