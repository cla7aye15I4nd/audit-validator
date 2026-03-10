package orderbook

import (
	"bytes"
	"encoding/binary"
	"encoding/gob"
	"fmt"
	"os"
	"path"
	"sync"

	"github.com/ethereum/go-ethereum/log"
)

// EventWALLogger handles asynchronous logging of orderbook events
type EventWALLogger struct {
	dataDir      string
	currentBlock uint64
	blockEvents  []OrderbookEvent // Events for current block
	mu           sync.Mutex
}

// NewEventWALLogger creates a new event-based WAL logger
func NewEventWALLogger(dataDir string) (*EventWALLogger, error) {
	// Ensure data directory exists
	if err := os.MkdirAll(dataDir, 0755); err != nil {
		return nil, fmt.Errorf("failed to create event WAL directory: %w", err)
	}

	return &EventWALLogger{
		dataDir:     dataDir,
		blockEvents: make([]OrderbookEvent, 0),
	}, nil
}

// SetBlockContext sets the current block number for event generation
func (w *EventWALLogger) SetBlockContext(blockNum uint64) {
	w.mu.Lock()
	defer w.mu.Unlock()

	// If block changed, flush previous block's events
	if w.currentBlock != blockNum && len(w.blockEvents) > 0 {
		if err := w.flushBlockEvents(); err != nil {
			log.Error("Failed to flush block events", "block", w.currentBlock, "error", err)
		}
	}

	w.currentBlock = blockNum
}

// LogEvents adds multiple events to the current block's event list
func (w *EventWALLogger) LogEvents(events []OrderbookEvent) {
	if len(events) == 0 {
		return
	}

	w.mu.Lock()
	defer w.mu.Unlock()

	w.blockEvents = append(w.blockEvents, events...)
}

// OnBlockEnd flushes all events for the current block atomically
func (w *EventWALLogger) OnBlockEnd(blockNum uint64) error {
	w.mu.Lock()
	defer w.mu.Unlock()

	if len(w.blockEvents) == 0 {
		log.Debug("No events to flush for block", "block", blockNum)
		return nil
	}

	// Verify block number consistency
	if w.currentBlock != blockNum {
		log.Warn("Block number mismatch at block end", "expected", w.currentBlock, "got", blockNum)
	}

	return w.flushBlockEvents()
}

// flushBlockEvents writes all events for the current block to disk
// Must be called with mutex held
func (w *EventWALLogger) flushBlockEvents() error {
	if len(w.blockEvents) == 0 {
		return nil
	}

	// Create filename for this block
	filename := fmt.Sprintf("block_%d.events", w.currentBlock)
	filepath := path.Join(w.dataDir, filename)

	// Serialize events
	data, err := w.serializeEvents(w.blockEvents)
	if err != nil {
		return fmt.Errorf("failed to serialize events: %w", err)
	}

	// Write atomically (write to temp file then rename)
	tempPath := filepath + ".tmp"
	if err := os.WriteFile(tempPath, data, 0644); err != nil {
		return fmt.Errorf("failed to write events file: %w", err)
	}

	// Atomic rename
	if err := os.Rename(tempPath, filepath); err != nil {
		os.Remove(tempPath) // Clean up temp file
		return fmt.Errorf("failed to rename events file: %w", err)
	}

	log.Info("Flushed block events",
		"block", w.currentBlock,
		"events", len(w.blockEvents),
		"file", filename)

	// Clear events for next block
	w.blockEvents = w.blockEvents[:0]

	return nil
}

// serializeEvents converts events to bytes using gob encoding
func (w *EventWALLogger) serializeEvents(events []OrderbookEvent) ([]byte, error) {
	var buf bytes.Buffer

	// Write number of events
	if err := binary.Write(&buf, binary.BigEndian, uint32(len(events))); err != nil {
		return nil, err
	}

	// Encode each event with its type
	encoder := gob.NewEncoder(&buf)
	for _, event := range events {
		// Write event type
		eventType := event.GetEventType()
		if err := encoder.Encode(eventType); err != nil {
			return nil, err
		}

		// Write event data based on type
		switch e := event.(type) {
		case *OrderAddedEvent:
			if err := encoder.Encode(e); err != nil {
				return nil, err
			}
		case *OrderQuantityUpdatedEvent:
			if err := encoder.Encode(e); err != nil {
				return nil, err
			}
		case *OrderRemovedEvent:
			if err := encoder.Encode(e); err != nil {
				return nil, err
			}
		case *PriceUpdatedEvent:
			if err := encoder.Encode(e); err != nil {
				return nil, err
			}
		case *TPSLOrderAddedEvent:
			if err := encoder.Encode(e); err != nil {
				return nil, err
			}
		case *TPSLOrderRemovedEvent:
			if err := encoder.Encode(e); err != nil {
				return nil, err
			}
		default:
			return nil, fmt.Errorf("unknown event type: %T", event)
		}
	}

	return buf.Bytes(), nil
}

// Close shuts down the event WAL logger gracefully
func (w *EventWALLogger) Close() error {
	w.mu.Lock()
	defer w.mu.Unlock()

	// Flush any remaining events
	if len(w.blockEvents) > 0 {
		log.Info("Flushing remaining events on close", "events", len(w.blockEvents))
		if err := w.flushBlockEvents(); err != nil {
			log.Error("Failed to flush events on close", "error", err)
			return err
		}
	}

	log.Info("Event WAL logger closed")
	return nil
}
