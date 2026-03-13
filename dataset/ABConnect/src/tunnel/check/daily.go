package check

import (
	"crypto/tls"
	"errors"
	"fmt"
	"math/big"
	"strings"
	"time"

	"github.com/upper/db/v4"
	"gitlab.weinvent.org/yangchenzhong/tunnel/api"
	"gitlab.weinvent.org/yangchenzhong/tunnel/blockchain"
	"gitlab.weinvent.org/yangchenzhong/tunnel/database"
	"gitlab.weinvent.org/yangchenzhong/tunnel/notify/smtp"
	pb "gitlab.weinvent.org/yangchenzhong/tunnel/proto/tunnelapi"
	"gitlab.weinvent.org/yangchenzhong/tunnel/utils"
	"gitlab.weinvent.org/yangchenzhong/tunnel/utils/config"
	"gopkg.in/gomail.v2"
)

func (c *Check) Daily() {
	c.DailyEmail()
}

// DailyEmail send daily eStatement by email
func (c *Check) DailyEmail() {
	cb := c.Bridge

	// open db
	sess, err := database.OpenDatabase(cb.DB.Adapter, cb.DB.ConnectionURL)
	if err != nil {
		fmt.Println("Open db err: ", err)
		return
	}
	defer sess.Close()

	if err := c.InitBlockchains(sess); err != nil {
		fmt.Println("Init blockchains err: ", err)
		return
	}

	var bcList []*database.Blockchain
	err = sess.SQL().SelectFrom("blockchains").All(&bcList)
	if errors.Is(err, db.ErrNoMoreRows) {
		fmt.Println("No blockchains")
		return
	} else if err != nil {
		log.Errorln(err)
		return
	}
	bcMap := make(map[uint64]*database.Blockchain)
	for _, bc := range bcList {
		bcMap[bc.Id] = bc
	}

	blockchains := make(map[string]*config.ChainConfig)
	slugs := make(map[uint64]string)

	for i, bc := range cb.Router.Blockchains {
		if bc == nil {
			log.Errorf("blockchain %d is zero", i)
			return
		}

		if bc.Network == "" || bc.ChainId == "" {
			log.Errorf("blockchain %d config empty", i)
			return
		}

		var aBC database.Blockchain
		err = sess.SQL().SelectFrom("blockchains").Where(
			"network", bc.Network).And(
			"chain_id", bc.ChainId).One(&aBC)
		if errors.Is(err, db.ErrNoMoreRows) {
			log.Errorf("blockchain %d not support: (%s:%s)", i, bc.Network, bc.ChainId)
			return
		} else if err != nil {
			log.Errorf("blockchain %d error: %v", i, err)
			return
		}

		if bc.BlockchainId != 0 && aBC.Id != bc.BlockchainId {
			log.Errorf("blockchain %d id error, from config is %d but the database is %d", i, bc.BlockchainId, aBC.Id)
			return
		}
		bc.BlockchainId = aBC.Id

		aBaseChain := blockchain.Parse(aBC.BaseChain)
		if aBaseChain == blockchain.UnknownChain {
			log.Errorf("blockchain from db is unknow")
			return
		}

		if bc.BaseChain == blockchain.UnknownChain {
			bc.BaseChain = aBaseChain
		} else if bc.BaseChain != aBaseChain {
			log.Errorf("basechain %d error, from config is %s but the database is %s", i, bc.BaseChain.String(), aBaseChain.String())
			return
		}

		bc.Slug = strings.ToLower(bc.Slug)

		if bc.BlockchainId == 0 || bc.Network == "" || bc.ChainId == "" || bc.Slug == "" {
			log.Errorf("blockchain %d empty: %v", i, bc)
			return
		}

		// get inner blockchain type
		chainInfo, err := api.GetChainInfo(bc.ChainAPIHost)
		if err != nil {
			log.Errorln(err)
			return
		}
		if chainInfo == nil {
			log.Errorf("get chainInfo nil")
			return
		}
		bc.BaseChain = blockchain.Parse(chainInfo.BaseChain)
		if bc.BaseChain == blockchain.UnknownChain {
			log.Errorf("UnknownChain %d:%v", i, bc.Slug)
		}

		if blockchains[bc.Slug] != nil {
			log.Errorf("duplicated blockchain name: %v", bc.Slug)
			return
		}
		blockchains[bc.Slug] = bc
		slugs[bc.BlockchainId] = bc.Slug
	}

	// blockchainId ==> assetId => AssetBalance
	blockchainsMap := make(map[uint64]map[uint64]*utils.AssetBalance)
	// pairId ==> assetId => AssetBalance
	pairsMap := make(map[uint64]map[uint64]*utils.AssetBalance)
	bcForBalances := make(map[uint64]map[string]map[string]bool) // bcId => AssetId => []address
	now := time.Now().Add(-24 * time.Hour).UTC()
	startOfNow := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, time.UTC)

	// all from history left join
	var historyList []*database.HistoryDetail
	err = sess.SQL().Select(
		"h.*",
		"p.id AS pair_id",
		"a1.id AS asset_id",
		"a1.name AS asset_name",
		"a1.symbol AS asset_symbol",
		"a1.decimals AS asset_decimals",
		"a1.attribute AS asset_attribute",
		"a1.asset_type AS asset_type",
		"b1.network AS network",
		"b1.chain_id AS chain_id",
		"b1.base_chain AS base_chain",
		"a2.id AS target_asset_id",
		"a2.name AS target_asset_name",
		"a2.symbol AS target_asset_symbol",
		"a2.decimals AS target_asset_decimals",
		"a2.attribute AS target_asset_attribute",
		"a2.asset_type AS target_asset_type",
		"b2.network AS target_network",
		"b2.chain_id AS target_chain_id",
		"b2.base_chain AS target_base_chain").From("history h").
		LeftJoin("assets a1").On("h.blockchain_id = a1.blockchain_id and h.asset = a1.asset").
		LeftJoin("blockchains b1").On("a1.blockchain_id = b1.id").
		LeftJoin("assets a2").On("h.target_blockchain_id = a2.blockchain_id and h.target_asset = a2.asset").
		LeftJoin("blockchains b2").On("a2.blockchain_id = b2.id").
		LeftJoin("pairs p").On("(p.asset_a_id = a1.id and p.asset_b_id = a2.id) or (p.asset_a_id = a2.id and p.asset_b_id = a1.id)").OrderBy(
		"h.id DESC").All(&historyList)
	if err != nil {
		log.Errorln(err)
		return
	}

	for _, h := range historyList {
		// deposit
		if blockchainsMap[h.BlockchainId] == nil {
			blockchainsMap[h.BlockchainId] = make(map[uint64]*utils.AssetBalance)
		}
		if blockchainsMap[h.BlockchainId][h.AssetId] == nil {
			blockchainsMap[h.BlockchainId][h.AssetId] = &utils.AssetBalance{
				AssetId:      h.AssetId,
				BlockchainId: h.BlockchainId,
				Asset:        h.Asset,
				Name:         h.AssetName,
				Symbol:       h.AssetSymbol,
				Decimals:     h.AssetDecimals,
				Attribute:    h.AssetAttribute,
				AssetType:    h.AssetType,

				Network:   h.Network,
				ChainId:   h.ChainId,
				BaseChain: h.BaseChain,
				Slug:      slugs[h.BlockchainId],

				TotalDeposit:         big.NewInt(0),
				TotalWithdraw:        big.NewInt(0),
				TotalDepositLastDay:  big.NewInt(0),
				TotalWithdrawLastDay: big.NewInt(0),
				TotalFee:             big.NewInt(0),
			}
		}
		amount, ok := big.NewInt(0).SetString(h.Amount, 10)
		if !ok {
			log.Errorln("string to big int error")
			return
		}
		blockchainsMap[h.BlockchainId][h.AssetId].TotalDeposit.Add(
			blockchainsMap[h.BlockchainId][h.AssetId].TotalDeposit,
			amount)
		if h.BlockTimestamp.After(startOfNow) {
			blockchainsMap[h.BlockchainId][h.AssetId].TotalDepositLastDay.Add(
				blockchainsMap[h.BlockchainId][h.AssetId].TotalDepositLastDay,
				amount)
		}
		fee := big.NewInt(0)
		if h.Fee != "" {
			// fee use WithdrawDecimals
			_, ok := fee.SetString(h.Fee, 10)
			if !ok {
				log.Errorln(fmt.Errorf("invalid fee: %s", h.Fee))
				return
			}
		}
		blockchainsMap[h.BlockchainId][h.AssetId].TotalFee.Add(
			blockchainsMap[h.BlockchainId][h.AssetId].TotalFee, fee)

		if bcForBalances[h.BlockchainId] == nil {
			bcForBalances[h.BlockchainId] = make(map[string]map[string]bool)
		}
		if bcForBalances[h.BlockchainId][h.Asset] == nil {
			bcForBalances[h.BlockchainId][h.Asset] = make(map[string]bool)
		}
		if bcForBalances[h.TargetBlockchainId] == nil {
			bcForBalances[h.TargetBlockchainId] = make(map[string]map[string]bool)
		}
		if bcForBalances[h.TargetBlockchainId][h.TargetAsset] == nil {
			bcForBalances[h.TargetBlockchainId][h.TargetAsset] = make(map[string]bool)
		}
		if h.Status != utils.BridgeMergedBroadcast && h.Status != utils.BridgeMergedConfirmed {
			bcForBalances[h.BlockchainId][h.Asset][h.Address] = true
		}

		if h.PairId != nil {
			pairId := *h.PairId
			if pairsMap[pairId] == nil {
				pairsMap[pairId] = make(map[uint64]*utils.AssetBalance)
			}
			if pairsMap[pairId][h.AssetId] == nil {
				pairsMap[pairId][h.AssetId] = &utils.AssetBalance{
					AssetId:      h.AssetId,
					BlockchainId: h.BlockchainId,
					Asset:        h.Asset,
					Name:         h.AssetName,
					Symbol:       h.AssetSymbol,
					Decimals:     h.AssetDecimals,
					Attribute:    h.AssetAttribute,
					AssetType:    h.AssetType,

					Network:   h.Network,
					ChainId:   h.ChainId,
					BaseChain: h.BaseChain,
					Slug:      slugs[h.BlockchainId],

					TotalDeposit:         big.NewInt(0),
					TotalWithdraw:        big.NewInt(0),
					TotalDepositLastDay:  big.NewInt(0),
					TotalWithdrawLastDay: big.NewInt(0),
					TotalFee:             big.NewInt(0),
				}
			}

			pairsMap[pairId][h.AssetId].TotalDeposit.Add(
				pairsMap[pairId][h.AssetId].TotalDeposit,
				amount)
			if h.BlockTimestamp.After(startOfNow) {
				pairsMap[pairId][h.AssetId].TotalDepositLastDay.Add(
					pairsMap[pairId][h.AssetId].TotalDepositLastDay,
					amount)
			}
		}

		if h.TargetAssetId == nil ||
			h.TargetAssetName == nil ||
			h.TargetAssetSymbol == nil ||
			h.TargetAssetDecimals == nil ||
			h.TargetNetwork == nil ||
			h.TargetChainId == nil ||
			h.TargetBaseChain == nil {
			continue
		}
		if blockchainsMap[h.TargetBlockchainId] == nil {
			blockchainsMap[h.TargetBlockchainId] = make(map[uint64]*utils.AssetBalance)
		}
		if blockchainsMap[h.TargetBlockchainId][*h.TargetAssetId] == nil {
			blockchainsMap[h.TargetBlockchainId][*h.TargetAssetId] = &utils.AssetBalance{
				AssetId:      *h.TargetAssetId,
				BlockchainId: h.TargetBlockchainId,
				Asset:        h.TargetAsset,
				Name:         *h.TargetAssetName,
				Symbol:       *h.TargetAssetSymbol,
				Decimals:     *h.TargetAssetDecimals,
				// Attribute:     0,
				AssetType: *h.TargetAssetType,

				Network:   *h.TargetNetwork,
				ChainId:   *h.TargetChainId,
				BaseChain: *h.TargetBaseChain,
				Slug:      slugs[h.TargetBlockchainId],

				TotalDeposit:         big.NewInt(0),
				TotalWithdraw:        big.NewInt(0),
				TotalDepositLastDay:  big.NewInt(0),
				TotalWithdrawLastDay: big.NewInt(0),
				TotalFee:             big.NewInt(0),
			}
		}
		finalAmount := big.NewInt(0)
		if h.FinalAmount != "" {
			finalAmount, ok = big.NewInt(0).SetString(h.FinalAmount, 10)
			if !ok {
				log.Errorln("string to big int error")
				return
			}
		}
		blockchainsMap[h.TargetBlockchainId][*h.TargetAssetId].TotalWithdraw.Add(
			blockchainsMap[h.TargetBlockchainId][*h.TargetAssetId].TotalWithdraw,
			finalAmount)

		// base on deposit block timestamp not target block timestamp
		if h.BlockTimestamp.After(startOfNow) {
			blockchainsMap[h.TargetBlockchainId][*h.TargetAssetId].TotalWithdrawLastDay.Add(
				blockchainsMap[h.TargetBlockchainId][*h.TargetAssetId].TotalWithdrawLastDay,
				finalAmount)
		}

		// pair
		// AssetA == Balance
		// AssetB == Balance
		if h.PairId != nil {
			pairId := *h.PairId
			if pairsMap[pairId] == nil {
				pairsMap[pairId] = make(map[uint64]*utils.AssetBalance)
			}
			if pairsMap[pairId][*h.TargetAssetId] == nil {
				pairsMap[pairId][*h.TargetAssetId] = &utils.AssetBalance{
					AssetId:      *h.TargetAssetId,
					BlockchainId: h.TargetBlockchainId,
					Asset:        h.TargetAsset,
					Name:         *h.TargetAssetName,
					Symbol:       *h.TargetAssetSymbol,
					Decimals:     *h.TargetAssetDecimals,
					// Attribute:     0,
					AssetType: *h.TargetAssetType,

					Network:   *h.TargetNetwork,
					ChainId:   *h.TargetChainId,
					BaseChain: *h.TargetBaseChain,
					Slug:      slugs[h.TargetBlockchainId],

					TotalDeposit:         big.NewInt(0),
					TotalWithdraw:        big.NewInt(0),
					TotalDepositLastDay:  big.NewInt(0),
					TotalWithdrawLastDay: big.NewInt(0),
					TotalFee:             big.NewInt(0),
				}
			}

			pairsMap[pairId][*h.TargetAssetId].TotalWithdraw.Add(
				pairsMap[pairId][*h.TargetAssetId].TotalWithdraw,
				finalAmount)
			pairsMap[*h.PairId][h.AssetId].TotalFee.Add(
				pairsMap[*h.PairId][h.AssetId].TotalFee,
				fee)
			// base on deposit block timestamp not target block timestamp
			if h.BlockTimestamp.After(startOfNow) {
				pairsMap[pairId][*h.TargetAssetId].TotalWithdrawLastDay.Add(
					pairsMap[pairId][*h.TargetAssetId].TotalWithdrawLastDay,
					finalAmount)
			}
		}
	}

	mainBalances, err := c.getOnChainBalance(sess, bcForBalances)
	if err != nil {
		fmt.Println(fmt.Errorf("getSystemBalance: %s", err))
		return
	}

	assetsCardHtml := ""
	pairsCardHtml := ""
	blockchainsList := make([]*pb.Balance, 0)
	for i, ab := range blockchainsMap {
		assetBalances := make([]*pb.AssetBalance, 0)
		slug, ok := slugs[i]
		if !ok {
			continue
		}
		bc, ok := blockchains[slug]
		if !ok {
			continue
		}
		for _, b := range ab {
			onchainBalance := big.NewInt(0)
			if mainBalances != nil && mainBalances[b.BlockchainId] != nil {
				onchainBalance = mainBalances[b.BlockchainId][b.Asset]
				if onchainBalance == nil {
					onchainBalance = big.NewInt(0)
				}
			}

			if b.Asset == "" {
				// calc the fee
				totalFee, err := c.getTotalFee(sess, b.BlockchainId)
				if err != nil {
					fmt.Println(fmt.Errorf("getTotalFees: %s", err))
					return
				}

				netBridgeAmount := big.NewInt(0).Abs(new(big.Int).Sub(b.TotalDeposit, b.TotalWithdraw))

				assetCardHtml := fmt.Sprintf(smtp.CardStart, b.Name, fmt.Sprintf("%s(%s)", b.Network, b.ChainId),
					utils.GetAmountTextFromISAACWithDecimals(b.TotalDeposit, b.Decimals), b.Symbol,
					utils.GetAmountTextFromISAACWithDecimals(b.TotalWithdraw, b.Decimals), b.Symbol,
					utils.GetAmountTextFromISAACWithDecimals(b.TotalFee, b.Decimals), b.Symbol,
					utils.GetAmountTextFromISAACWithDecimals(b.TotalDepositLastDay, b.Decimals), b.Symbol,
					utils.GetAmountTextFromISAACWithDecimals(b.TotalWithdrawLastDay, b.Decimals), b.Symbol)
				assetCardHtml += fmt.Sprintf(smtp.CardItem, "Logical Balance", utils.GetAmountTextFromISAACWithDecimals(netBridgeAmount, b.Decimals), b.Symbol)
				assetCardHtml += fmt.Sprintf(smtp.CardItem, "OnChain Fees", utils.GetAmountTextFromISAACWithDecimals(totalFee, b.Decimals), b.Symbol)
				assetCardHtml += fmt.Sprintf(smtp.CardItem, "OnChain Balance", utils.GetAmountTextFromISAACWithDecimals(onchainBalance, b.Decimals), b.Symbol)

				message := fmt.Sprintf("Asset: %s(%s)\n"+
					"Network: %s(%s)\n"+
					"TotalDeposit: %v %s\n"+
					"TotalWithdraw: %v %s\n"+
					"Logical Balance: %v %s\n"+
					"OnChain Fees: %v %s\n"+
					"OnChain Balance: %v %s\n",
					b.Name, b.Symbol, b.Network, b.ChainId,
					utils.GetAmountTextFromISAACWithDecimals(b.TotalDeposit, b.Decimals), b.Symbol,
					utils.GetAmountTextFromISAACWithDecimals(b.TotalWithdraw, b.Decimals), b.Symbol,
					utils.GetAmountTextFromISAACWithDecimals(netBridgeAmount, b.Decimals), b.Symbol,
					utils.GetAmountTextFromISAACWithDecimals(totalFee, b.Decimals), b.Symbol,
					utils.GetAmountTextFromISAACWithDecimals(onchainBalance, b.Decimals), b.Symbol,
				)

				netBalance := big.NewInt(0).Set(netBridgeAmount)
				if strings.HasPrefix(b.Network, "ABCore") {
					// for AB@ABCore
					assetInfo, err := getAssetInfo(bc.ChainAPIHost, "")
					if err != nil {
						fmt.Println(err)
						return
					}
					totalSupply := big.NewInt(0)
					if assetInfo.TotalSupply != "" {
						totalSupply, ok = big.NewInt(0).SetString(assetInfo.TotalSupply, 10)
						if !ok {
							fmt.Println(fmt.Errorf("totalSupply: %s", assetInfo.TotalSupply))
							return
						}
					}

					netBalance.Add(netBalance, totalFee)
					netBalance.Sub(totalSupply, netBalance)
					message += fmt.Sprintf("OnChain TotalSupply: %v %s\n"+
						"NetBalance: %v %s\n",
						utils.GetAmountTextFromISAACWithDecimals(totalSupply, b.Decimals), b.Symbol,
						utils.GetAmountTextFromISAACWithDecimals(netBalance, b.Decimals), b.Symbol,
					)
					assetCardHtml += fmt.Sprintf(smtp.CardItem, "OnChain TotalSupply", utils.GetAmountTextFromISAACWithDecimals(totalSupply, b.Decimals), b.Symbol)
					assetCardHtml += fmt.Sprintf(smtp.CardItem, "NetBalance", utils.GetAmountTextFromISAACWithDecimals(netBalance, b.Decimals), b.Symbol)
				} else {
					netBalance.Sub(netBalance, totalFee)
				}

				assetCardHtml += smtp.CardEnd
				assetsCardHtml = fmt.Sprintf("%s%s", assetsCardHtml, assetCardHtml)

				fmt.Println(message)
				if onchainBalance.Cmp(netBalance) < 0 {
					_ = c.sendMessage("Security Check: Asset Balance Check Failed", message)
				}
			} else {
				netBridgeAmount := big.NewInt(0).Abs(new(big.Int).Sub(b.TotalDeposit, b.TotalWithdraw))

				assetCardHtml := fmt.Sprintf(smtp.CardStart, b.Name, fmt.Sprintf("%s(%s)", b.Network, b.ChainId),
					utils.GetAmountTextFromISAACWithDecimals(b.TotalDeposit, b.Decimals), b.Symbol,
					utils.GetAmountTextFromISAACWithDecimals(b.TotalWithdraw, b.Decimals), b.Symbol,
					utils.GetAmountTextFromISAACWithDecimals(b.TotalFee, b.Decimals), b.Symbol,
					utils.GetAmountTextFromISAACWithDecimals(b.TotalDepositLastDay, b.Decimals), b.Symbol,
					utils.GetAmountTextFromISAACWithDecimals(b.TotalWithdrawLastDay, b.Decimals), b.Symbol)
				assetCardHtml += fmt.Sprintf(smtp.CardItem, "Logical Balance", utils.GetAmountTextFromISAACWithDecimals(netBridgeAmount, b.Decimals), b.Symbol)
				assetCardHtml += fmt.Sprintf(smtp.CardItem, "OnChain Balance", utils.GetAmountTextFromISAACWithDecimals(onchainBalance, b.Decimals), b.Symbol)

				message := fmt.Sprintf("Asset: %s(%s)\n"+
					"Network: %s(%s)\n"+
					"TotalDeposit: %v %s\n"+
					"TotalWithdraw: %v %s\n"+
					"Logical Balance: %v %s\n"+
					"OnChain Balance: %v %s\n",
					b.Name, b.Symbol, b.Network, b.ChainId,
					utils.GetAmountTextFromISAACWithDecimals(b.TotalDeposit, b.Decimals), b.Symbol,
					utils.GetAmountTextFromISAACWithDecimals(b.TotalWithdraw, b.Decimals), b.Symbol,
					utils.GetAmountTextFromISAACWithDecimals(netBridgeAmount, b.Decimals), b.Symbol,
					utils.GetAmountTextFromISAACWithDecimals(onchainBalance, b.Decimals), b.Symbol,
				)

				netBalance := big.NewInt(0).Set(onchainBalance)
				// for mint but not burn
				if (b.Attribute&utils.AttributeMintable == utils.AttributeMintable) && (b.Attribute&utils.AttributeBurnable != utils.AttributeBurnable) {
					// mainBalance is token.totalSupply - balanceOf(mainList)
					// "OnChain Adjusted Balance: %v %s\n",
					// continue

					assetInfo, err := getAssetInfo(bc.ChainAPIHost, b.Asset)
					if err != nil {
						fmt.Println(fmt.Errorf("getAssetInfo: %s", err))
						return
					}
					totalSupply := big.NewInt(0)
					if assetInfo.TotalSupply != "" {
						totalSupply, ok = big.NewInt(0).SetString(assetInfo.TotalSupply, 10)
						if !ok {
							fmt.Println(fmt.Errorf("totalSupply: %s", assetInfo.TotalSupply))
							return
						}
					}

					netBalance.Sub(totalSupply, onchainBalance)
					message += fmt.Sprintf("OnChain TotalSupply: %v %s\n"+
						"OnChain NetBalance: %v %s\n",
						utils.GetAmountTextFromISAACWithDecimals(totalSupply, b.Decimals), b.Symbol,
						utils.GetAmountTextFromISAACWithDecimals(netBalance, b.Decimals), b.Symbol,
					)
					assetCardHtml += fmt.Sprintf(smtp.CardItem, "OnChain TotalSupply", utils.GetAmountTextFromISAACWithDecimals(totalSupply, b.Decimals), b.Symbol)
					assetCardHtml += fmt.Sprintf(smtp.CardItem, "NetBalance", utils.GetAmountTextFromISAACWithDecimals(netBalance, b.Decimals), b.Symbol)
				}

				fmt.Println(message)
				assetCardHtml += smtp.CardEnd
				assetsCardHtml = fmt.Sprintf("%s%s", assetsCardHtml, assetCardHtml)

				if netBalance.Cmp(netBridgeAmount) < 0 {
					_ = c.sendMessage("Security Check: Asset Balance Check Failed", message)
				}

			}

			assetBalances = append(assetBalances, &pb.AssetBalance{
				Asset: &pb.Asset{
					Id:        b.AssetId,
					Asset:     b.Asset,
					Name:      b.Name,
					Symbol:    b.Symbol,
					Decimals:  uint32(b.Decimals),
					AssetType: b.AssetType,
					Network:   b.Network,
					ChainId:   b.ChainId,
					BaseChain: b.BaseChain,
					Slug:      b.Slug,
				},
				TotalDeposit:         b.TotalDeposit.String(),
				TotalWithdraw:        b.TotalWithdraw.String(),
				TotalDepositLastDay:  b.TotalDepositLastDay.String(),
				TotalWithdrawLastDay: b.TotalWithdrawLastDay.String(),
			})
		}

		blockchainsList = append(blockchainsList, &pb.Balance{
			BlockchainId: i,
			Blockchain: &pb.Blockchain{
				Network:   bc.Network,
				ChainId:   bc.ChainId,
				BaseChain: bc.BaseChain.String(),
				Slug:      slug,
			},
			Balances: assetBalances,
		})
	}
	assetsCardHtml = fmt.Sprintf("<h2>By Asset</h2>%s", assetsCardHtml)

	// pairs
	messagePairs := ""
	for _, ab := range pairsMap {
		messagePairs = fmt.Sprintf("%s----------------\n", messagePairs)
		if len(ab) != 2 {
			fmt.Println("Pairs map error")
			// return
			continue
		}

		var first, second uint64
		for id, asset := range ab {
			if first == 0 || asset.AssetId < ab[first].AssetId {
				second = first
				first = id
			} else if second == 0 || asset.AssetId < ab[second].AssetId {
				second = id
			}
		}
		assetA, assetB := ab[first], ab[second]

		pairCardHtml := fmt.Sprintf(smtp.CardPair, assetA.Name, fmt.Sprintf("%s(%s)", assetA.Network, assetA.ChainId), assetB.Name, fmt.Sprintf("%s(%s)", assetB.Network, assetB.ChainId),
			assetA.Name, fmt.Sprintf("%s(%s)", assetA.Network, assetA.ChainId),
			utils.GetAmountTextFromISAACWithDecimals(assetA.TotalDeposit, assetA.Decimals), assetA.Symbol,
			utils.GetAmountTextFromISAACWithDecimals(assetA.TotalWithdraw, assetA.Decimals), assetA.Symbol,
			utils.GetAmountTextFromISAACWithDecimals(assetA.TotalFee, assetA.Decimals), assetA.Symbol,
			utils.GetAmountTextFromISAACWithDecimals(assetA.TotalDepositLastDay, assetA.Decimals), assetA.Symbol,
			utils.GetAmountTextFromISAACWithDecimals(assetA.TotalWithdrawLastDay, assetA.Decimals), assetA.Symbol,
			assetB.Name, fmt.Sprintf("%s(%s)", assetB.Network, assetB.ChainId),
			utils.GetAmountTextFromISAACWithDecimals(assetB.TotalDeposit, assetB.Decimals), assetB.Symbol,
			utils.GetAmountTextFromISAACWithDecimals(assetB.TotalWithdraw, assetB.Decimals), assetB.Symbol,
			utils.GetAmountTextFromISAACWithDecimals(assetB.TotalFee, assetB.Decimals), assetB.Symbol,
			utils.GetAmountTextFromISAACWithDecimals(assetB.TotalDepositLastDay, assetB.Decimals), assetB.Symbol,
			utils.GetAmountTextFromISAACWithDecimals(assetB.TotalWithdrawLastDay, assetB.Decimals), assetB.Symbol)
		pairsCardHtml = fmt.Sprintf("%s%s", pairsCardHtml, pairCardHtml)

	}
	pairsCardHtml = fmt.Sprintf("<h2>By Pair</h2>%s", pairsCardHtml)

	cardsHtml := fmt.Sprintf("%s %s", assetsCardHtml, pairsCardHtml)

	if cb.EnableSMTP && cb.SMTP != nil {
		from := cb.SMTP.From
		fromDisplayName := cb.SMTP.FromDisplayName
		toList := strings.Split(cb.SMTP.To, ",")

		d := gomail.NewDialer(cb.SMTP.Host, cb.SMTP.Port, cb.SMTP.Username, cb.SMTP.Password)
		d.TLSConfig = &tls.Config{InsecureSkipVerify: true}

		title := fmt.Sprintf("%s Daily eStatement - %s %d, %d", utils.BrandName, startOfNow.Month(), startOfNow.Day(), startOfNow.Year())

		if fromDisplayName == "" {
			fromDisplayName = utils.BrandName
		}
		body := fmt.Sprintf(smtp.Body,
			fmt.Sprintf("%s %d, %d", startOfNow.Month(), startOfNow.Day(), startOfNow.Year()),
			cardsHtml,
			utils.BrandName)

		// fmt.Println(body)

		m := gomail.NewMessage()
		// m.SetHeader("From", from, fromDisplayName)
		m.SetAddressHeader("From", from, fromDisplayName)
		m.SetHeader("To", toList...)
		m.SetHeader("Subject", title)
		m.SetBody("text/html", body)

		err = d.DialAndSend(m)
		if err != nil {
			log.Errorln(err)
		} else {
			fmt.Println("Email sent successfully!")
		}
	}

}
