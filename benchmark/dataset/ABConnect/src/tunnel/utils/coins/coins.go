package coins

import (
	"github.com/ethereum/go-ethereum/common"
	"gitlab.weinvent.org/yangchenzhong/tunnel/utils/coins/newton"
	"gitlab.weinvent.org/yangchenzhong/tunnel/utils/coins/tron"
)

func IsSupportAddress(address string) bool {
	if common.IsHexAddress(address) {
		return true
	}

	if newton.IsNEWAddress(address) {
		return true
	}

	if tron.IsTronAddress(address) {
		return true
	}

	return false
}
