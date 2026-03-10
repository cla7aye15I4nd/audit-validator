package cli

import (
	"encoding/json"
	"errors"
	"fmt"
	"math/big"
	"os"
	"strconv"
	"text/tabwriter"

	"github.com/spf13/cobra"
	"github.com/spf13/viper"
	db "github.com/upper/db/v4"
	"gitlab.weinvent.org/yangchenzhong/tunnel/api"
	"gitlab.weinvent.org/yangchenzhong/tunnel/blockchain"
	"gitlab.weinvent.org/yangchenzhong/tunnel/database"
)

func (cli *CLI) buildBlockchainCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:                   "bc <add|update|delete|list>",
		Short:                 "Manager blockchain",
		Aliases:               []string{"blockchain"},
		DisableFlagsInUseLine: true,
		Args:                  cobra.MinimumNArgs(1),
		Run: func(cmd *cobra.Command, args []string) {
			return
		},
	}
	cmd.AddCommand(cli.buildAddBCCmd())
	cmd.AddCommand(cli.buildUpdateBCCmd())
	cmd.AddCommand(cli.buildDeleteBCCmd())
	cmd.AddCommand(cli.buildListBCCmd())

	return cmd
}

func (cli *CLI) buildListBCCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:                   "list",
		Short:                 "List all pairs",
		DisableFlagsInUseLine: true,
		Run: func(cmd *cobra.Command, args []string) {

			// 0: address

			// 1: attribute

			// ok, try to get token base info on-chain
			all := viper.AllSettings()
			allJson, err := json.Marshal(&all)
			if err != nil {
				fmt.Println(err)
				return
			}

			var b api.Tunnel
			err = json.Unmarshal(allJson, &b)
			if err != nil {
				fmt.Println(err)
				return
			}

			if b.DB.Adapter != "mysql" {
				fmt.Println("Not support db")
				return
			}

			sess, err := database.OpenDatabase("mysql", b.DB.ConnectionURL)
			if err != nil {
				fmt.Println(err)
				return
			}

			var bcList []database.Blockchain
			err = sess.SQL().SelectFrom("blockchains").All(&bcList)
			if errors.Is(err, db.ErrNoMoreRows) {
				fmt.Println("No blockchain")
				return
			} else if err != nil {
				fmt.Println(err)
				return
			}

			writer := tabwriter.NewWriter(os.Stdout, 0, 0, 2, ' ', tabwriter.Debug)
			fmt.Fprintln(writer, "Id\tNetwork\tChainId\tBaseChain\tArgs(Add|Update)")
			fmt.Fprintln(writer, "--\t-------\t--------\t--------\t--------")

			for _, bc := range bcList {
				baseChain := blockchain.Parse(bc.BaseChain).String()
				fmt.Fprintln(writer, fmt.Sprintf("%d\t%s\t%s\t%s\t%s",
					bc.Id, bc.Network, bc.ChainId, baseChain,
					fmt.Sprintf("%s %s %s", bc.Network, bc.ChainId, baseChain)))

				// fmt.Printf("======== %d ========\n", bc.Id)
				// fmt.Println("Network: ", bc.Network)
				// fmt.Println("ChainId: ", bc.ChainId)
				// fmt.Println("BaseChain: ", bc.BaseChain)
				//
				// fmt.Printf("Args: %s %s %s\n", bc.Network, bc.ChainId, bc.BaseChain)
			}
			writer.Flush()

			return
		},
	}

	return cmd
}

func (cli *CLI) buildAddBCCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "add <network> <chainId> <BaseChain>",
		Short: "Add a blockchain",
		Example: `add Bitcoin main Bitcoin
add Ethereum 1 Ethereum
add Newton 1012 NewChain
add Dogelayer 9888 Ethereum`,
		Args:                  cobra.MinimumNArgs(3),
		DisableFlagsInUseLine: true,
		Run: func(cmd *cobra.Command, args []string) {
			network := args[0]
			chainId := args[1]
			baseChainStr := args[2]

			baseChain := blockchain.Parse(baseChainStr)
			if baseChain == blockchain.UnknownChain {
				fmt.Println("Unknown base chain")
				return
			}

			if baseChain == blockchain.Ethereum || baseChain == blockchain.NewChain {
				// evm
				chainIdBig, ok := big.NewInt(0).SetString(chainId, 10)
				if !ok {
					fmt.Println("For evm, convert chainId to big int error")
					return
				}
				if chainId != chainIdBig.String() {
					fmt.Println("ChainId error: ", chainId, chainIdBig.String())
					return
				}
			}

			fmt.Println("Network: ", network)
			fmt.Println("ChainId: ", chainId)
			fmt.Println("BaseChain: ", baseChainStr)

			// ok, args check pass

			// database
			all := viper.AllSettings()
			allJson, err := json.Marshal(&all)
			if err != nil {
				fmt.Println(err)
				return
			}

			var b api.Tunnel
			err = json.Unmarshal(allJson, &b)
			if err != nil {
				fmt.Println(err)
				return
			}

			if b.DB.Adapter != "mysql" {
				fmt.Println("Not support db")
				return
			}

			sess, err := database.OpenDatabase("mysql", b.DB.ConnectionURL)
			if err != nil {
				fmt.Println(err)
				return
			}

			// check add
			var idList database.Blockchain
			err = sess.SQL().Select("id").From("blockchains").Where(
				"network", network).And("chain_id", chainId).One(&idList)
			if errors.Is(err, db.ErrNoMoreRows) {

			} else if err != nil {
				fmt.Println(err)
				return
			} else {
				fmt.Println("Pair existed, use `update`")
				return
			}

			result, err := sess.SQL().InsertInto("blockchains").Columns(
				"network", "chain_id", "base_chain").Values(
				network, chainId, baseChain.String()).Exec()
			if err != nil {
				fmt.Println(err)
				return
			}
			id, err := result.LastInsertId()
			if err != nil {
				fmt.Println(err)
				return
			}
			fmt.Println("Blockchain added: ", id)

		},
	}

	return cmd
}

func (cli *CLI) buildUpdateBCCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "update <id> <network> <chainId> <BaseChain>",
		Short: "Update a blockchain base on id",
		Example: `update 1 Bitcoin main Bitcoin
update 2 Ethereum 1 Ethereum
update 3 Newton 1012 NewChain
update 4 Dogelayer 9888 Ethereum`,
		Args:                  cobra.MinimumNArgs(4),
		DisableFlagsInUseLine: true,
		Run: func(cmd *cobra.Command, args []string) {
			idStr := args[0]
			network := args[1]
			chainId := args[2]
			baseChainStr := args[3]

			id, err := strconv.ParseUint(idStr, 10, 64)
			if err != nil {
				fmt.Println("Parse id error: ", err)
				return
			}

			baseChain := blockchain.Parse(baseChainStr)
			if baseChain == blockchain.UnknownChain {
				fmt.Println("Unknown base chain")
				return
			}

			if baseChain == blockchain.Ethereum || baseChain == blockchain.NewChain {
				// evm
				chainIdBig, ok := big.NewInt(0).SetString(chainId, 10)
				if !ok {
					fmt.Println("For evm, convert chainId to big int error")
					return
				}
				if chainId != chainIdBig.String() {
					fmt.Println("ChainId error: ", chainId, chainIdBig.String())
					return
				}
			}

			fmt.Println("=== INPUT ===")
			fmt.Println("Id: ", id)
			fmt.Println("Network: ", network)
			fmt.Println("ChainId: ", chainId)
			fmt.Println("BaseChain: ", baseChainStr)

			// ok, args check pass

			// database
			all := viper.AllSettings()
			allJson, err := json.Marshal(&all)
			if err != nil {
				fmt.Println(err)
				return
			}

			var b api.Tunnel
			err = json.Unmarshal(allJson, &b)
			if err != nil {
				fmt.Println(err)
				return
			}

			if b.DB.Adapter != "mysql" {
				fmt.Println("Not support db")
				return
			}

			sess, err := database.OpenDatabase("mysql", b.DB.ConnectionURL)
			if err != nil {
				fmt.Println(err)
				return
			}

			// check add
			var idList database.Blockchain
			err = sess.SQL().SelectFrom("blockchains").Where(
				"id", id).One(&idList)
			if errors.Is(err, db.ErrNoMoreRows) {
				fmt.Println("No such blockchain")
				return
			} else if err != nil {
				fmt.Println(err)
				return
			}

			{
				dbBaseChain := blockchain.Parse(idList.BaseChain)
				if dbBaseChain == blockchain.UnknownChain {
					fmt.Println("Database Unknown base chain")
					// return
				}

				if dbBaseChain == blockchain.Ethereum || dbBaseChain == blockchain.NewChain {
					// evm
					chainIdBig, ok := big.NewInt(0).SetString(idList.ChainId, 10)
					if !ok {
						fmt.Println("For evm, convert chainId to big int error")
						// return
					} else {
						if idList.ChainId != chainIdBig.String() {
							fmt.Println("ChainId error: ", idList.ChainId, chainIdBig.String())
							// return
						}
					}
				}

				fmt.Println("=== DATABASE ===")
				fmt.Println("Id: ", id)
				fmt.Println("Network: ", idList.Network)
				fmt.Println("ChainId: ", idList.ChainId)
				fmt.Println("BaseChain: ", dbBaseChain.String())
			}

			_, err = sess.SQL().Update("blockchains").Set(
				"network", network).Set(
				"chain_id", chainId).Set(
				"base_chain", baseChain.String()).Where(
				"id", id).Exec()
			if err != nil {
				fmt.Println(err)
				return
			}

			fmt.Println("Blockchain updated")
		},
	}

	return cmd
}

func (cli *CLI) buildDeleteBCCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:                   "delete <blockchain_id> <network> <chain_id>",
		Short:                 "delete the blockchain",
		Args:                  cobra.MinimumNArgs(3),
		DisableFlagsInUseLine: true,
		Run: func(cmd *cobra.Command, args []string) {

			idStr := args[0]
			network := args[1]
			chainId := args[2]

			id, err := strconv.ParseUint(idStr, 10, 64)
			if err != nil {
				fmt.Println("Parse id error: ", err)
				return
			}

			fmt.Println("=== INPUT ===")
			fmt.Println("Id: ", id)
			fmt.Println("Network: ", network)
			fmt.Println("ChainId: ", chainId)

			// ok, args check pass

			// database
			all := viper.AllSettings()
			allJson, err := json.Marshal(&all)
			if err != nil {
				fmt.Println(err)
				return
			}

			var b api.Tunnel
			err = json.Unmarshal(allJson, &b)
			if err != nil {
				fmt.Println(err)
				return
			}

			if b.DB.Adapter != "mysql" {
				fmt.Println("Not support db")
				return
			}

			sess, err := database.OpenDatabase("mysql", b.DB.ConnectionURL)
			if err != nil {
				fmt.Println(err)
				return
			}

			// check add
			var idList database.Blockchain
			err = sess.SQL().SelectFrom("blockchains").Where(
				"id", id).And(
				"network", network).And(
				"chain_id", chainId).One(&idList)
			if errors.Is(err, db.ErrNoMoreRows) {
				fmt.Println("No such blockchain")
				return
			} else if err != nil {
				fmt.Println(err)
				return
			}

			// ok, check assets with this blockchain
			var asset database.Asset
			err = sess.SQL().SelectFrom("assets").Where(
				"blockchain_id", id).One(&asset)
			if errors.Is(err, db.ErrNoMoreRows) {

			} else if err != nil {
				fmt.Println(err)
				return
			} else {
				fmt.Println("delete assets with this blockchain id first")
				return
			}

			// ok, all pass, delete

			_, err = sess.SQL().DeleteFrom("blockchains").Where(
				"id", id).And(
				"network", network).And(
				"chain_id", chainId).Exec()
			if err != nil {
				fmt.Println(err)
				return
			}

			fmt.Println("Blockchain deleted")

		},
	}

	return cmd
}
