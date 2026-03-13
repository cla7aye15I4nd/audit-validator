package orderbook

import (
	"container/heap"
	"github.com/holiman/uint256"
	"testing"
	"time"
)

func TestBuyQueueHeapOrder(t *testing.T) {
	now := time.Now().Unix()

	orders := []*Order{
		{OrderID: "1", Price: new(uint256.Int).SetUint64(100), Timestamp: now + 2},
		{OrderID: "2", Price: new(uint256.Int).SetUint64(101), Timestamp: now + 1},
		{OrderID: "3", Price: new(uint256.Int).SetUint64(101), Timestamp: now}, // 가장 우선
		{OrderID: "4", Price: new(uint256.Int).SetUint64(99), Timestamp: now + 3},
		{OrderID: "5", Price: new(uint256.Int).SetUint64(100), Timestamp: now + 4},
	}

	q := &BuyQueue{}
	heap.Init(q)
	for _, o := range orders {
		heap.Push(q, o)
	}

	wantOrder := []string{"3", "2", "1", "5", "4"} // 우선순위대로
	for i, wantID := range wantOrder {
		o := heap.Pop(q).(*Order)
		if o.OrderID != wantID {
			t.Errorf("BuyQueue[%d]: expected orderID %s, got %s", i, wantID, o.OrderID)
		}
	}
}

func TestSellQueueHeapOrder(t *testing.T) {
	now := time.Now().Unix()

	orders := []*Order{
		{OrderID: "1", Price: new(uint256.Int).SetUint64(100), Timestamp: now + 2},
		{OrderID: "2", Price: new(uint256.Int).SetUint64(99), Timestamp: now + 1},
		{OrderID: "3", Price: new(uint256.Int).SetUint64(99), Timestamp: now}, // 가장 우선
		{OrderID: "4", Price: new(uint256.Int).SetUint64(101), Timestamp: now + 3},
		{OrderID: "5", Price: new(uint256.Int).SetUint64(99), Timestamp: now + 4},
	}

	q := &SellQueue{}
	heap.Init(q)
	for _, o := range orders {
		heap.Push(q, o)
	}

	wantOrder := []string{"3", "2", "5", "1", "4"} // 우선순위대로
	for i, wantID := range wantOrder {
		o := heap.Pop(q).(*Order)
		if o.OrderID != wantID {
			t.Errorf("SellQueue[%d]: expected orderID %s, got %s", i, wantID, o.OrderID)
		}
	}
}
