package tron

import (
	"testing"

	"github.com/ethereum/go-ethereum/common"

	"github.com/stretchr/testify/require"
)

func TestAddress(t *testing.T) {
	address := common.HexToAddress("0xa614f803b6fd780986a42c78ec9c7f77e6ded13c")
	a, err := NewAddress("TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t")

	require.NoError(t, err)
	require.Equal(t, a.Address, address)
	require.Equal(t, a.String(), "TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t")
}
