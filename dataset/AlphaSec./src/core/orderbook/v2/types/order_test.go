package types

import (
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestFailedOrderSerialization(t *testing.T) {
	// Test empty failed orders
	t.Run("Empty FailedOrders", func(t *testing.T) {
		failedOrders := FailedOrders{}

		data, err := failedOrders.Serialize()
		require.NoError(t, err)
		require.NotNil(t, data)

		// Deserialize and verify
		var decoded FailedOrders
		err = decoded.Deserialize(data)
		require.NoError(t, err)
		assert.Empty(t, decoded)
	})

	// Test single failed order
	t.Run("Single FailedOrder", func(t *testing.T) {
		failedOrders := FailedOrders{
			{
				OrderID: "0x1234567890abcdef",
				Reason:  "insufficient balance",
			},
		}

		data, err := failedOrders.Serialize()
		require.NoError(t, err)
		require.NotNil(t, data)

		// Deserialize and verify
		var decoded FailedOrders
		err = decoded.Deserialize(data)
		require.NoError(t, err)
		require.Len(t, decoded, 1)
		assert.Equal(t, OrderID("0x1234567890abcdef"), decoded[0].OrderID)
		assert.Equal(t, "insufficient balance", decoded[0].Reason)
	})

	// Test multiple failed orders
	t.Run("Multiple FailedOrders", func(t *testing.T) {
		failedOrders := FailedOrders{
			{
				OrderID: "0x1111111111111111",
				Reason:  "validation failed",
			},
			{
				OrderID: "0x2222222222222222",
				Reason:  "market closed",
			},
			{
				OrderID: "0x3333333333333333",
				Reason:  "order expired",
			},
		}

		data, err := failedOrders.Serialize()
		require.NoError(t, err)
		require.NotNil(t, data)

		// Deserialize and verify
		var decoded FailedOrders
		err = decoded.Deserialize(data)
		require.NoError(t, err)
		require.Len(t, decoded, 3)

		for i, expected := range failedOrders {
			assert.Equal(t, expected.OrderID, decoded[i].OrderID)
			assert.Equal(t, expected.Reason, decoded[i].Reason)
		}
	})
}