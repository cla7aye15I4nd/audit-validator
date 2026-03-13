package utils

import (
	"bufio"
	"fmt"
	"os"
	"strings"
)

// Name TunnelNamePrefix-<DestNetworkName>-<DestChainId>-<DestAddress>
const (
	TunnelNamePrefix = "Tunnel"
	TunnelNameSep    = "-"

	SwapName = "Swap"
)

func GetInternalAddressName(network, chainId, address string, enableSwap bool) string {
	if enableSwap {
		return strings.Join([]string{TunnelNamePrefix, network, chainId, address, SwapName}, TunnelNameSep)
	}
	return strings.Join([]string{TunnelNamePrefix, network, chainId, address}, TunnelNameSep)
}

const (
	TimeFormat = "2006-01-02 15:04:05"
)

func MergeNetworkPrefix(a, b string) string {
	al := strings.ToLower(a)
	bl := strings.ToLower(b)

	var root string
	if strings.Compare(al, bl) > 0 {
		root = fmt.Sprintf("%v%v", al, bl)
	} else {
		root = fmt.Sprintf("%v%v", bl, al)
	}

	return root
}

func Confirm() bool {
	fmt.Printf("Are your sure to continue (y/N)? ")
	reader := bufio.NewReader(os.Stdin)
	input, _ := reader.ReadString('\n')
	input = strings.TrimSpace(input)
	input = strings.ToLower(input)
	if input == "y" || input == "yes" {
		return true
	}
	return false
}
