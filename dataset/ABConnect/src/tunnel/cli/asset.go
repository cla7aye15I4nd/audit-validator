package cli

import (
	"context"
	"encoding/json"
	"fmt"
	"strconv"
	"strings"

	"github.com/ethereum/go-ethereum/common"
	"github.com/spf13/cobra"
	"github.com/spf13/viper"
	"github.com/upper/db/v4"
	"gitlab.weinvent.org/yangchenzhong/tunnel/api"
	"gitlab.weinvent.org/yangchenzhong/tunnel/blockchain"
	"gitlab.weinvent.org/yangchenzhong/tunnel/database"
	"gitlab.weinvent.org/yangchenzhong/tunnel/proto/chainapi"
	"gitlab.weinvent.org/yangchenzhong/tunnel/utils"
	"gitlab.weinvent.org/yangchenzhong/tunnel/utils/config"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
)

func (cli *CLI) buildAssetCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:                   "asset <add|delete|list>",
		Short:                 "Manager asset",
		DisableFlagsInUseLine: true,
		Args:                  cobra.MinimumNArgs(1),
		Run: func(cmd *cobra.Command, args []string) {
			return
		},
	}
	cmd.AddCommand(cli.buildAddAssetCmd())
	// cmd.AddCommand(cli.buildUpdateAssetCmd())
	cmd.AddCommand(cli.buildDeleteAssetCmd())
	cmd.AddCommand(cli.buildListAssetCmd())

	return cmd
}

func (cli *CLI) buildListAssetCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:                   "list",
		Short:                 "List all assets",
		DisableFlagsInUseLine: true,
		Run: func(cmd *cobra.Command, args []string) {

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

			s := sess.SQL().Select(
				"a.*",
				"b.network AS network",
				"b.chain_id AS chain_id",
				"b.base_chain AS base_chain",
			).From("assets a").
				LeftJoin("blockchains b").On("a.blockchain_id = b.id")

			var assetsList []database.AssetDetail
			if err := s.All(&assetsList); err != nil {
				fmt.Println(err)
				return
			}

			for _, a := range assetsList {

				baseChain := blockchain.Parse(a.BaseChain)
				if baseChain == blockchain.UnknownChain {
					fmt.Println("Asset BaseChain unknown")
					return
				}

				asset := a.Asset.Asset
				if asset != "" && (baseChain == blockchain.Ethereum || baseChain == blockchain.NewChain) {
					if !common.IsHexAddress(asset) {
						fmt.Println("Asset A invalid address")
					}
					asset = common.HexToAddress(asset).String()
				}

				attribute := a.Attribute
				var attributeTextList []string
				if attribute&utils.AttributeMintable == utils.AttributeMintable {
					attributeTextList = append(attributeTextList, "mint")
				}
				if attribute&utils.AttributeBurnable == utils.AttributeBurnable {
					attributeTextList = append(attributeTextList, "burn")
				}
				if len(attributeTextList) == 0 {
					attributeTextList = append(attributeTextList, "transfer")
				}
				attributeText := strings.Join(attributeTextList, ",")

				addArgs := fmt.Sprintf("%d:%s:%s:%s:%d:%s:%s",
					a.BlockchainId,
					asset, a.Name, a.Symbol, a.Decimals, attributeText,
					a.AssetType)
				if strings.Contains(addArgs, " ") {
					addArgs = fmt.Sprintf("\"%s\"", addArgs)
				}

				fmt.Printf("================ %d ================\n", a.ID)
				fmt.Println("Asset: ", asset)
				fmt.Println("Name: ", a.Name)
				fmt.Println("Symbol: ", a.Symbol)
				fmt.Println("Decimals: ", a.Decimals)
				fmt.Println("Attribute: ", attributeText)
				fmt.Println("AssetType: ", a.AssetType)

				fmt.Println("BlockchainId: ", a.BlockchainId)
				fmt.Println("Network: ", a.Network)
				fmt.Println("ChainId: ", a.ChainId)
				fmt.Println("BaseChain: ", baseChain.String())

				fmt.Printf("Args: add %s\n", addArgs)
			}

			return
		},
	}

	return cmd
}

func (cli *CLI) buildAddAssetCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "add <BlockchainId:AssetTickOrTokenAddress:Slug:Symbol:Decimals:attribute:AssetType>",
		Short: "Add a asset",
		Example: `add 1::Newton:NEW:18:transfer:Coin
add 2::Ethereum:ETH:18:transfer:Coin
add 3::Bitcoin:BTC:8:transfer:Coin
add "6:0x9Fc54AAAd8ED0085CAE87e1c94F2b19eE10a1653:Tether USD:USDT:6:transfer:ERC20"
add 6:0x9Fc54AAAd8ED0085CAE87e1c94F2b19eE10a1653::::transfer:ERC20`,
		Args:                  cobra.MinimumNArgs(1),
		DisableFlagsInUseLine: true,
		Run: func(cmd *cobra.Command, args []string) {
			// cli.handlePair(cmd, args, PairAdd)

			sep := ":"
			if len(args) > 1 {
				sep = "args[1]"
			}
			list := strings.Split(args[0], sep)
			if len(list) < 6 {
				fmt.Println("asset parse error")
				return
			}

			// 		Use:   "add <BlockchainId:AssetTickOrTokenAddress:Slug:Symbol:Decimals:attribute:AssetType>",
			bcId, err := strconv.ParseUint(list[0], 10, 64)
			if err != nil {
				fmt.Println("Parse blockchain id error: ", err)
				return
			}

			asset := list[1]
			name := list[2]
			symbol := list[3]

			decimalsStr := list[4]
			decimals := uint8(0)
			if decimalsStr != "" {
				decimals64, err := strconv.ParseUint(decimalsStr, 10, 8)
				if err != nil {
					fmt.Println("Parse decimals error: ", err)
					return
				}
				decimals = uint8(decimals64)
			}

			var (
				attributeStr = list[5]
				attribute    uint
			)
			attributeList := strings.Split(strings.ToLower(attributeStr), ",")
			var attributeTextList []string
			for _, a := range attributeList {
				if a == "mint" {
					attribute |= utils.AttributeMintable
					attributeTextList = append(attributeTextList, "mint")
				} else if a == "burn" {
					attribute |= utils.AttributeBurnable
					attributeTextList = append(attributeTextList, "burn")
				} else if a == "" || a == "transfer" {
					attributeTextList = append(attributeTextList, "transfer")
				} else {
					fmt.Println("not support attribute: ", a)
					return
				}
			}
			attributeText := strings.Join(attributeTextList, ",")

			assetType := ""
			if len(list) > 6 {
				assetType = list[6]
			}

			fmt.Println("=== INPUT ===")
			fmt.Println("BlockchainId: ", bcId)
			fmt.Println("Asset: ", asset)
			fmt.Println("Slug: ", name)
			fmt.Println("Symbol: ", symbol)
			fmt.Println("Decimals: ", decimals)
			fmt.Println("Attribute: ", attributeText)
			fmt.Println("AssetType: ", assetType)

			// ok, args pass, check db

			// TODO: how to get token base info on-chain
			cb, err := loadBridge()
			if err != nil {
				fmt.Println(err)
				return
			}

			if cb.DB.Adapter != "mysql" {
				fmt.Println("Not support db")
				return
			}

			sess, err := database.OpenDatabase("mysql", cb.DB.ConnectionURL)
			if err != nil {
				fmt.Println(err)
				return
			}
			defer sess.Close()

			bcExists, err := sess.Collection("blockchains").Find("id", bcId).Exists()
			if err != nil {
				fmt.Println(err)
				return
			}
			if !bcExists {
				fmt.Println("No such blockchain")
				return
			}

			if asset != "" {
				// check base info
				r := api.New(cb, cb.DB)
				if r == nil {
					fmt.Println("Create router error")
					return
				}
				if err := r.Init(); err != nil {
					fmt.Println(err)
					return
				}

				var (
					baseChain blockchain.BlockChain
				)
				var cBC *config.ChainConfig
				for _, bc := range r.Blockchains {
					if bc.BlockchainId == bcId {
						baseChain = bc.BaseChain
						cBC = bc
						break
					}
				}

				if baseChain == blockchain.UnknownChain {
					fmt.Println("Unknown chain, please add blockchain to config file")
					return
				}

				conn, err := grpc.NewClient(cBC.ChainAPIHost, grpc.WithTransportCredentials(insecure.NewCredentials()))
				if err != nil {
					fmt.Println(err)
					return
				}
				client := chainapi.NewChainAPIClient(conn)
				ctx := context.Background()

				chainInfo, err := client.GetChainInfo(ctx, &chainapi.ChainInfoRequest{})
				if err != nil {
					fmt.Println(err)
					return
				}
				assetInfo, err := client.GetAssetInfo(ctx, &chainapi.AssetInfoRequest{Asset: asset})
				if err != nil {
					fmt.Println(err)
					return
				}

				chainId := chainInfo.ChainId
				if err != nil {
					fmt.Println(err)
					return
				}
				if chainId != cBC.ChainId {
					fmt.Printf("ChainId not match, from RpcURL is %v but config is %v\n",
						chainId, cBC.ChainId)
					return
				}

				tokenName := assetInfo.Name
				if name == "" {
					name = tokenName
				} else {
					if tokenName != name {
						fmt.Printf("Token name not same, change from %s to %s\n",
							name, tokenName)
						name = tokenName
					}
				}

				tokenSymbol := assetInfo.Symbol
				if symbol == "" {
					symbol = tokenSymbol
				} else {
					if tokenSymbol != symbol {
						fmt.Printf("Token symbol not same, change from %s to %s\n",
							symbol, tokenSymbol)
						symbol = tokenSymbol
					}
				}

				tokenDecimals := uint8(assetInfo.Decimals)
				if tokenDecimals != decimals {
					fmt.Printf("Token decimals not same, change from %v to %v\n",
						decimals, tokenDecimals)
					decimals = tokenDecimals
				}

				fmt.Println("=== after ON-CHAIN repair ===")
				fmt.Println("BlockchainId: ", bcId)
				fmt.Println("Asset: ", asset)
				fmt.Println("Slug: ", name)
				fmt.Println("Symbol: ", symbol)
				fmt.Println("Decimals: ", decimals)
				fmt.Println("Attribute: ", attributeText)
				fmt.Println("AssetType: ", assetType)

			}

			if name == "" || symbol == "" {
				fmt.Println("Asset's name or symbol empty, please re-add")
				return
			}
			if decimals == 0 {
				fmt.Println("Decimals is 0")
			}

			yes, _ := cmd.Flags().GetBool("yes")
			if !yes && !utils.Confirm() {
				return
			}

			_, err = sess.SQL().InsertInto("assets").Columns(
				"blockchain_id",
				"asset", "name", "symbol", "decimals", "attribute", "asset_type").Values(
				bcId, asset, name, symbol, decimals, attribute, assetType).Exec()

			if err != nil {
				fmt.Println(err)
				return
			}

			fmt.Println("Asset added")
		},
	}

	cmd.Flags().Bool("yes", false, "confirm action without recheck")

	return cmd
}

func (cli *CLI) buildDeleteAssetCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:                   "delete <AssetId> <BlockchainId> <Asset>",
		Short:                 "delete the pair",
		Args:                  cobra.MinimumNArgs(3),
		DisableFlagsInUseLine: true,
		Run: func(cmd *cobra.Command, args []string) {

			assetIdStr := args[0]
			bcIdStr := args[1]
			asset := args[2]

			id, err := strconv.ParseUint(assetIdStr, 10, 64)
			if err != nil {
				fmt.Println("Parse id error: ", err)
				return
			}

			bcId, err := strconv.ParseUint(bcIdStr, 10, 64)
			if err != nil {
				fmt.Println("Parse id error: ", err)
				return
			}

			fmt.Println("=== INPUT ===")
			fmt.Println("AssetID: ", id)
			fmt.Println("BlockchainId: ", bcId)
			fmt.Println("Asset: ", asset)

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

			// check exists
			aExists, err := sess.Collection("assets").Find(db.Cond{
				"id":            id,
				"blockchain_id": bcId,
				"asset":         asset,
			}).Exists()
			if err != nil {
				fmt.Println(err)
				return
			}
			if !aExists {
				fmt.Println("No such asset, no need to delete")
				return
			}

			// ok, check assets with this blockchain

			pairExists, err := sess.Collection("pairs").Find(db.Or(
				db.Cond{"asset_a_id": id},
				db.Cond{"asset_b_id": id},
			)).Exists()
			if err != nil {
				fmt.Println(err)
				return
			}
			if pairExists {
				fmt.Println("delete pairs with this asset id first")
				return
			}

			// ok, all pass, delete

			_, err = sess.SQL().DeleteFrom("assets").Where(
				"id", id).And(
				"blockchain_id", bcId).And(
				"asset", asset).Exec()
			if err != nil {
				fmt.Println(err)
				return
			}

			fmt.Println("Asset deleted")
		},
	}

	return cmd
}
