package orderbook

import (
	"sort"

	"github.com/holiman/uint256"
	"github.com/shopspring/decimal"
)

// Level2Entry represents a single price level in the Level2 book
type Level2Entry struct {
	Price    *uint256.Int
	Quantity *uint256.Int
}

// Level2Book maintains the aggregated order book with price levels
type Level2Book struct {
	Bids map[string]*Level2Entry // Price string → Level2Entry mapping
	Asks map[string]*Level2Entry // Price string → Level2Entry mapping
}

// NewLevel2Book creates a new Level2Book instance
func NewLevel2Book() *Level2Book {
	return &Level2Book{
		Bids: make(map[string]*Level2Entry),
		Asks: make(map[string]*Level2Entry),
	}
}

// ToSortedStringLists converts the Level2Book to sorted bid and ask lists
func (book *Level2Book) ToSortedStringLists() ([][]string, [][]string) {
	bidList := toSortedLevel2List(book.Bids, true)  // Higher price first (descending)
	askList := toSortedLevel2List(book.Asks, false) // Lower price first (ascending)
	return bidList, askList
}

// toSortedLevel2List converts a map of Level2Entry to a sorted list of string arrays
func toSortedLevel2List(entries map[string]*Level2Entry, descending bool) [][]string {
	slice := make([]*Level2Entry, 0, len(entries))
	for _, entry := range entries {
		if entry.Quantity.IsZero() {
			continue
		}
		slice = append(slice, entry)
	}

	sort.Slice(slice, func(i, j int) bool {
		if descending {
			return slice[i].Price.Cmp(slice[j].Price) > 0
		}
		return slice[i].Price.Cmp(slice[j].Price) < 0
	})

	result := make([][]string, 0, len(slice))
	for _, entry := range slice {
		result = append(result, []string{
			decimal.NewFromBigInt(entry.Price.ToBig(), -ScalingExp).String(),
			decimal.NewFromBigInt(entry.Quantity.ToBig(), -ScalingExp).String(),
		})
	}

	return result
}

// buildLevel2BookFromQueues rebuilds the Level2Book from buy and sell queues
func buildLevel2BookFromQueues(buyQueue BuyQueue, sellQueue SellQueue) *Level2Book {
	bidMap := make(map[string]*uint256.Int)
	askMap := make(map[string]*uint256.Int)

	// Process BuyQueue (higher price priority)
	for _, order := range buyQueue {
		if order == nil || order.IsCanceled || order.Price == nil || order.Quantity == nil || order.Quantity.IsZero() {
			continue
		}
		priceStr := order.Price.String()
		if _, exists := bidMap[priceStr]; !exists {
			bidMap[priceStr] = uint256.NewInt(0)
		}
		bidMap[priceStr] = new(uint256.Int).Add(bidMap[priceStr], order.Quantity)
	}

	// Process SellQueue (lower price priority)
	for _, order := range sellQueue {
		if order == nil || order.IsCanceled || order.Price == nil || order.Quantity == nil || order.Quantity.IsZero() {
			continue
		}
		priceStr := order.Price.String()
		if _, exists := askMap[priceStr]; !exists {
			askMap[priceStr] = uint256.NewInt(0)
		}
		askMap[priceStr] = new(uint256.Int).Add(askMap[priceStr], order.Quantity)
	}

	bids := mapToLevel2Entry(bidMap)
	asks := mapToLevel2Entry(askMap)

	return &Level2Book{Bids: bids, Asks: asks}
}

// Helper function: convert string → *uint256.Int map to Level2Entry map
func mapToLevel2Entry(m map[string]*uint256.Int) map[string]*Level2Entry {
	result := make(map[string]*Level2Entry)
	for priceStr, qty := range m {
		result[priceStr] = &Level2Entry{
			Price:    uint256.MustFromDecimal(priceStr),
			Quantity: qty,
		}
	}
	return result
}

// updateLevel2ByQueue updates the Level2Book for a specific side with dirty tracking
func updateLevel2ByQueue(book *Level2Book, queue []*Order, side Side, dirty map[string]struct{}) [][]string {
	var bookSide map[string]*Level2Entry
	
	if side == BUY {
		bookSide = book.Bids
	} else {
		bookSide = book.Asks
	}

	delta := make(map[string]*Level2Entry)
	for priceStr := range dirty {
		delta[priceStr] = &Level2Entry{
			Price:    uint256.MustFromDecimal(priceStr),
			Quantity: new(uint256.Int),
		}
	}

	for _, o := range queue {
		if o.IsCanceled || o.Quantity.IsZero() {
			continue
		}
		priceStr := o.Price.String()
		if _, ok := dirty[priceStr]; !ok {
			continue
		}

		delta[priceStr].Quantity = new(uint256.Int).Add(delta[priceStr].Quantity, o.Quantity)
	}

	// Update existing book (only modified price levels)
	for priceStr, entry := range delta {
		if entry.Quantity.IsZero() {
			delete(bookSide, priceStr)
		} else {
			bookSide[priceStr] = entry
		}
	}

	deltaSlice := make([]*Level2Entry, 0, len(delta))
	for _, entry := range delta {
		deltaSlice = append(deltaSlice, entry)
	}

	sort.Slice(deltaSlice, func(i, j int) bool {
		if side == BUY {
			return deltaSlice[i].Price.Cmp(deltaSlice[j].Price) > 0 // Higher price first
		}
		return deltaSlice[i].Price.Cmp(deltaSlice[j].Price) < 0 // Lower price first
	})

	result := make([][]string, 0, len(deltaSlice))
	for _, entry := range deltaSlice {
		result = append(result, []string{
			decimal.NewFromBigInt(entry.Price.ToBig(), -ScalingExp).String(),    // Price converted to string
			decimal.NewFromBigInt(entry.Quantity.ToBig(), -ScalingExp).String(), // Quantity converted to string
		})
	}

	return result
}