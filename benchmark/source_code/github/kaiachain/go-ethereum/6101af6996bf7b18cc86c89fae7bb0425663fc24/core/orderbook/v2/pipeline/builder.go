package pipeline

// PipelineType represents the type of pipeline to create
type PipelineType int

const (
	PIPELINE_TRADING PipelineType = iota
	PIPELINE_TRADING_WITH_MODIFY
	PIPELINE_MANAGEMENT
)

// PipelineBuilder helps construct pipelines with the right configuration
type PipelineBuilder struct {
	stages []Stage
}

// NewPipelineBuilder creates a new pipeline builder
func NewPipelineBuilder() *PipelineBuilder {
	return &PipelineBuilder{
		stages: make([]Stage, 0),
	}
}

// AddStage adds a stage to the pipeline being built
func (b *PipelineBuilder) AddStage(stage Stage) *PipelineBuilder {
	b.stages = append(b.stages, stage)
	return b
}

// Build creates the final pipeline
func (b *PipelineBuilder) Build() *Pipeline {
	return NewPipeline(b.stages...)
}

// Reset clears the builder for reuse
func (b *PipelineBuilder) Reset() *PipelineBuilder {
	b.stages = make([]Stage, 0)
	return b
}

// PipelineFactory creates pre-configured pipelines
type PipelineFactory struct{}

// NewPipelineFactory creates a new pipeline factory
func NewPipelineFactory() *PipelineFactory {
	return &PipelineFactory{}
}

// CreatePipeline creates a pipeline based on the specified type
func (f *PipelineFactory) CreatePipeline(pipelineType PipelineType) *Pipeline {
	switch pipelineType {
	case PIPELINE_TRADING:
		return NewTradingPipeline()
	case PIPELINE_TRADING_WITH_MODIFY:
		return NewTradingPipelineWithModifySupport()
	case PIPELINE_MANAGEMENT:
		return NewManagementPipeline()
	default:
		// Return a basic trading pipeline as default
		return NewTradingPipeline()
	}
}

// CreateCustomPipeline allows creating a custom pipeline with specific stages
func (f *PipelineFactory) CreateCustomPipeline(stages ...Stage) *Pipeline {
	return NewPipeline(stages...)
}

// PipelineManager manages multiple pipelines for different operations
type PipelineManager struct {
	tradingPipeline    *Pipeline
	managementPipeline *Pipeline
	factory            *PipelineFactory
}

// NewPipelineManager creates a new pipeline manager with default pipelines
func NewPipelineManager() *PipelineManager {
	factory := NewPipelineFactory()
	return &PipelineManager{
		tradingPipeline:    factory.CreatePipeline(PIPELINE_TRADING),
		managementPipeline: factory.CreatePipeline(PIPELINE_MANAGEMENT),
		factory:            factory,
	}
}

// GetTradingPipeline returns the trading pipeline
func (m *PipelineManager) GetTradingPipeline() *Pipeline {
	return m.tradingPipeline
}

// GetManagementPipeline returns the management pipeline
func (m *PipelineManager) GetManagementPipeline() *Pipeline {
	return m.managementPipeline
}

// SetTradingPipeline sets a custom trading pipeline
func (m *PipelineManager) SetTradingPipeline(pipeline *Pipeline) {
	m.tradingPipeline = pipeline
}

// SetManagementPipeline sets a custom management pipeline
func (m *PipelineManager) SetManagementPipeline(pipeline *Pipeline) {
	m.managementPipeline = pipeline
}

// EnableModifySupport switches the trading pipeline to support modify operations
func (m *PipelineManager) EnableModifySupport() {
	m.tradingPipeline = m.factory.CreatePipeline(PIPELINE_TRADING_WITH_MODIFY)
}

// ProcessOrder decides which pipeline to use based on the operation
func (m *PipelineManager) ProcessOrder(ctx *OrderContext) error {
	// Check metadata to determine operation type
	action, exists := ctx.Metadata["action"]
	if !exists {
		// Default to trading pipeline for orders
		return m.tradingPipeline.Execute(ctx)
	}
	
	switch action {
	case "cancel", "cancel_all":
		return m.managementPipeline.Execute(ctx)
	case "order", "modify", "stop_order":
		return m.tradingPipeline.Execute(ctx)
	default:
		return m.tradingPipeline.Execute(ctx)
	}
}