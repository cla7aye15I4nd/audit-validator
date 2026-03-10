package utils

import (
	"fmt"
	"testing"
)

func TestUtils(t *testing.T) {

	n := int64(1)
	for i := int64(1); i <= 10; i++ {
		fmt.Println(n, GetBChainAmount2Text(n))
		n = n * 10
	}

}
