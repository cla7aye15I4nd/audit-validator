package cli

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"math/big"
	"strconv"
	"strings"

	"github.com/btcsuite/btcd/rpcclient"
	dbtcutil "github.com/dogecoinw/doged/btcutil"
	dchaincfg "github.com/dogecoinw/doged/chaincfg"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/ethclient"
	"github.com/shopspring/decimal"
	"github.com/spf13/cobra"
	"github.com/spf13/viper"
	"github.com/upper/db/v4"
	"gitlab.weinvent.org/yangchenzhong/tunnel/blockchain"
	"gitlab.weinvent.org/yangchenzhong/tunnel/database"
	"gitlab.weinvent.org/yangchenzhong/tunnel/proto/chainapi"
	"gitlab.weinvent.org/yangchenzhong/tunnel/utils"
	"gitlab.weinvent.org/yangchenzhong/tunnel/utils/coins/tron"
	"gitlab.weinvent.org/yangchenzhong/tunnel/utils/config"
	"google.golang.org/grpc"
)

func (cli *CLI) buildPairCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:                   "pair <add|list>",
		Short:                 "Manager pair",
		DisableFlagsInUseLine: true,
		Args:                  cobra.MinimumNArgs(1),
		Run: func(cmd *cobra.Command, args []string) {
			return
		},
	}
	cmd.AddCommand(cli.buildAddPairCmd())
	cmd.AddCommand(cli.buildUpdatePairCmd())
	// cmd.AddCommand(cli.buildDeletePairCmd())
	cmd.AddCommand(cli.buildListPairCmd())

	return cmd
}

func (cli *CLI) buildListPairCmd() *cobra.Command {
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

			var b config.Bridge
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

			s := sess.SQL().Select("p.*",
				"a1.asset AS asset_a_asset",
				"a1.name AS asset_a_name",
				"a1.symbol AS asset_a_symbol",
				"a1.decimals AS asset_a_decimals",
				"a1.asset_type AS asset_a_asset_type",
				"a1.attribute AS asset_a_attribute",
				"b1.network AS asset_a_network",
				"b1.chain_id AS asset_a_chain_id",
				"b1.base_chain AS asset_a_base_chain",
				"a2.asset AS asset_b_asset",
				"a2.name AS asset_b_name",
				"a2.symbol AS asset_b_symbol",
				"a2.decimals AS asset_b_decimals",
				"a2.asset_type AS asset_b_asset_type",
				"a2.attribute AS asset_b_attribute",
				"b2.network AS asset_b_network",
				"b2.chain_id AS asset_b_chain_id",
				"b2.base_chain AS asset_b_base_chain").From("pairs p").
				LeftJoin("assets a1").On("p.asset_a_id = a1.id").
				LeftJoin("blockchains b1").On("a1.blockchain_id = b1.id").
				LeftJoin("assets a2").On("p.asset_b_id = a2.id").
				LeftJoin("blockchains b2").On("a2.blockchain_id = b2.id")

			var pairsList []database.PairDetail
			if err := s.All(&pairsList); err != nil {
				fmt.Println(err)
				return
			}

			for _, pair := range pairsList {

				aBaseChain := blockchain.Parse(pair.AssetABaseChain)
				if aBaseChain == blockchain.UnknownChain {
					fmt.Println("Asset A BaseChain unknown")
					return
				}
				bBaseChain := blockchain.Parse(pair.AssetBBaseChain)
				if bBaseChain == blockchain.UnknownChain {
					fmt.Println("Asset B BaseChain unknown")
					return
				}

				assetAAsset := pair.AssetAAsset
				if assetAAsset != "" {
					if aBaseChain == blockchain.Ethereum {
						if !common.IsHexAddress(assetAAsset) {
							fmt.Println("Asset A invalid address")
						}
						assetAAsset = common.HexToAddress(assetAAsset).String()
					} else if aBaseChain == blockchain.Tron {
						address, err := tron.NewAddress(assetAAsset)
						if err != nil {
							fmt.Println("Asset A invalid address")
						}
						assetAAsset = address.String()
					}
				}

				assetBAsset := pair.AssetBAsset
				if assetBAsset != "" {
					if bBaseChain == blockchain.Ethereum {
						if !common.IsHexAddress(assetBAsset) {
							fmt.Println("Asset A invalid address")
						}
						assetBAsset = common.HexToAddress(assetBAsset).String()
					} else if bBaseChain == blockchain.Tron {
						address, err := tron.NewAddress(assetBAsset)
						if err != nil {
							fmt.Println("Asset A invalid address")
						}
						assetBAsset = address.String()
					}
				}

				aAttribute := pair.AssetAAttribute
				bAttribute := pair.AssetBAttribute

				var aAttributeTextList []string
				if aAttribute&utils.AttributeMintable == utils.AttributeMintable {
					aAttributeTextList = append(aAttributeTextList, "mint")
				}
				if aAttribute&utils.AttributeBurnable == utils.AttributeBurnable {
					aAttributeTextList = append(aAttributeTextList, "burn")
				}
				if len(aAttributeTextList) == 0 {
					aAttributeTextList = append(aAttributeTextList, "transfer")
				}
				aAttributeText := strings.Join(aAttributeTextList, ",")

				var bAttributeTextList []string
				if bAttribute&utils.AttributeMintable == utils.AttributeMintable {
					bAttributeTextList = append(bAttributeTextList, "mint")
				}
				if bAttribute&utils.AttributeBurnable == utils.AttributeBurnable {
					bAttributeTextList = append(bAttributeTextList, "burn")
				}
				if len(bAttributeTextList) == 0 {
					bAttributeTextList = append(bAttributeTextList, "transfer")
				}
				bAttributeText := strings.Join(bAttributeTextList, ",")

				var (
					aName     = pair.AssetAName
					aSymbol   = pair.AssetASymbol
					aDecimals = pair.AssetADecimals
					bName     = pair.AssetBName
					bSymbol   = pair.AssetBSymbol
					bDecimals = pair.AssetBDecimals

					aNetwork = pair.AssetANetwork
					aChainId = pair.AssetAChainId
					bNetwork = pair.AssetBNetwork
					bChainId = pair.AssetBChainId
				)

				// 2: minDepositAmountInDecimals
				aMinDepositAmount, ok := big.NewInt(0).SetString(pair.AssetAMinDepositAmount, 10)
				if !ok {
					fmt.Println("AssetAMinDepositAmount to big int error: ", pair.Id)
					return
				}
				bMinDepositAmount, ok := big.NewInt(0).SetString(pair.AssetBMinDepositAmount, 10)
				if !ok {
					fmt.Println("AssetBMinDepositAmount to big int error: ", pair.Id)
					return
				}

				// 3: withdrawFeePercent
				// fee percent
				aFeePercent := int64(pair.AssetAWithdrawFeePercent)
				bFeePercent := int64(pair.AssetBWithdrawFeePercent)

				// 4: withdrawFeeMinInDecimals
				// fee min base
				aWithdrawFeeMin, ok := big.NewInt(0).SetString(pair.AssetAWithdrawFeeMin, 10)
				if !ok {
					fmt.Println("AssetAWithdrawFeeMin to big int error: ", pair.Id)
					return
				}
				bWithdrawFeeMin, ok := big.NewInt(0).SetString(pair.AssetBWithdrawFeeMin, 10)
				if !ok {
					fmt.Println("AssetBWithdrawFeeMin to big int error: ", pair.Id)
					return
				}

				// 5: AutoConfirmAmount
				dogeAutoConfirmAmount := big.NewInt(0)
				if pair.AssetAAutoConfirmDepositAmount != "" {
					_, ok = dogeAutoConfirmAmount.SetString(pair.AssetAAutoConfirmDepositAmount, 10)
					if !ok {
						fmt.Println("AssetAAutoConfirmDepositAmount to big int error: ", pair.Id)
						return
					}
				}
				ethAutoConfirmAmount := big.NewInt(0)
				if pair.AssetBAutoConfirmDepositAmount != "" {
					_, ok = ethAutoConfirmAmount.SetString(pair.AssetBAutoConfirmDepositAmount, 10)
					if !ok {
						fmt.Println("AssetBAutoConfirmDepositAmount to big int error: ", pair.Id)
						return
					}
				}

				fmt.Printf("================ %d ================\n", pair.Id)
				fmt.Printf("AssetA(%d): %s\n", pair.AssetAId, assetAAsset)
				fmt.Printf("\tNetwork: %s(%s)\n", aNetwork, aChainId)
				fmt.Println("\tName: ", aName)
				fmt.Println("\tSymbol: ", aSymbol)
				fmt.Println("\tDecimals: ", aDecimals)
				fmt.Printf("\tMinDepositAmount: %v (%v %s)\n", aMinDepositAmount.String(), utils.GetAmountTextFromISAACWithDecimals(aMinDepositAmount, aDecimals), aSymbol)
				fmt.Printf("\tWithdrawFeePercent: %v/%v = %v\n", aFeePercent, utils.FeeBase, float64(aFeePercent)/float64(utils.FeeBase))
				fmt.Printf("\tWithdrawFeeMin: %v (%v %s)\n", aWithdrawFeeMin.String(), utils.GetAmountTextFromISAACWithDecimals(aWithdrawFeeMin, aDecimals), aSymbol)
				fmt.Println("\tAttribute: ", aAttributeText)
				fmt.Printf("\tAutoConfirmDepositAmount: %v (%v %s)\n", dogeAutoConfirmAmount.String(), utils.GetAmountTextFromISAACWithDecimals(dogeAutoConfirmAmount, aDecimals), aSymbol)

				fmt.Printf("AssetB(%d): %s\n", pair.AssetBId, assetBAsset)
				fmt.Printf("\tNetwork: %s(%s)\n", bNetwork, bChainId)
				fmt.Println("\tName: ", bName)
				fmt.Println("\tSymbol: ", bSymbol)
				fmt.Println("\tDecimals: ", bDecimals)
				fmt.Printf("\tMinDepositAmount: %v (%v %s)\n", bMinDepositAmount.String(), utils.GetAmountTextFromISAACWithDecimals(bMinDepositAmount, bDecimals), bSymbol)
				fmt.Printf("\tWithdrawFeePercent: %v/%v = %v\n", bFeePercent, utils.FeeBase, float64(bFeePercent)/float64(utils.FeeBase))
				fmt.Printf("\tWithdrawFeeMin: %v (%v %s)\n", bWithdrawFeeMin.String(), utils.GetAmountTextFromISAACWithDecimals(bWithdrawFeeMin, bDecimals), bSymbol)
				fmt.Println("\tAttribute: ", bAttributeText)
				fmt.Printf("\tAutoConfirmDepositAmount: %v (%v %s)\n", ethAutoConfirmAmount.String(), utils.GetAmountTextFromISAACWithDecimals(ethAutoConfirmAmount, bDecimals), bSymbol)

				dogeArgs := fmt.Sprintf("%d:%s:%v:%s:%s",
					pair.AssetAId,
					utils.GetAmountTextFromISAACWithDecimals(aMinDepositAmount, aDecimals),
					float64(aFeePercent)/float64(utils.FeeBase),
					utils.GetAmountTextFromISAACWithDecimals(aWithdrawFeeMin, aDecimals),
					utils.GetAmountTextFromISAACWithDecimals(dogeAutoConfirmAmount, aDecimals))
				ethArgs := fmt.Sprintf("%d:%s:%v:%s:%s",
					pair.AssetBId,
					utils.GetAmountTextFromISAACWithDecimals(bMinDepositAmount, bDecimals),
					float64(bFeePercent)/float64(utils.FeeBase),
					utils.GetAmountTextFromISAACWithDecimals(bWithdrawFeeMin, bDecimals),
					utils.GetAmountTextFromISAACWithDecimals(ethAutoConfirmAmount, bDecimals))

				fmt.Printf("Args: %s %s\n", dogeArgs, ethArgs)
			}

			return
		},
	}

	return cmd
}

func createInternalDogecoinAddress(name, target string) (dbtcutil.Address, error) {
	conn, err := grpc.Dial(target, grpc.WithInsecure())
	if err != nil {
		return nil, err
	}
	defer conn.Close()
	ec := chainapi.NewChainAPIClient(conn)

	accountReply, err := ec.CreateAccount(context.Background(),
		&chainapi.CreateAccountRequest{Name: name})
	if err != nil {
		return nil, err
	}

	return dbtcutil.DecodeAddress(accountReply.Address, &dchaincfg.MainNetParams)
}

func createInternalAddress(name, target string) (common.Address, error) {
	conn, err := grpc.Dial(target, grpc.WithInsecure())
	if err != nil {
		return common.Address{}, err
	}
	defer conn.Close()
	ec := chainapi.NewChainAPIClient(conn)

	accountReply, err := ec.CreateAccount(context.Background(),
		&chainapi.CreateAccountRequest{Name: name})
	if err != nil {
		return common.Address{}, err
	}
	if !common.IsHexAddress(accountReply.Address) {
		return common.Address{}, errors.New("internal address error")
	}
	return common.HexToAddress(accountReply.Address), nil
}

func getDogecoinNetworkName(target, user, pass string) (string, error) {
	connCfg := &rpcclient.ConnConfig{
		Host:         target,
		Endpoint:     "ws",
		User:         user,
		Pass:         pass,
		HTTPPostMode: true, // Bitcoin core only supports HTTP POST mode
		DisableTLS:   true, // Bitcoin core does not provide TLS by default
	}

	// Notice the notification parameter is nil since notifications are
	rpcClient, err := rpcclient.New(connCfg, nil)
	if err != nil {
		fmt.Println(err)
		return "", err
	}

	dogeInfo, err := rpcClient.GetBlockChainInfo()
	if err != nil {
		fmt.Println(err)
		return "", err
	}

	return dogeInfo.Chain, nil
}

func getChainId(target string) (*big.Int, error) {
	client, err := ethclient.Dial(target)
	if err != nil {
		return nil, err
	}

	return client.ChainID(context.Background())
}

func (cli *CLI) buildAddPairCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "add <AssetIdA:minDepositAmountInDecimals:withdrawFeePercent:withdrawFeeMinInDecimals:AutoDepositConfirmAmountInDecimals> <AssetIdB:attribute:minDepositAmountInDecimals:withdrawFeePercent:withdrawFeeMinInDecimals:AutoDepositConfirmAmountInDecimals>",
		Short: "Add a pair",
		Example: `1:0:0.003:1:10 2:1000:0.003:1:10
13:0:0:0:100000000 14:0:0:0:100000000`,
		Args:                  cobra.ExactArgs(2),
		DisableFlagsInUseLine: true,
		Run: func(cmd *cobra.Command, args []string) {
			cli.handlePair(cmd, args, ActionAdd)
		},
	}

	return cmd
}

func (cli *CLI) buildUpdatePairCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:                   "update <PairID> <DRC20Tick:attribute:minDepositAmountInDecimals:withdrawFeePercent:withdrawFeeMinInDecimals> <EthereumToken:attribute:minDepositAmountInDecimals:withdrawFeePercent:withdrawFeeMinInDecimals>",
		Short:                 "update a pair",
		Args:                  cobra.ExactArgs(3),
		DisableFlagsInUseLine: true,
		Run: func(cmd *cobra.Command, args []string) {
			cli.handlePair(cmd, args, ActionUpdate)
		},
	}

	return cmd
}

func (cli *CLI) handlePair(cmd *cobra.Command, args []string, pairAction int) {
	if pairAction != ActionAdd && pairAction != ActionUpdate {
		fmt.Println("Not support Pair action")
		return
	}

	var (
		err error

		updatePairId uint64
	)
	if pairAction == ActionUpdate {
		updatePairId, err = strconv.ParseUint(args[0], 10, 64)
		if err != nil {
			fmt.Println("Parse id error: ", err)
			return
		}
		args = args[1:]
	}

	// assetId:minDepositAmountInDecimals:withdrawFeePercent:withdrawFeeMinInDecimals:autoConfirmDepositAmount

	// 13:0:0:0:100000000 14:0:0:0:100000000

	aList := strings.Split(args[0], ":")
	bList := strings.Split(args[1], ":")

	if len(aList) != 5 {
		fmt.Println("args0 len error")
		return
	}
	if len(bList) != 5 {
		fmt.Println("args1 len error")
		return
	}

	// 0: asset id
	aId, err := strconv.ParseUint(aList[0], 10, 64)
	if err != nil {
		fmt.Println("Parse id error: ", err)
		return
	}

	bId, err := strconv.ParseUint(bList[0], 10, 64)
	if err != nil {
		fmt.Println("Parse id error: ", err)
		return
	}

	fmt.Printf("Asset a id is %d and asset b id is %d\n", aId, bId)

	if aId == 0 || bId == 0 {
		fmt.Println("Id is zero")
		return
	}

	if aId >= bId {
		fmt.Println("assetAId must be less then assetBId")
		return
	}

	// ok, try to get token base info on-chain
	all := viper.AllSettings()
	allJson, err := json.Marshal(&all)
	if err != nil {
		fmt.Println(err)
		return
	}

	var b config.Bridge
	err = json.Unmarshal(allJson, &b)
	if err != nil {
		fmt.Println(err)
		return
	}

	if b.ToolsSignKeyId == "" {
		fmt.Println("Tools sign key is empty")
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

	// check pairs exist
	if pairAction == ActionUpdate {
		pairExist, err := sess.Collection("pairs").Find(db.Cond{
			"id":         updatePairId,
			"asset_a_id": aId,
			"asset_b_id": bId,
		}).Exists()
		if err != nil {
			fmt.Println(err)
			return
		}
		if !pairExist {
			fmt.Printf("No pair for asset %d and asset %d to be updated\n", aId, bId)
			return
		}
	} else {
		pairExist, err := sess.Collection("pairs").Find(db.Cond{
			"asset_a_id": aId,
			"asset_b_id": bId,
		}).Exists()
		if err != nil {
			fmt.Println(err)
			return
		}
		if pairExist {
			fmt.Printf("Existing pair for asset %d and asset %d\n", aId, bId)
			return
		}
	}

	var assetList []database.AssetDetail

	s := sess.SQL().Select(
		"a.*",
		"b.network AS network",
		"b.chain_id AS chain_id",
		"b.base_chain AS base_chain",
	).From("assets a").LeftJoin(
		"blockchains b").On(
		"a.blockchain_id = b.id").Where(db.Or(
		db.Cond{"a.id": aId},
		db.Cond{"a.id": bId},
	)).OrderBy("a.id")
	if err := s.All(&assetList); err != nil {
		fmt.Println(err)
		return
	}

	if len(assetList) == 0 {
		fmt.Println("all asset not exist")
		return
	} else if len(assetList) == 1 {
		if assetList[0].ID == aId {
			fmt.Println("asset b not exist: ", bId)
			return
		} else {
			fmt.Println("asset a not exist: ", aId)
			return
		}
	}

	if assetList[0].ID != aId || assetList[1].ID != bId {
		fmt.Println("Asset not match")
		return
	}

	if assetList[0].BlockchainId == assetList[1].BlockchainId {
		fmt.Println("assets are the same blockchain")
		return
	}

	var (
		aAsset    = assetList[0].Asset.Asset
		aName     = assetList[0].Name
		aSymbol   = assetList[0].Symbol
		aDecimals = assetList[0].Decimals

		bAsset    = assetList[1].Asset.Asset
		bName     = assetList[1].Name
		bSymbol   = assetList[1].Symbol
		bDecimals = assetList[1].Decimals
	)

	// 2: minDepositAmountInDecimals
	aMinDepositAmount, err := utils.GetAmountISAACFromTextWithDecimals(aList[1], aDecimals)
	if err != nil {
		fmt.Println(err)
		return
	}
	bMinDepositAmount, err := utils.GetAmountISAACFromTextWithDecimals(bList[1], bDecimals)
	if err != nil {
		fmt.Println(err)
		return
	}

	// 3: withdrawFeePercent
	// fee percent
	var (
		aFeePercent = int64(0)
		bFeePercent = int64(0)
	)
	aFeePercentDecimal, err := decimal.NewFromString(aList[2])
	if err != nil {
		fmt.Println(err)
		return
	}
	aFeePercentDecimal = aFeePercentDecimal.Mul(decimal.NewFromInt(utils.FeeBase))
	aFeePercent = aFeePercentDecimal.IntPart()
	if aFeePercent < 0 || aFeePercent > utils.FeeBase {
		fmt.Println("Asset A fee percent error")
		return
	}

	bFeePercentDecimal, err := decimal.NewFromString(bList[2])
	if err != nil {
		fmt.Println(err)
		return
	}
	bFeePercentDecimal = bFeePercentDecimal.Mul(decimal.NewFromInt(utils.FeeBase))
	bFeePercent = bFeePercentDecimal.IntPart()
	if bFeePercent < 0 || bFeePercent > utils.FeeBase {
		fmt.Println("Asset B fee percent error")
		return
	}

	// 4: withdrawFeeMinInDecimals
	// fee min base
	aWithdrawFeeMin, err := utils.GetAmountISAACFromTextWithDecimals(aList[3], aDecimals)
	if err != nil {
		fmt.Println(err)
		return
	}
	bWithdrawFeeMin, err := utils.GetAmountISAACFromTextWithDecimals(bList[3], bDecimals)
	if err != nil {
		fmt.Println(err)
		return
	}

	// 5: autoConfirmDepositAmount
	aAutoConfirmDepositAmount := big.NewInt(0)
	if len(aList[4]) > 0 {
		aAutoConfirmDepositAmount, err = utils.GetAmountISAACFromTextWithDecimals(aList[4], aDecimals)
		if err != nil {
			fmt.Println(err)
			return
		}
	}
	bAutoConfirmDepositAmount := big.NewInt(0)
	if len(bList[4]) > 0 {
		bAutoConfirmDepositAmount, err = utils.GetAmountISAACFromTextWithDecimals(bList[4], bDecimals)
		if err != nil {
			fmt.Println(err)
			return
		}
	}

	// TODO: add WithdrawMainAddress as minter and burner

	fmt.Println("Asset A: ", aId)
	if aAsset == "" {
		fmt.Println("\tAsset: (native coin)")
	} else {
		fmt.Println("\tAsset: ", aAsset)
	}
	fmt.Println("\tName: ", aName)
	fmt.Println("\tSymbol: ", aSymbol)
	fmt.Println("\tDecimals: ", aDecimals)
	fmt.Println("\tAssetType: ", assetList[0].AssetType)
	fmt.Printf("\tMinDepositAmount: %v (%v %s)\n", aMinDepositAmount.String(), utils.GetAmountTextFromISAACWithDecimals(aMinDepositAmount, aDecimals), aSymbol)
	fmt.Printf("\tWithdrawFeePercent: %v/%v = %v\n", aFeePercent, utils.FeeBase, float64(aFeePercent)/float64(utils.FeeBase))
	fmt.Printf("\tWithdrawFeeMin: %v (%v %s)\n", aWithdrawFeeMin.String(), utils.GetAmountTextFromISAACWithDecimals(aWithdrawFeeMin, aDecimals), aSymbol)
	fmt.Printf("\tAutoConfirmDepositAmount: %v (%v %s)\n", aAutoConfirmDepositAmount.String(), utils.GetAmountTextFromISAACWithDecimals(aAutoConfirmDepositAmount, aDecimals), aSymbol)
	fmt.Println("\tNetwork: ", assetList[0].Network)
	fmt.Println("\tChainId: ", assetList[0].ChainId)

	fmt.Println("Asset B: ", bId)
	if bAsset == "" {
		fmt.Println("\tAsset: (native coin)")
	} else {
		fmt.Println("\tAsset: ", bAsset)
	}
	fmt.Println("\tName: ", bName)
	fmt.Println("\tSymbol: ", bSymbol)
	fmt.Println("\tDecimals: ", bDecimals)
	fmt.Println("\tAssetType: ", assetList[1].AssetType)
	fmt.Printf("\tMinDepositAmount: %v (%v %s)\n", bMinDepositAmount.String(), utils.GetAmountTextFromISAACWithDecimals(bMinDepositAmount, bDecimals), bSymbol)
	fmt.Printf("\tWithdrawFeePercent: %v/%v = %v\n", bFeePercent, utils.FeeBase, float64(bFeePercent)/float64(utils.FeeBase))
	fmt.Printf("\tWithdrawFeeMin: %v (%v %s)\n", bWithdrawFeeMin.String(), utils.GetAmountTextFromISAACWithDecimals(bWithdrawFeeMin, bDecimals), bSymbol)
	fmt.Printf("\tAutoConfirmDepositAmount: %v (%v %s)\n", bAutoConfirmDepositAmount.String(), utils.GetAmountTextFromISAACWithDecimals(bAutoConfirmDepositAmount, bDecimals), bSymbol)
	fmt.Println("\tNetwork: ", assetList[1].Network)
	fmt.Println("\tChainId: ", assetList[1].ChainId)

	// check decimals
	if aDecimals != bDecimals {
		log.Warnln("Decimals not match...")
	}

	yes, _ := cmd.Flags().GetBool("yes")
	if !yes && !utils.Confirm() {
		fmt.Println("Canceled.")
		return
	}

	// ok,

	// check add

	if pairAction == ActionUpdate {
		err = sess.Tx(func(dbTx db.Session) error {
			_, err = dbTx.SQL().Update("pairs").Set(map[string]interface{}{
				"asset_a_min_deposit_amount":          aMinDepositAmount.String(),
				"asset_b_min_deposit_amount":          bMinDepositAmount.String(),
				"asset_a_withdraw_fee_percent":        aFeePercent,
				"asset_b_withdraw_fee_percent":        bFeePercent,
				"asset_a_withdraw_fee_min":            aWithdrawFeeMin.String(),
				"asset_b_withdraw_fee_min":            bWithdrawFeeMin.String(),
				"asset_a_auto_confirm_deposit_amount": aAutoConfirmDepositAmount.String(),
				"asset_b_auto_confirm_deposit_amount": bAutoConfirmDepositAmount.String(),
			}).Where(db.Cond{
				"id":         updatePairId,
				"asset_a_id": aId,
				"asset_b_id": bId,
			}).Exec()
			if err != nil {
				return err
			}

			err = database.UpdateSign(dbTx, database.TableOfPairs, updatePairId, b.ToolsSignKeyId)
			if err != nil {
				return err
			}

			return nil
		})
		if err != nil {
			fmt.Println(err)
			return
		}

		fmt.Println("Pair Updated")
		return
	} else {
		err = sess.Tx(func(dbTx db.Session) error {
			result, err := dbTx.SQL().InsertInto("pairs").Columns(
				"asset_a_id", "asset_b_id",
				"asset_a_min_deposit_amount", "asset_b_min_deposit_amount",
				"asset_a_withdraw_fee_percent", "asset_b_withdraw_fee_percent",
				"asset_a_withdraw_fee_min", "asset_b_withdraw_fee_min",
				"asset_a_auto_confirm_deposit_amount", "asset_b_auto_confirm_deposit_amount",
			).Values(
				aId, bId,
				aMinDepositAmount.String(), bMinDepositAmount.String(),
				aFeePercent, bFeePercent,
				aWithdrawFeeMin.String(), bWithdrawFeeMin.String(),
				aAutoConfirmDepositAmount.String(), bAutoConfirmDepositAmount.String()).Exec()
			if err != nil {
				return err
			}

			lastId, err := result.LastInsertId()
			if err != nil {
				return err
			}
			err = database.UpdateSign(dbTx, database.TableOfPairs, uint64(lastId), b.ToolsSignKeyId)
			if err != nil {
				return err
			}

			return nil
		})
		if err != nil {
			fmt.Println(err)
			return
		}

		fmt.Println("Pair added")
	}

	return
}

func (cli *CLI) buildDeletePairCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:                   "delete <DogecoinDRC20> <EthereumToken>",
		Short:                 "delete the pair",
		Args:                  cobra.MinimumNArgs(2),
		DisableFlagsInUseLine: true,
		Run: func(cmd *cobra.Command, args []string) {

			// 0: address
			dogeTokenTick := args[0]
			if len(dogeTokenTick) == 0 {
				fmt.Println("Dogecoin DRC-20 tick error: ", dogeTokenTick)
				return
			}

			if !common.IsHexAddress(args[1]) {
				fmt.Println("Ethereum token address error: ", args[1])
				return
			}
			ethTokenAddress := common.HexToAddress(args[1])

			// ok, try to get token base info on-chain
			all := viper.AllSettings()
			allJson, err := json.Marshal(&all)
			if err != nil {
				fmt.Println(err)
				return
			}

			var b config.Bridge
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
			_, err = sess.SQL().DeleteFrom("pairs_list").Where(
				"doge_token", dogeTokenTick).And(
				"eth_token", ethTokenAddress.String()).Exec()
			if err != nil {
				fmt.Println(err)
				return
			}

			fmt.Println("Pair deleted")

		},
	}

	return cmd
}
