package types

import (
	flag "github.com/spf13/pflag"
	"time"
)

// OrderbookConfig defines the orderbook system configuration
// This is a copy of the main orderbook.OrderbookConfig to avoid import cycles
type OrderbookConfig struct {
	// Version settings
	Version string `koanf:"version"` // "v1", "v2", or "auto" (default: "v1")

	// Performance settings
	EnableMetrics   bool          `koanf:"enable-metrics"`
	MetricsInterval time.Duration `koanf:"metrics-interval"`

	// Persistence settings
	PersistenceEnabled bool   `koanf:"persistence-enabled"`
	PersistenceDir     string `koanf:"persistence-dir"`
	SnapshotInterval   uint64 `koanf:"snapshot-interval"`

	// Async persistence settings
	AsyncSnapshotCreation bool `koanf:"async-snapshot-creation"`
}

// DefaultOrderbookConfig returns a default orderbook configuration
func DefaultOrderbookConfig() OrderbookConfig {
	return OrderbookConfig{
		Version:            "v2", // Default to v1 for backward compatibility
		EnableMetrics:      true,
		MetricsInterval:    30 * time.Second,
		PersistenceEnabled:    true,        // Enabled by default
		PersistenceDir:        "orderbook", // Relative to chain datadir
		SnapshotInterval:      1000,        // Every 1000 blocks
		AsyncSnapshotCreation: true,        // Enable async snapshot creation for better performance
	}
}

// OrderbookConfigAddOptions adds command-line options for orderbook configuration
func OrderbookConfigAddOptions(prefix string, f *flag.FlagSet) {
	def := DefaultOrderbookConfig()
	f.String(prefix+".version", def.Version, "orderbook version to use: v1 (stable), v2 (experimental), or auto (automatic selection)")
	f.Bool(prefix+".enable-metrics", def.EnableMetrics, "enable orderbook metrics collection")
	f.Duration(prefix+".metrics-interval", def.MetricsInterval, "interval for metrics collection")
	f.Bool(prefix+".persistence-enabled", def.PersistenceEnabled, "enable orderbook persistence to disk")
	f.String(prefix+".persistence-dir", def.PersistenceDir, "directory for orderbook persistence data (relative to chain datadir if not absolute)")
	f.Uint64(prefix+".snapshot-interval", def.SnapshotInterval, "blocks between orderbook snapshots")
	// Async persistence options
	f.Bool(prefix+".async-snapshot-creation", def.AsyncSnapshotCreation, "enable asynchronous snapshot creation for better performance")
}
