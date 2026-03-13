package tpsl

import (
	"fmt"
	"testing"

	"github.com/ethereum/go-ethereum/core/orderbook/v2/types"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestOCOController_RegisterPair(t *testing.T) {
	controller := NewOCOController()

	pair := &OCOPair{
		ID:        "OCO_001",
		OrderIDs:  []types.OrderID{"order1", "order2"},
		Strategy:  OneCancelsOther,
		CreatedAt: 1234567890,
	}

	err := controller.RegisterPair(pair)
	require.NoError(t, err)
	assert.Equal(t, 1, controller.GetPairCount())

	err = controller.RegisterPair(pair)
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "already exists")
}

func TestOCOController_RegisterPairWithExistingOrder(t *testing.T) {
	controller := NewOCOController()

	pair1 := &OCOPair{
		ID:       "OCO_001",
		OrderIDs: []types.OrderID{"order1", "order2"},
		Strategy: OneCancelsOther,
	}

	pair2 := &OCOPair{
		ID:       "OCO_002",
		OrderIDs: []types.OrderID{"order2", "order3"},
		Strategy: OneCancelsOther,
	}

	err := controller.RegisterPair(pair1)
	require.NoError(t, err)

	err = controller.RegisterPair(pair2)
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "already in OCO pair")
}

func TestOCOController_RegisterInvalidPair(t *testing.T) {
	controller := NewOCOController()

	testCases := []struct {
		name string
		pair *OCOPair
	}{
		{"Nil pair", nil},
		{"Empty ID", &OCOPair{ID: "", OrderIDs: []types.OrderID{"order1"}}},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			err := controller.RegisterPair(tc.pair)
			assert.Error(t, err)
			assert.Contains(t, err.Error(), "invalid OCO pair")
		})
	}
}

func TestOCOController_ExecuteOCO_OneCancelsOther(t *testing.T) {
	controller := NewOCOController()

	pair := &OCOPair{
		ID:       "OCO_001",
		OrderIDs: []types.OrderID{"order1", "order2", "order3"},
		Strategy: OneCancelsOther,
	}

	err := controller.RegisterPair(pair)
	require.NoError(t, err)

	toCancel := controller.ExecuteOCO("order1")
	assert.Len(t, toCancel, 2)
	assert.Contains(t, toCancel, types.OrderID("order2"))
	assert.Contains(t, toCancel, types.OrderID("order3"))

	assert.Equal(t, 0, controller.GetPairCount())

	toCancelAgain := controller.ExecuteOCO("order2")
	assert.Len(t, toCancelAgain, 0)
}

func TestOCOController_ExecuteOCO_OneFillsCancelsOthers(t *testing.T) {
	controller := NewOCOController()

	pair := &OCOPair{
		ID:       "OCO_002",
		OrderIDs: []types.OrderID{"order1", "order2"},
		Strategy: OneFillsCancelsOthers,
	}

	err := controller.RegisterPair(pair)
	require.NoError(t, err)

	toCancel := controller.ExecuteOCO("order1")
	assert.Len(t, toCancel, 1)
	assert.Contains(t, toCancel, types.OrderID("order2"))

	assert.Equal(t, 0, controller.GetPairCount())
}

func TestOCOController_ExecuteOCO_AllOrNone(t *testing.T) {
	controller := NewOCOController()

	pair := &OCOPair{
		ID:       "OCO_003",
		OrderIDs: []types.OrderID{"order1", "order2", "order3"},
		Strategy: AllOrNone,
	}

	err := controller.RegisterPair(pair)
	require.NoError(t, err)

	toCancel := controller.ExecuteOCO("order1")
	assert.Len(t, toCancel, 2)
	assert.Contains(t, toCancel, types.OrderID("order2"))
	assert.Contains(t, toCancel, types.OrderID("order3"))

	assert.Equal(t, 0, controller.GetPairCount())
}

func TestOCOController_CancelOCO_OneCancelsOther(t *testing.T) {
	controller := NewOCOController()

	pair := &OCOPair{
		ID:       "OCO_004",
		OrderIDs: []types.OrderID{"order1", "order2"},
		Strategy: OneCancelsOther,
	}

	err := controller.RegisterPair(pair)
	require.NoError(t, err)

	toCancel := controller.CancelOCO("order1")
	assert.Len(t, toCancel, 1)
	assert.Contains(t, toCancel, types.OrderID("order2"))

	assert.Equal(t, 0, controller.GetPairCount())
}

func TestOCOController_CancelOCO_OneFillsCancelsOthers(t *testing.T) {
	controller := NewOCOController()

	pair := &OCOPair{
		ID:       "OCO_005",
		OrderIDs: []types.OrderID{"order1", "order2", "order3"},
		Strategy: OneFillsCancelsOthers,
	}

	err := controller.RegisterPair(pair)
	require.NoError(t, err)

	toCancel := controller.CancelOCO("order1")
	assert.Len(t, toCancel, 0)

	assert.Equal(t, 1, controller.GetPairCount())

	related := controller.GetRelatedOrders("order2")
	assert.Len(t, related, 1)
	assert.Contains(t, related, types.OrderID("order3"))

	toCancel2 := controller.CancelOCO("order2")
	assert.Len(t, toCancel2, 0)

	toCancel3 := controller.CancelOCO("order3")
	assert.Len(t, toCancel3, 0)

	assert.Equal(t, 0, controller.GetPairCount())
}

func TestOCOController_CancelOCO_AllOrNone(t *testing.T) {
	controller := NewOCOController()

	pair := &OCOPair{
		ID:       "OCO_006",
		OrderIDs: []types.OrderID{"order1", "order2", "order3"},
		Strategy: AllOrNone,
	}

	err := controller.RegisterPair(pair)
	require.NoError(t, err)

	toCancel := controller.CancelOCO("order1")
	assert.Len(t, toCancel, 2)
	assert.Contains(t, toCancel, types.OrderID("order2"))
	assert.Contains(t, toCancel, types.OrderID("order3"))

	assert.Equal(t, 0, controller.GetPairCount())
}

func TestOCOController_GetRelatedOrders(t *testing.T) {
	controller := NewOCOController()

	pair := &OCOPair{
		ID:       "OCO_007",
		OrderIDs: []types.OrderID{"order1", "order2", "order3"},
		Strategy: OneCancelsOther,
	}

	err := controller.RegisterPair(pair)
	require.NoError(t, err)

	related := controller.GetRelatedOrders("order1")
	assert.Len(t, related, 2)
	assert.Contains(t, related, types.OrderID("order2"))
	assert.Contains(t, related, types.OrderID("order3"))

	related = controller.GetRelatedOrders("order2")
	assert.Len(t, related, 2)
	assert.Contains(t, related, types.OrderID("order1"))
	assert.Contains(t, related, types.OrderID("order3"))

	related = controller.GetRelatedOrders("nonexistent")
	assert.Len(t, related, 0)
}

func TestOCOController_RemovePair(t *testing.T) {
	controller := NewOCOController()

	pair := &OCOPair{
		ID:       "OCO_008",
		OrderIDs: []types.OrderID{"order1", "order2"},
		Strategy: OneCancelsOther,
	}

	err := controller.RegisterPair(pair)
	require.NoError(t, err)

	removed := controller.RemovePair("OCO_008")
	assert.True(t, removed)
	assert.Equal(t, 0, controller.GetPairCount())

	related := controller.GetRelatedOrders("order1")
	assert.Len(t, related, 0)

	removed = controller.RemovePair("OCO_008")
	assert.False(t, removed)
}

func TestOCOController_Clear(t *testing.T) {
	controller := NewOCOController()

	for i := 0; i < 5; i++ {
		pair := &OCOPair{
			ID:       fmt.Sprintf("OCO_%03d", i),
			OrderIDs: []types.OrderID{types.OrderID(fmt.Sprintf("order_%d_1", i)), types.OrderID(fmt.Sprintf("order_%d_2", i))},
			Strategy: OneCancelsOther,
		}
		err := controller.RegisterPair(pair)
		require.NoError(t, err)
	}

	assert.Equal(t, 5, controller.GetPairCount())

	controller.Clear()
	assert.Equal(t, 0, controller.GetPairCount())

	related := controller.GetRelatedOrders("order_0_1")
	assert.Len(t, related, 0)
}

func TestOCOController_NonExistentOrder(t *testing.T) {
	controller := NewOCOController()

	toCancel := controller.ExecuteOCO("nonexistent")
	assert.Len(t, toCancel, 0)

	toCancel = controller.CancelOCO("nonexistent")
	assert.Len(t, toCancel, 0)

	related := controller.GetRelatedOrders("nonexistent")
	assert.Len(t, related, 0)
}

func TestOCOController_MultiplePairs(t *testing.T) {
	controller := NewOCOController()

	pair1 := &OCOPair{
		ID:       "OCO_001",
		OrderIDs: []types.OrderID{"order1", "order2"},
		Strategy: OneCancelsOther,
	}

	pair2 := &OCOPair{
		ID:       "OCO_002",
		OrderIDs: []types.OrderID{"order3", "order4"},
		Strategy: OneFillsCancelsOthers,
	}

	pair3 := &OCOPair{
		ID:       "OCO_003",
		OrderIDs: []types.OrderID{"order5", "order6"},
		Strategy: AllOrNone,
	}

	require.NoError(t, controller.RegisterPair(pair1))
	require.NoError(t, controller.RegisterPair(pair2))
	require.NoError(t, controller.RegisterPair(pair3))

	assert.Equal(t, 3, controller.GetPairCount())

	toCancel := controller.ExecuteOCO("order1")
	assert.Len(t, toCancel, 1)
	assert.Contains(t, toCancel, types.OrderID("order2"))
	assert.Equal(t, 2, controller.GetPairCount())

	toCancel = controller.CancelOCO("order3")
	assert.Len(t, toCancel, 0)
	
	toCancel = controller.ExecuteOCO("order5")
	assert.Len(t, toCancel, 1)
	assert.Contains(t, toCancel, types.OrderID("order6"))
	assert.Equal(t, 0, controller.GetPairCount()) // All pairs removed now
}

func TestOCOController_GetUserPairs(t *testing.T) {
	controller := NewOCOController()

	userPairs := controller.GetUserPairs("user1")
	assert.Len(t, userPairs, 0)
}

func TestOCOController_ConcurrentOperations(t *testing.T) {
	controller := NewOCOController()

	done := make(chan bool)
	
	go func() {
		for i := 0; i < 100; i++ {
			pair := &OCOPair{
				ID:       fmt.Sprintf("OCO_%d", i),
				OrderIDs: []types.OrderID{types.OrderID(fmt.Sprintf("order_%d_1", i)), types.OrderID(fmt.Sprintf("order_%d_2", i))},
				Strategy: OneCancelsOther,
			}
			controller.RegisterPair(pair)
		}
		done <- true
	}()

	go func() {
		for i := 0; i < 100; i++ {
			controller.ExecuteOCO(types.OrderID(fmt.Sprintf("order_%d_1", i)))
		}
		done <- true
	}()

	go func() {
		for i := 0; i < 100; i++ {
			controller.GetRelatedOrders(types.OrderID(fmt.Sprintf("order_%d_2", i)))
		}
		done <- true
	}()

	for i := 0; i < 3; i++ {
		<-done
	}
}