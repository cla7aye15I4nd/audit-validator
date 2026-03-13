package metrics

import (
	"github.com/ethereum/go-ethereum/metrics"
)

var (
	// Dispatcher metrics
	DispatcherRequestsTotal      = metrics.NewRegisteredCounter("orderbook/dispatcher/requests/total", nil)
	DispatcherRequestsSuccessful = metrics.NewRegisteredCounter("orderbook/dispatcher/requests/successful", nil)
	DispatcherRequestsFailed     = metrics.NewRegisteredCounter("orderbook/dispatcher/requests/failed", nil)
	DispatcherQueueLengthGauge   = metrics.NewRegisteredGauge("orderbook/dispatcher/queue/length", nil)
	DispatcherProcessingTimer    = metrics.NewRegisteredTimer("orderbook/dispatcher/processing/time", nil)
	DispatcherActiveEnginesGauge = metrics.NewRegisteredGauge("orderbook/dispatcher/engines/active", nil)
	DispatcherTotalOrders        = metrics.NewRegisteredCounter("orderbook/dispatcher/orders/total", nil)
	DispatcherTotalTrades        = metrics.NewRegisteredCounter("orderbook/dispatcher/trades/total", nil)
	DispatcherTotalVolumeGauge   = metrics.NewRegisteredGauge("orderbook/dispatcher/volume/total", nil) // Volume in whole units (divided by 10^18)

	// Balance manager metrics
	BalanceLocksActiveGauge     = metrics.NewRegisteredGauge("orderbook/balance/locks/active", nil)
	BalanceLocksCreatedCounter  = metrics.NewRegisteredCounter("orderbook/balance/locks/created", nil)
	BalanceLocksReleasedCounter = metrics.NewRegisteredCounter("orderbook/balance/locks/released", nil)
	BalanceLocksFailedCounter   = metrics.NewRegisteredCounter("orderbook/balance/locks/failed", nil)
	BalanceSettlementsCounter   = metrics.NewRegisteredCounter("orderbook/balance/settlements/total", nil)

	// Conditional orders metrics
	ConditionalOrdersActiveGauge      = metrics.NewRegisteredGauge("orderbook/conditional/orders/active", nil)
	ConditionalOrdersTriggeredCounter = metrics.NewRegisteredCounter("orderbook/conditional/orders/triggered", nil)

	// Persistence metrics
	PersistenceWALEntriesCounter     = metrics.NewRegisteredCounter("orderbook/persistence/wal/entries", nil)
	PersistenceWALSizeGauge          = metrics.NewRegisteredGauge("orderbook/persistence/wal/size", nil)
	PersistenceWALWriteTimer         = metrics.NewRegisteredTimer("orderbook/persistence/wal/write/time", nil)
	PersistenceWALReadTimer          = metrics.NewRegisteredTimer("orderbook/persistence/wal/read/time", nil)
	PersistenceSnapshotsCounter      = metrics.NewRegisteredCounter("orderbook/persistence/snapshots/created", nil)
	PersistenceSnapshotSizeGauge     = metrics.NewRegisteredGauge("orderbook/persistence/snapshot/size", nil)
	PersistenceSnapshotTimer         = metrics.NewRegisteredTimer("orderbook/persistence/snapshot/time", nil)
	PersistenceRecoveryTimer         = metrics.NewRegisteredTimer("orderbook/persistence/recovery/time", nil)
	PersistenceRecoveryErrorsCounter = metrics.NewRegisteredCounter("orderbook/persistence/recovery/errors", nil)
)

// Per-symbol metrics helpers
func GetSymbolCounter(base string, symbol string) *metrics.Counter {
	return metrics.GetOrRegisterCounter(base+"/"+symbol, nil)
}

func GetSymbolTimer(base string, symbol string) *metrics.Timer {
	return metrics.GetOrRegisterTimer(base+"/"+symbol, nil)
}

func GetSymbolGauge(base string, symbol string) *metrics.Gauge {
	return metrics.GetOrRegisterGauge(base+"/"+symbol, nil)
}
