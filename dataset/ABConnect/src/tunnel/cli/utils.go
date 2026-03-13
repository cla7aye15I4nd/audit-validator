package cli

import (
	"fmt"
)

func showSuccess(msg string, args ...interface{}) {
	fmt.Printf(msg+"\n", args...)
}

const (
	ActionAdd = iota
	ActionUpdate
)
