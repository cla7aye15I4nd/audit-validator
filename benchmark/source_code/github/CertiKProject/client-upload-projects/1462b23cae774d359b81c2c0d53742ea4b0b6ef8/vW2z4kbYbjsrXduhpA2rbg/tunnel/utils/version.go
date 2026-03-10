package utils

import "fmt"

var (
	BrandName = "Tunnel"
)

var (
	buildCommit string
	buildDate   string
)

func Version() string {
	return fmt.Sprintf("%s-%s", buildCommit, buildDate)
}
