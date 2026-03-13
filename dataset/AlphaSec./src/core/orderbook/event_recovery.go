package orderbook

import (
	"bytes"
	"encoding/binary"
	"encoding/gob"
	"fmt"
	"io"
	"os"
	"path"
	"sort"
	"strconv"
	"strings"

	"github.com/ethereum/go-ethereum/log"
)

// EventRecovery handles recovery from event WAL files
type EventRecovery struct {
	dataDir string
}

// NewEventRecovery creates a new event recovery handler
func NewEventRecovery(dataDir string) *EventRecovery {
	return &EventRecovery{
		dataDir: dataDir,
	}
}

// RecoverFromEvents recovers dispatcher state from event files
func (r *EventRecovery) RecoverFromEvents(d *Dispatcher, fromBlock uint64) error {
	log.Info("Starting event-based recovery", "fromBlock", fromBlock, "dataDir", r.dataDir)

	// List all event files
	eventFiles, err := r.listEventFiles(fromBlock)
	if err != nil {
		return fmt.Errorf("failed to list event files: %w", err)
	}

	if len(eventFiles) == 0 {
		log.Info("No event files found for recovery")
		return nil
	}

	log.Info("Found event files for recovery", "count", len(eventFiles))

	// Sort files by block number
	sort.Slice(eventFiles, func(i, j int) bool {
		return eventFiles[i].blockNum < eventFiles[j].blockNum
	})

	// Apply events from each file
	totalEvents := 0
	for _, file := range eventFiles {
		events, err := r.loadEventsFromFile(file.path)
		if err != nil {
			log.Error("Failed to load events from file", "file", file.path, "error", err)
			continue // Skip corrupted files
		}

		log.Info("Applying events from block", "block", file.blockNum, "events", len(events))

		// Apply each event to rebuild state
		for _, event := range events {
			if err := event.Apply(d); err != nil {
				log.Error("Failed to apply event", 
					"type", event.GetEventType(),
					"block", event.GetBase().BlockNumber,
					"error", err)
				// Continue with other events
			}
			totalEvents++
		}
	}

	// Rebuild Level2 books for all engines
	d.mu.RLock()
	for _, engine := range d.engines {
		engine.level2Book = engine.BuildLevel2BookFromQueues()
	}
	d.mu.RUnlock()

	// Start engine goroutines after recovery
	d.StartEngineGoroutines()

	log.Info("Event recovery completed", 
		"files", len(eventFiles),
		"totalEvents", totalEvents,
		"engines", len(d.engines))

	return nil
}

// eventFile represents an event WAL file
type eventFile struct {
	path     string
	blockNum uint64
}

// listEventFiles lists all event files from the given block
func (r *EventRecovery) listEventFiles(fromBlock uint64) ([]eventFile, error) {
	files, err := os.ReadDir(r.dataDir)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, nil // No event directory yet
		}
		return nil, err
	}

	var eventFiles []eventFile
	for _, file := range files {
		if file.IsDir() {
			continue
		}

		// Parse block number from filename (block_<num>.events)
		name := file.Name()
		if !strings.HasPrefix(name, "block_") || !strings.HasSuffix(name, ".events") {
			continue
		}

		// Extract block number
		blockStr := strings.TrimPrefix(name, "block_")
		blockStr = strings.TrimSuffix(blockStr, ".events")
		blockNum, err := strconv.ParseUint(blockStr, 10, 64)
		if err != nil {
			log.Warn("Invalid event file name", "file", name)
			continue
		}

		// Skip blocks before fromBlock
		if blockNum < fromBlock {
			continue
		}

		eventFiles = append(eventFiles, eventFile{
			path:     path.Join(r.dataDir, name),
			blockNum: blockNum,
		})
	}

	return eventFiles, nil
}

// loadEventsFromFile loads events from a single WAL file
func (r *EventRecovery) loadEventsFromFile(filepath string) ([]OrderbookEvent, error) {
	data, err := os.ReadFile(filepath)
	if err != nil {
		return nil, fmt.Errorf("failed to read file: %w", err)
	}

	return r.deserializeEvents(data)
}

// deserializeEvents converts bytes back to events using gob decoding
func (r *EventRecovery) deserializeEvents(data []byte) ([]OrderbookEvent, error) {
	buf := bytes.NewReader(data)
	
	// Read number of events
	var numEvents uint32
	if err := binary.Read(buf, binary.BigEndian, &numEvents); err != nil {
		return nil, fmt.Errorf("failed to read event count: %w", err)
	}

	events := make([]OrderbookEvent, 0, numEvents)
	decoder := gob.NewDecoder(buf)

	for i := uint32(0); i < numEvents; i++ {
		// Read event type
		var eventType string
		if err := decoder.Decode(&eventType); err != nil {
			if err == io.EOF {
				break // End of file
			}
			return nil, fmt.Errorf("failed to decode event type: %w", err)
		}

		// Decode event based on type
		var event OrderbookEvent
		switch eventType {
		case "OrderAdded":
			var e OrderAddedEvent
			if err := decoder.Decode(&e); err != nil {
				return nil, fmt.Errorf("failed to decode OrderAddedEvent: %w", err)
			}
			event = &e

		case "OrderQuantityUpdated":
			var e OrderQuantityUpdatedEvent
			if err := decoder.Decode(&e); err != nil {
				return nil, fmt.Errorf("failed to decode OrderQuantityUpdatedEvent: %w", err)
			}
			event = &e

		case "OrderRemoved":
			var e OrderRemovedEvent
			if err := decoder.Decode(&e); err != nil {
				return nil, fmt.Errorf("failed to decode OrderRemovedEvent: %w", err)
			}
			event = &e

		case "PriceUpdated":
			var e PriceUpdatedEvent
			if err := decoder.Decode(&e); err != nil {
				return nil, fmt.Errorf("failed to decode PriceUpdatedEvent: %w", err)
			}
			event = &e

		case "TPSLOrderAdded":
			var e TPSLOrderAddedEvent
			if err := decoder.Decode(&e); err != nil {
				return nil, fmt.Errorf("failed to decode TPSLOrderAddedEvent: %w", err)
			}
			event = &e

		case "TPSLOrderRemoved":
			var e TPSLOrderRemovedEvent
			if err := decoder.Decode(&e); err != nil {
				return nil, fmt.Errorf("failed to decode TPSLOrderRemovedEvent: %w", err)
			}
			event = &e

		default:
			return nil, fmt.Errorf("unknown event type: %s", eventType)
		}

		events = append(events, event)
	}

	return events, nil
}
