package cli

import (
	"encoding/json"
	"fmt"
	"math/big"

	"github.com/ethereum/go-ethereum/common"
	"github.com/sirupsen/logrus"
	"github.com/spf13/cobra"
	"github.com/spf13/viper"
	"gitlab.weinvent.org/yangchenzhong/tunnel/blockchain"
	"gitlab.weinvent.org/yangchenzhong/tunnel/monitor"
	"gitlab.weinvent.org/yangchenzhong/tunnel/utils/config"
)

func (cli *CLI) buildMonitorCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "monitor [--detected] [add]",
		Short: "Monitor on-chain deposits",
		Run: func(cmd *cobra.Command, args []string) {
			cli.monitorRun(cmd, args)

			return
		},
	}

	cmd.PersistentFlags().Int64("start", 0, "The `number` of start block")
	cmd.PersistentFlags().Bool("detected", false, "Detected the latest deposit, force use DelayBlockNumber as 0")

	cmd.AddCommand(cli.buildMonitorAddCmd())

	return cmd
}

func (cli *CLI) monitorRun(cmd *cobra.Command, args []string) {
	var err error

	cb, err := loadBridge()
	if err != nil {
		fmt.Println(err)
		return
	}

	cbb, err := json.MarshalIndent(*cb, " ", " ")
	if err != nil {
		fmt.Println("MarshalIndent: ", err)
		return
	}
	fmt.Println(string(cbb))

	if err := handleBlockchain(cb); err != nil {
		fmt.Println(err)
		return
	}
	if err := applyDB(cb); err != nil {
		fmt.Println(err)
		return
	}

	var startBig *big.Int
	if cmd.Flags().Changed("start") {
		start, err := cmd.Flags().GetInt64("start")
		if err != nil {
			fmt.Println(err)
			return
		}
		startBig = big.NewInt(start)
	}

	if cmd.Flags().Changed("detected") {
		detected, err := cmd.Flags().GetBool("detected")
		if err != nil {
			fmt.Println(err)
			return
		}
		if detected {
			log.Warnf("Force DelayBlockNumber from %v to zero", cb.Blockchain.DelayBlockNumber)
			cb.Blockchain.DelayBlockNumber = 0
		}
	}

	m, err := monitor.New(cb)
	if err != nil {
		fmt.Println(err)
		return
	}
	if err := m.InitBlockchain(); err != nil {
		fmt.Println(err)
		return
	}

	if viper.GetString("LogLevel") != "" {
		logLevel, err := logrus.ParseLevel(viper.GetString("LogLevel"))
		if err != nil {
			fmt.Println(err)
			return
		}
		m.SetLevel(logLevel)
	}

	if bc := m.Blockchain.BaseChain; bc == blockchain.Dogecoin {
		fmt.Printf("not support monitor %s of onchain deposit, run `indexer`\n", m.Blockchain.Network)
		return
	}
	m.RunDepositMonitor(startBig)
}

func (cli *CLI) buildMonitorAddCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:                   "add <txHash> <tokenAddress|empty> <internalAddress> <sender> <amountOfAsset>",
		Short:                 "add missed monitor tx hash and set it BridgeDeposit",
		DisableFlagsInUseLine: true,
		Args:                  cobra.ExactArgs(5),
		Example:               `monitor add 0x58bbf9d12780bb454d976852542e512a984470ba0364ec4bf6ddec1ebd39d0dd 0xdAC17F958D2ee523a2206206994597C13D831ec7 0x8a7abd016d251578492980b1A4568D4f891e60F9 0x7EdC0CaDD6c20811058D4FB3EDA6F9218cCC7332 5`,
		Run: func(cmd *cobra.Command, args []string) {
			hash := common.HexToHash(args[0])
			if hash == (common.Hash{}) {
				fmt.Println("Hash is empty: ", args[0])
				return
			}

			assetStr := args[1]
			var asset common.Address
			if assetStr != "" {
				if !common.IsHexAddress(assetStr) {
					fmt.Println("Asset address is invalid: ", assetStr)
					return
				}
				asset = common.HexToAddress(assetStr)
			}

			address := common.HexToAddress(args[2])
			if address == (common.Address{}) {
				fmt.Println("Address is empty: ", args[2])
				return
			}

			sender := common.HexToAddress(args[3])
			if sender == (common.Address{}) {
				fmt.Println("Sender is empty: ", args[3])
				return
			}

			amountOfAsset := args[4]

			all := viper.AllSettings()
			allJson, err := json.Marshal(&all)
			if err != nil {
				fmt.Println(err)
				return
			}

			var cb config.Bridge
			err = json.Unmarshal(allJson, &cb)
			if err != nil {
				fmt.Println(err)
				return
			}

			if err := handleBlockchain(&cb); err != nil {
				fmt.Println(err)
				return
			}

			m, err := monitor.New(&cb)
			if err != nil {
				fmt.Println(err)
				return
			}
			if err := m.InitBlockchain(); err != nil {
				fmt.Println(err)
				return
			}

			err = m.Add(hash, asset, address, sender, amountOfAsset)
			if err != nil {
				fmt.Println(err)
				return
			}

			fmt.Println("Successfully add missed tx hash and set it BridgeDeposit")
		},
	}

	return cmd
}
