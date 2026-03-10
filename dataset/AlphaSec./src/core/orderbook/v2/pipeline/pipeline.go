package pipeline

import (
	"fmt"
)

// Stage represents a single processing stage in the order processing pipeline
type Stage interface {
	// Name returns the name of this stage for logging and debugging
	Name() string

	// Process executes the main logic of this stage
	Process(ctx *OrderContext) error

	// Rollback undoes any changes made by this stage in case of error
	Rollback(ctx *OrderContext) error
}

// Pipeline manages the execution of multiple stages in sequence
type Pipeline struct {
	stages []Stage
}

// NewPipeline creates a new Pipeline with the given stages
func NewPipeline(stages ...Stage) *Pipeline {
	return &Pipeline{
		stages: stages,
	}
}

// Execute runs all stages in sequence, rolling back on error
func (p *Pipeline) Execute(ctx *OrderContext) error {
	// Execute each stage in sequence
	for i, stage := range p.stages {
		ctx.StageIndex = i
		
		// Execute the stage
		err := stage.Process(ctx)
		
		if err != nil {
			ctx.Error = err
			
			// Rollback in reverse order starting from the failed stage
			for j := i; j >= 0; j-- {
				rollbackErr := p.stages[j].Rollback(ctx)
				if rollbackErr != nil {
					// Continue rollback process even if individual rollback fails
					// The error is ignored to ensure all rollbacks are attempted
				}
			}
			
			return fmt.Errorf("pipeline failed at stage %s: %w", stage.Name(), err)
		}
	}
	
	return nil
}

// AddStage adds a new stage to the pipeline
func (p *Pipeline) AddStage(stage Stage) {
	p.stages = append(p.stages, stage)
}

// GetStages returns a copy of the stages slice
func (p *Pipeline) GetStages() []Stage {
	stages := make([]Stage, len(p.stages))
	copy(stages, p.stages)
	return stages
}

// GetStageCount returns the number of stages in the pipeline
func (p *Pipeline) GetStageCount() int {
	return len(p.stages)
}

// Clear removes all stages from the pipeline
func (p *Pipeline) Clear() {
	p.stages = []Stage{}
}