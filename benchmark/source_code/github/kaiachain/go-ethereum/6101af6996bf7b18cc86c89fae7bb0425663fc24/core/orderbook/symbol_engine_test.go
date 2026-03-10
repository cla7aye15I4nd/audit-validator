package orderbook

import (
	"github.com/holiman/uint256"
	"github.com/stretchr/testify/assert"
	"testing"
)

func mustUint256(s string) *uint256.Int {
	val, err := uint256.FromDecimal(s)
	if err != nil {
		panic("invalid decimal: " + s)
	}
	return val
}

// Helper function to scale a decimal value by 10^18
// e.g., toWei("1000") returns 1000 * 10^18
func toWei(value string) *uint256.Int {
	val, err := uint256.FromDecimal(value)
	if err != nil {
		panic("invalid decimal: " + value)
	}
	// Multiply by 10^18
	scale := new(uint256.Int).Exp(uint256.NewInt(10), uint256.NewInt(18))
	return new(uint256.Int).Mul(val, scale)
}

func TestUpdateLevel2(t *testing.T) {
	engine := NewSymbolEngine("1/2") // Use number/number format

	// mock 주문 추가 - scale to Wei (10^18)
	engine.buyQueue.Push(&Order{
		OrderID:  "buy1",
		Price:    toWei("1000"),
		Quantity: toWei("15"),
		Side:     BUY,
	})

	engine.buyQueue.Push(&Order{
		OrderID:  "buy2",
		Price:    toWei("990"),
		Quantity: toWei("20"),
		Side:     BUY,
	})

	engine.sellQueue.Push(&Order{
		OrderID:  "sell1",
		Price:    toWei("1010"),
		Quantity: toWei("30"),
		Side:     SELL,
	})

	engine.sellQueue.Push(&Order{
		OrderID:  "sell2",
		Price:    toWei("1020"),
		Quantity: toWei("10"),
		Side:     SELL,
	})

	// dirty 가격 설정 - use Wei values as keys
	engine.buyDirty[toWei("1000").String()] = struct{}{}
	engine.buyDirty[toWei("990").String()] = struct{}{}
	engine.sellDirty[toWei("1010").String()] = struct{}{}
	engine.sellDirty[toWei("1020").String()] = struct{}{}

	// updateLevel2 실행
	bids, asks := engine.UpdateLevel2()

	// 기대값
	expectedBids := [][]string{
		{"1000", "15"},
		{"990", "20"},
	}

	expectedAsks := [][]string{
		{"1010", "30"},
		{"1020", "10"},
	}

	assert.Equal(t, expectedBids, bids, "buy level2 mismatch")
	assert.Equal(t, expectedAsks, asks, "sell level2 mismatch")
}

func TestUpdateLevel2_Complex(t *testing.T) {
	engine := NewSymbolEngine("1/2") // Use number/number format

	// BUY 쪽 주문
	engine.buyQueue.Push(&Order{
		OrderID:  "b1",
		Price:    toWei("1000"),
		Quantity: toWei("5"),
		Side:     BUY,
	})

	engine.buyQueue.Push(&Order{
		OrderID:    "b2",
		Price:      toWei("1000"),
		Quantity:   toWei("3"),
		Side:       BUY,
		IsCanceled: true, // 무시되어야 함
	})

	engine.buyQueue.Push(&Order{
		OrderID:  "b3",
		Price:    toWei("990"),
		Quantity: uint256.NewInt(0), // 무시되어야 함
		Side:     BUY,
	})

	engine.buyQueue.Push(&Order{
		OrderID:  "b4",
		Price:    toWei("980"),
		Quantity: toWei("2"),
		Side:     BUY,
	})

	// SELL 쪽 주문
	engine.sellQueue.Push(&Order{
		OrderID:  "s1",
		Price:    toWei("1010"),
		Quantity: toWei("4"),
		Side:     SELL,
	})

	engine.sellQueue.Push(&Order{
		OrderID:  "s2",
		Price:    toWei("1010"),
		Quantity: toWei("6"),
		Side:     SELL,
	})

	engine.sellQueue.Push(&Order{
		OrderID:    "s3",
		Price:      toWei("1020"),
		Quantity:   toWei("5"),
		Side:       SELL,
		IsCanceled: true, // 무시되어야 함
	})

	engine.sellQueue.Push(&Order{
		OrderID:  "s4",
		Price:    toWei("1030"),
		Quantity: uint256.NewInt(0), // 무시되어야 함
		Side:     SELL,
	})

	// dirty 가격 직접 설정 (MarkDirty 없이) - use Wei values as keys
	engine.buyDirty[toWei("1000").String()] = struct{}{}
	engine.buyDirty[toWei("990").String()] = struct{}{}
	engine.buyDirty[toWei("980").String()] = struct{}{}
	engine.sellDirty[toWei("1010").String()] = struct{}{}
	engine.sellDirty[toWei("1020").String()] = struct{}{}
	engine.sellDirty[toWei("1030").String()] = struct{}{}

	// 실행
	bids, asks := engine.UpdateLevel2()

	// 기대값
	expectedBids := [][]string{
		{"1000", "5"}, // 유효 주문 1건
		{"990", "0"},  // dirty지만 유효 주문 없음
		{"980", "2"},
	}

	expectedAsks := [][]string{
		{"1010", "10"}, // 두 주문 합산
		{"1020", "0"},  // 취소됨
		{"1030", "0"},  // 수량 0
	}

	assert.Equal(t, expectedBids, bids, "buy level2 mismatch")
	assert.Equal(t, expectedAsks, asks, "sell level2 mismatch")
}

func TestUpdateLevel2_AdvancedScenario(t *testing.T) {
	engine := NewSymbolEngine("1/2") // Use number/number format

	// ----- BUY QUEUE -----
	engine.buyQueue.Push(&Order{
		OrderID:  "b1",
		Price:    toWei("1000"),
		Quantity: toWei("5"),
		Side:     BUY,
	})

	engine.buyQueue.Push(&Order{
		OrderID:    "b2",
		Price:      toWei("1000"),
		Quantity:   toWei("2"),
		Side:       BUY,
		IsCanceled: true, // should be ignored
	})

	engine.buyQueue.Push(&Order{
		OrderID:  "b3",
		Price:    toWei("990"),
		Quantity: uint256.NewInt(0), // ignored due to 0 quantity
		Side:     BUY,
	})

	engine.buyQueue.Push(&Order{
		OrderID:  "b4",
		Price:    toWei("980"),
		Quantity: toWei("15"),
		Side:     BUY,
	})

	// ----- SELL QUEUE -----
	engine.sellQueue.Push(&Order{
		OrderID:  "s1",
		Price:    toWei("1010"),
		Quantity: toWei("6"),
		Side:     SELL,
	})

	engine.sellQueue.Push(&Order{
		OrderID:  "s2",
		Price:    toWei("1010"),
		Quantity: toWei("4"),
		Side:     SELL,
	})

	engine.sellQueue.Push(&Order{
		OrderID:    "s3",
		Price:      toWei("1020"),
		Quantity:   toWei("3"),
		Side:       SELL,
		IsCanceled: true, // ignored
	})

	engine.sellQueue.Push(&Order{
		OrderID:  "s4",
		Price:    toWei("1030"),
		Quantity: uint256.NewInt(0),
		Side:     SELL,
	})

	// ----- DIRTY 설정 (BUY/SELL 구분) ----- use Wei values as keys
	engine.buyDirty[toWei("1000").String()] = struct{}{}
	engine.buyDirty[toWei("990").String()] = struct{}{}
	engine.buyDirty[toWei("980").String()] = struct{}{}

	engine.sellDirty[toWei("1010").String()] = struct{}{}
	engine.sellDirty[toWei("1020").String()] = struct{}{}
	engine.sellDirty[toWei("1030").String()] = struct{}{}

	// 실행
	bids, asks := engine.UpdateLevel2()

	// ----- 기대값 -----
	expectedBids := [][]string{
		{"1000", "5"},
		{"990", "0"}, // dirty but 0 qty
		{"980", "15"},
	}

	expectedAsks := [][]string{
		{"1010", "10"},
		{"1020", "0"}, // dirty + canceled only
		{"1030", "0"}, // dirty + 0 qty
	}

	assert.Equal(t, expectedBids, bids, "BUY level2 mismatch")
	assert.Equal(t, expectedAsks, asks, "SELL level2 mismatch")
}
