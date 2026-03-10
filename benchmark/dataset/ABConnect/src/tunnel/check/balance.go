package check

import (
	"context"
	"errors"
	"fmt"
	"math/big"
	"strings"
	"sync"
	"time"

	"github.com/upper/db/v4"
	"gitlab.weinvent.org/yangchenzhong/tunnel/database"
	"gitlab.weinvent.org/yangchenzhong/tunnel/proto/chainapi"
	"gitlab.weinvent.org/yangchenzhong/tunnel/utils"
	"gitlab.weinvent.org/yangchenzhong/tunnel/utils/config"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
)

// Balance check all chain MainWithdrawAddress balance
func (c *Check) Balance() (err error) {
	// load all MainWithdrawAddress and ColdAddress
	// compare onchain balance with system balance

	// init notify
	if err := c.initNotify(); err != nil {
		return err
	}
	defer func() {
		if err != nil {
			_ = c.sendMessage("Security Check Error", err.Error())
		}
	}()

	sess, err := database.OpenDatabase(c.DB.Adapter, c.DB.ConnectionURL)
	if err != nil {
		return fmt.Errorf("open db err: %v", err)
	}
	defer sess.Close()

	if err := c.InitBlockchains(sess); err != nil {
		return err
	}

	// blockchainId ==> assetId => AssetBalance
	blockchains := make(map[uint64]map[uint64]*utils.AssetBalance)
	// pairId => assetAId + AssetBId => AssetBalance
	pairs := make(map[uint64]map[uint64]*utils.AssetBalance)
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
		return err
	}

	if len(historyList) == 0 {
		return nil
	}

	for _, h := range historyList {
		if h.Status >= utils.BridgeInternalTx {
			continue
		}

		// deposit
		if blockchains[h.BlockchainId] == nil {
			blockchains[h.BlockchainId] = make(map[uint64]*utils.AssetBalance)
		}
		if blockchains[h.BlockchainId][h.AssetId] == nil {
			blockchains[h.BlockchainId][h.AssetId] = &utils.AssetBalance{
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
				Slug:      c.slugs[h.BlockchainId],

				TotalDeposit:         big.NewInt(0),
				TotalWithdraw:        big.NewInt(0),
				TotalDepositLastDay:  big.NewInt(0),
				TotalWithdrawLastDay: big.NewInt(0),
				TotalFee:             big.NewInt(0),
			}
		}
		amount, ok := big.NewInt(0).SetString(h.Amount, 10)
		if !ok {
			return fmt.Errorf("invalid amount: %s", h.Amount)
		}
		blockchains[h.BlockchainId][h.AssetId].TotalDeposit.Add(
			blockchains[h.BlockchainId][h.AssetId].TotalDeposit,
			amount)
		if h.BlockTimestamp.After(startOfNow) {
			blockchains[h.BlockchainId][h.AssetId].TotalDepositLastDay.Add(
				blockchains[h.BlockchainId][h.AssetId].TotalDepositLastDay,
				amount)
		}
		fee := big.NewInt(0)
		if h.Fee != "" {
			// fee use WithdrawDecimals
			_, ok := fee.SetString(h.Fee, 10)
			if !ok {
				return fmt.Errorf("invalid fee: %s", h.Fee)
			}
		}
		blockchains[h.BlockchainId][h.AssetId].TotalFee.Add(
			blockchains[h.BlockchainId][h.AssetId].TotalFee, fee)

		if bcForBalances[h.BlockchainId] == nil {
			bcForBalances[h.BlockchainId] = make(map[string]map[string]bool)
		}
		if bcForBalances[h.BlockchainId][h.Asset] == nil {
			bcForBalances[h.BlockchainId][h.Asset] = make(map[string]bool)
		}
		if h.Status != utils.BridgeMergedBroadcast && h.Status != utils.BridgeMergedConfirmed && h.MergeStatus != utils.HistoryMergeStatusConfirmed {
			bcForBalances[h.BlockchainId][h.Asset][h.Address] = true
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
		if blockchains[h.TargetBlockchainId] == nil {
			blockchains[h.TargetBlockchainId] = make(map[uint64]*utils.AssetBalance)
		}
		if blockchains[h.TargetBlockchainId][*h.TargetAssetId] == nil {
			blockchains[h.TargetBlockchainId][*h.TargetAssetId] = &utils.AssetBalance{
				AssetId:      *h.TargetAssetId,
				BlockchainId: h.TargetBlockchainId,
				Asset:        h.TargetAsset,
				Name:         *h.TargetAssetName,
				Symbol:       *h.TargetAssetSymbol,
				Decimals:     *h.TargetAssetDecimals,
				Attribute:    *h.TargetAssetAttribute,
				AssetType:    *h.TargetAssetType,

				Network:   *h.TargetNetwork,
				ChainId:   *h.TargetChainId,
				BaseChain: *h.TargetBaseChain,
				Slug:      c.slugs[h.TargetBlockchainId],

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
				return fmt.Errorf("invalid finalAmount: %s", h.FinalAmount)
			}
		}

		blockchains[h.TargetBlockchainId][*h.TargetAssetId].TotalWithdraw.Add(
			blockchains[h.TargetBlockchainId][*h.TargetAssetId].TotalWithdraw,
			finalAmount)

		// base on deposit block timestamp not target block timestamp
		if h.BlockTimestamp.After(startOfNow) {
			blockchains[h.TargetBlockchainId][*h.TargetAssetId].TotalWithdrawLastDay.Add(
				blockchains[h.TargetBlockchainId][*h.TargetAssetId].TotalWithdrawLastDay,
				finalAmount)
		}

		if bcForBalances[h.TargetBlockchainId] == nil {
			bcForBalances[h.TargetBlockchainId] = make(map[string]map[string]bool)
		}
		if bcForBalances[h.TargetBlockchainId][h.TargetAsset] == nil {
			bcForBalances[h.TargetBlockchainId][h.TargetAsset] = make(map[string]bool)
		}

		// pairs
		if h.PairId == nil || h.TargetAssetId == nil {
			continue
		}
		if pairs[*h.PairId] == nil {
			pairs[*h.PairId] = make(map[uint64]*utils.AssetBalance)
		}
		if pairs[*h.PairId][h.AssetId] == nil {
			pairs[*h.PairId][h.AssetId] = &utils.AssetBalance{
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
				Slug:      c.slugs[h.BlockchainId],

				TotalDeposit:         big.NewInt(0),
				TotalWithdraw:        big.NewInt(0),
				TotalDepositLastDay:  big.NewInt(0),
				TotalWithdrawLastDay: big.NewInt(0),
				TotalFee:             big.NewInt(0),
			}
		}
		pairs[*h.PairId][h.AssetId].TotalDeposit.Add(
			pairs[*h.PairId][h.AssetId].TotalDeposit,
			amount)
		pairs[*h.PairId][h.AssetId].TotalFee.Add(
			pairs[*h.PairId][h.AssetId].TotalFee,
			fee)
		if h.BlockTimestamp.After(startOfNow) {
			pairs[*h.PairId][h.AssetId].TotalDepositLastDay.Add(
				pairs[*h.PairId][h.AssetId].TotalDepositLastDay,
				amount)
		}

		if pairs[*h.PairId][*h.TargetAssetId] == nil {
			pairs[*h.PairId][*h.TargetAssetId] = &utils.AssetBalance{
				AssetId:      *h.TargetAssetId,
				BlockchainId: h.TargetBlockchainId,
				Asset:        h.TargetAsset,
				Name:         *h.TargetAssetName,
				Symbol:       *h.TargetAssetSymbol,
				Decimals:     *h.TargetAssetDecimals,
				Attribute:    *h.TargetAssetAttribute,
				AssetType:    *h.TargetAssetType,

				Network:   *h.TargetNetwork,
				ChainId:   *h.TargetChainId,
				BaseChain: *h.TargetBaseChain,
				Slug:      c.slugs[h.TargetBlockchainId],

				TotalDeposit:         big.NewInt(0),
				TotalWithdraw:        big.NewInt(0),
				TotalDepositLastDay:  big.NewInt(0),
				TotalWithdrawLastDay: big.NewInt(0),
				TotalFee:             big.NewInt(0),
			}
		}

		pairs[*h.PairId][*h.TargetAssetId].TotalWithdraw.Add(
			pairs[*h.PairId][*h.TargetAssetId].TotalWithdraw,
			finalAmount)

		// base on deposit block timestamp not target block timestamp
		if h.BlockTimestamp.After(startOfNow) {
			pairs[*h.PairId][*h.TargetAssetId].TotalWithdrawLastDay.Add(
				pairs[*h.PairId][*h.TargetAssetId].TotalWithdrawLastDay,
				finalAmount)
		}
	}

	// load configs
	var cfgList []database.Config
	if err := sess.SQL().SelectFrom(database.TableOfConfig).All(&cfgList); err != nil {
		return err
	}
	cfgMap := make(map[string]interface{})
	for _, cfg := range cfgList {
		if strings.HasSuffix(cfg.Variable, utils.LatestBlockHeight) {
			if number, ok := big.NewInt(0).SetString(cfg.Value, 10); !ok {
				return fmt.Errorf("invalid latest block height: %s", cfg.Variable)
			} else {
				cfgMap[cfg.Variable] = number.Uint64()
			}
		} else {
			cfgMap[cfg.Variable] = cfg.Value
		}
	}

	// pairs
	for pairId, assetBalanceMap := range pairs {
		if len(assetBalanceMap) != 2 {
			_ = c.sendMessage("Security Check Error",
				fmt.Sprintf("invalid asset balance len: %v", len(assetBalanceMap)))
			continue
		}

		var assetAId, assetBId uint64
		for assetId := range assetBalanceMap {
			if assetAId == 0 || assetId < assetAId {
				assetBId = assetAId
				assetAId = assetId
			} else if assetBId == 0 || assetId < assetBId {
				assetBId = assetId
			}
		}
		assetA := assetBalanceMap[assetAId]
		assetB := assetBalanceMap[assetBId]

		if assetA.TotalDeposit.Cmp(assetB.TotalWithdraw) < 0 {
			_ = c.sendMessage(fmt.Sprintf("Security Check: Pair(%d) TotalDeposit less than TotalWithdraw", pairId),
				fmt.Sprintf("AssetA: %s(%s)\n"+
					"AssetA Network: %s(%s)\n"+
					"AssetA TotalDeposit: %v %s\n\n"+
					"AssetB: %s(%s)\n"+
					"AssetB Network: %s(%s)\n"+
					"AssetB TotalWithdraw: %v %s\n",
					assetA.Name, assetA.Symbol, assetA.Network, assetA.ChainId,
					utils.GetAmountTextFromISAACWithDecimals(assetA.TotalDeposit, assetA.Decimals), assetA.Symbol,
					assetB.Name, assetB.Symbol, assetB.Network, assetB.ChainId,
					utils.GetAmountTextFromISAACWithDecimals(assetB.TotalWithdraw, assetB.Decimals), assetB.Symbol,
				))
			continue
		}

		if assetB.TotalDeposit.Cmp(assetA.TotalWithdraw) < 0 {
			_ = c.sendMessage(fmt.Sprintf("Security Check: Pair(%d) TotalDeposit less than TotalWithdraw", pairId),
				fmt.Sprintf("AssetA: %s(%s)\n"+
					"AssetA Network: %s(%s)\n"+
					"AssetA TotalDeposit: %v %s\n\n"+
					"AssetB: %s(%s)\n"+
					"AssetB Network: %s(%s)\n"+
					"AssetB TotalWithdraw: %v %s\n",
					assetB.Name, assetB.Symbol, assetB.Network, assetB.ChainId,
					utils.GetAmountTextFromISAACWithDecimals(assetB.TotalDeposit, assetB.Decimals), assetB.Symbol,
					assetA.Name, assetA.Symbol, assetA.Network, assetA.ChainId,
					utils.GetAmountTextFromISAACWithDecimals(assetA.TotalWithdraw, assetA.Decimals), assetA.Symbol,
				))
			continue
		}
	}

	// block height
	bhIds := make([]uint64, 0)
	for bcId := range bcForBalances {
		bhIds = append(bhIds, bcId)
	}
	blockHeights, err := c.getBlockHeight(sess, bhIds)
	if err != nil {
		return fmt.Errorf("getBlockHeight: %s", err)
	}

	mainBalances, err := c.getOnChainBalance(sess, bcForBalances)
	if err != nil {
		return fmt.Errorf("getSystemBalance: %s", err)
	}

	// main address onchain vs asset TotalDeposit-totalWithdraw

	for i, assetBalance := range blockchains {
		slug, ok := c.slugs[i]
		if !ok {
			continue
		}
		bc, ok := c.blockchains[slug]
		if !ok {
			continue
		}

		latestBlockHeightOnChain, ok := blockHeights[bc.BlockchainId]
		if !ok {
			return fmt.Errorf("latestBlockHeightOnChain not found for blockchain: %s", bc.BlockchainId)
		}
		LatestBlockHeight, ok := cfgMap[fmt.Sprintf("%s-%s-%s", bc.Network, bc.ChainId, utils.LatestBlockHeight)]
		if !ok {
			return fmt.Errorf("LatestBlockHeight not found in db: %s(%s)", bc.Network, bc.ChainId)
		}
		latestBlockHeight := LatestBlockHeight.(uint64)
		if latestBlockHeightOnChain-100 > latestBlockHeight {
			_ = c.sendMessage("Security Check: LatestBlockHeight delay",
				fmt.Sprintf("Network: %s(%s)\n"+
					"LatestBlockHeightOnChain: %d\n"+
					"LatestBlockHeightInDB: %d",
					bc.Network, bc.ChainId, latestBlockHeightOnChain, latestBlockHeight))
		}

		for _, b := range assetBalance {
			onchainBalance := big.NewInt(0)
			if mainBalances != nil && mainBalances[b.BlockchainId] != nil {
				onchainBalance = mainBalances[b.BlockchainId][b.Asset]
				if onchainBalance == nil {
					onchainBalance = big.NewInt(0)
				}
			}

			// TODO: update check
			// 1. add fee for native coin
			// 2. onchain balance + cold balance for mintable token
			if b.Asset == "" {
				// native coin

				// calc the fee
				totalOnChainFee, err := c.getTotalFee(sess, b.BlockchainId)
				if err != nil {
					return fmt.Errorf("getTotalFees: %s", err)
				}

				netBridgeAmount := big.NewInt(0).Abs(new(big.Int).Sub(b.TotalDeposit, b.TotalWithdraw))
				message := fmt.Sprintf("Asset: %s(%s)\n"+
					"Network: %s(%s)\n"+
					"TotalDeposit: %v %s\n"+
					"TotalWithdraw: %v %s\n"+
					"TotalFee: %v %s\n"+
					"Logical Balance: %v %s\n"+
					"OnChain Fees: %v %s\n"+
					"OnChain Balance: %v %s\n",
					b.Name, b.Symbol, b.Network, b.ChainId,
					utils.GetAmountTextFromISAACWithDecimals(b.TotalDeposit, b.Decimals), b.Symbol,
					utils.GetAmountTextFromISAACWithDecimals(b.TotalWithdraw, b.Decimals), b.Symbol,
					utils.GetAmountTextFromISAACWithDecimals(b.TotalFee, b.Decimals), b.Symbol,
					utils.GetAmountTextFromISAACWithDecimals(netBridgeAmount, b.Decimals), b.Symbol,
					utils.GetAmountTextFromISAACWithDecimals(totalOnChainFee, b.Decimals), b.Symbol,
					utils.GetAmountTextFromISAACWithDecimals(onchainBalance, b.Decimals), b.Symbol,
				)

				netBalance := big.NewInt(0).Set(netBridgeAmount)
				if strings.HasPrefix(b.Network, "ABCore") {
					// for AB@ABCore
					assetInfo, err := getAssetInfo(bc.ChainAPIHost, "")
					if err != nil {
						return fmt.Errorf("getAssetInfo: %s", err)
					}
					totalSupply := big.NewInt(0)
					if assetInfo.TotalSupply != "" {
						totalSupply, ok = big.NewInt(0).SetString(assetInfo.TotalSupply, 10)
						if !ok {
							return fmt.Errorf("totalSupply: %s", assetInfo.TotalSupply)
						}
					}

					netBalance.Sub(totalSupply, netBalance)
					message += fmt.Sprintf("OnChain TotalSupply: %v %s\n",
						utils.GetAmountTextFromISAACWithDecimals(totalSupply, b.Decimals), b.Symbol,
					)
				}
				netBalance.Sub(netBalance, totalOnChainFee)

				message += fmt.Sprintf("NetBalance: %v %s\n",
					utils.GetAmountTextFromISAACWithDecimals(netBalance, b.Decimals), b.Symbol,
				)

				fmt.Println(message)
				if onchainBalance.Cmp(netBalance) < 0 {
					message += fmt.Sprintf("\nError: OnchainBalance less than NetBalance\n")
					_ = c.sendMessage("Security Check: Asset Balance Check Failed", message)
				}
			} else {
				netBridgeAmount := big.NewInt(0).Abs(new(big.Int).Sub(b.TotalDeposit, b.TotalWithdraw))
				message := fmt.Sprintf("Asset: %s(%s)\n"+
					"Network: %s(%s)\n"+
					"TotalDeposit: %v %s\n"+
					"TotalWithdraw: %v %s\n"+
					"TotalFee: %v %s\n"+
					"Logical Balance: %v %s\n"+
					"OnChain Balance: %v %s\n",
					b.Name, b.Symbol, b.Network, b.ChainId,
					utils.GetAmountTextFromISAACWithDecimals(b.TotalDeposit, b.Decimals), b.Symbol,
					utils.GetAmountTextFromISAACWithDecimals(b.TotalWithdraw, b.Decimals), b.Symbol,
					utils.GetAmountTextFromISAACWithDecimals(b.TotalFee, b.Decimals), b.Symbol,
					utils.GetAmountTextFromISAACWithDecimals(netBridgeAmount, b.Decimals), b.Symbol,
					utils.GetAmountTextFromISAACWithDecimals(onchainBalance, b.Decimals), b.Symbol,
				)

				netBalance := big.NewInt(0).Set(netBridgeAmount)
				// for mint but not burn, force for AB@BSC
				if ((b.Attribute&utils.AttributeMintable == utils.AttributeMintable) && (b.Attribute&utils.AttributeBurnable != utils.AttributeBurnable)) ||
					((b.Attribute&utils.AttributeTransfer == utils.AttributeTransfer) && b.Name == "AB" && strings.HasPrefix(b.Network, "BSC")) {

					assetInfo, err := getAssetInfo(bc.ChainAPIHost, b.Asset)
					if err != nil {
						return fmt.Errorf("getAssetInfo: %s", err)
					}
					totalSupply := big.NewInt(0)
					if assetInfo.TotalSupply != "" {
						totalSupply, ok = big.NewInt(0).SetString(assetInfo.TotalSupply, 10)
						if !ok {
							return fmt.Errorf("totalSupply: %s", assetInfo.TotalSupply)
						}
					}

					netBalance.Sub(totalSupply, netBalance)
					message += fmt.Sprintf("OnChain TotalSupply: %v %s\n",
						utils.GetAmountTextFromISAACWithDecimals(totalSupply, b.Decimals), b.Symbol,
					)
				}
				// TODO: add this when token swap to native coin
				// netBalance.Sub(netBalance, b.TotalFee)

				message += fmt.Sprintf("NetBalance: %v %s\n",
					utils.GetAmountTextFromISAACWithDecimals(netBalance, b.Decimals), b.Symbol,
				)

				fmt.Println(message)
				if onchainBalance.Cmp(netBalance) < 0 {
					message += fmt.Sprintf("\nError: OnchainBalance less than NetBalance\n")
					_ = c.sendMessage("Security Check: Asset Balance Check Failed", message)
				}
			}
		}
	}

	return nil
}

// getMainBalance bcId => asset => balance
func (c *Check) getMainBalance(sess db.Session, blockchains map[uint64]map[string]bool) (mainBalances map[uint64]map[string]*big.Int, err error) {
	var cfgList []database.Config
	err = sess.SQL().SelectFrom(database.TableOfConfig).All(&cfgList)
	if err != nil {
		return nil, err
	}

	mainAddresses := make(map[string]string)
	for _, cfg := range cfgList {
		if !strings.HasSuffix(cfg.Variable, utils.WithdrawMainAddress) {
			continue
		}
		mainAddresses[cfg.Variable] = cfg.Value
	}

	if len(blockchains) == 0 || len(mainAddresses) == 0 {
		return nil, fmt.Errorf("no blockchains or main addresses set")
	}

	ctx := context.Background()
	var wg sync.WaitGroup
	var mu sync.Mutex
	errChan := make(chan error, len(blockchains))
	mainBalances = make(map[uint64]map[string]*big.Int) // bcId => asset => balance

	for bcId, assets := range blockchains {
		slug, ok := c.slugs[bcId]
		if !ok {
			continue
		}
		bc, ok := c.blockchains[slug]
		if !ok {
			continue
		}

		wg.Add(1)
		go func(bcCfg *config.ChainConfig, assets map[string]bool) {
			defer wg.Done()

			mA, ok := mainAddresses[fmt.Sprintf("%s-%s-%s", bcCfg.Network, bcCfg.ChainId, utils.WithdrawMainAddress)]
			if !ok {
				errChan <- fmt.Errorf("no such main address: %s(%s)", bcCfg.Network, bcCfg.ChainId)
				return
			}

			conn, err := grpc.NewClient(bcCfg.ChainAPIHost, grpc.WithTransportCredentials(insecure.NewCredentials()))
			if err != nil {
				errChan <- err
				return
			}

			client := chainapi.NewChainAPIClient(conn)

			for asset := range assets {
				resp, err := client.GetBalance(ctx, &chainapi.BalanceRequest{
					Address: mA,
					Asset:   asset,
				})
				if err != nil {
					errChan <- err
					return
				}
				if resp == nil {
					errChan <- errors.New("GetBalance returned nil response")
					return
				}

				balance, ok := big.NewInt(0).SetString(resp.Balance, 10)
				if !ok {
					errChan <- errors.New("GetBalance returned invalid response")
					return
				}

				mu.Lock()
				if mainBalances[bcCfg.BlockchainId] == nil {
					mainBalances[bcCfg.BlockchainId] = make(map[string]*big.Int)
				}
				mainBalances[bcCfg.BlockchainId][asset] = balance
				mu.Unlock()
			}
		}(bc, assets)
	}

	wg.Wait()
	close(errChan)

	if len(errChan) > 0 {
		return nil, errors.New("error fetching balances")
	}

	return mainBalances, nil
}

// getSystemBalance bcId => asset => balance
func (c *Check) getSystemBalance(sess db.Session, blockchains map[uint64]map[string]bool) (systemBalances map[uint64]map[string]*big.Int, err error) {
	var cfgList []database.Config
	err = sess.SQL().SelectFrom(database.TableOfConfig).All(&cfgList)
	if err != nil {
		return nil, err
	}

	// bc ==> address ==> true
	systemAddresses := make(map[string]map[string]bool)
	for _, cfg := range cfgList {
		vList := strings.Split(cfg.Variable, "-")
		if len(vList) != 3 {
			continue
		}

		bc := fmt.Sprintf("%s-%s", vList[0], vList[1]) // network + chainId
		if _, ok := systemAddresses[bc]; !ok {
			systemAddresses[bc] = make(map[string]bool)
		}

		if cfg.Variable == fmt.Sprintf("%s-%s", bc, utils.WithdrawMainAddress) {
			systemAddresses[bc][cfg.Value] = true
		} else if cfg.Variable == fmt.Sprintf("%s-%s", bc, utils.ColdAddress) {
			systemAddresses[bc][cfg.Value] = true
		} else if cfg.Variable == fmt.Sprintf("%s-%s", bc, utils.ColdAddresses) {
			colds := strings.Split(cfg.Value, utils.ColdAddressesSplit)
			for _, cold := range colds {
				systemAddresses[bc][cold] = true
			}
		}
	}

	if len(blockchains) == 0 || len(systemAddresses) == 0 {
		return nil, fmt.Errorf("no blockchains or main addresses set")
	}

	ctx := context.Background()
	var wg sync.WaitGroup
	var mu sync.Mutex
	errChan := make(chan error, len(blockchains))
	systemBalances = make(map[uint64]map[string]*big.Int) // bcId => asset => balance

	for bcId, assets := range blockchains {
		slug, ok := c.slugs[bcId]
		if !ok {
			continue
		}
		bc, ok := c.blockchains[slug]
		if !ok {
			continue
		}

		wg.Add(1)
		go func(bcCfg *config.ChainConfig, assets map[string]bool) {
			defer wg.Done()

			saMap, ok := systemAddresses[fmt.Sprintf("%s-%s", bcCfg.Network, bcCfg.ChainId)]
			if !ok {
				errChan <- fmt.Errorf("no such main address: %s(%s)", bcCfg.Network, bcCfg.ChainId)
				return
			}

			conn, err := grpc.NewClient(bcCfg.ChainAPIHost, grpc.WithTransportCredentials(insecure.NewCredentials()))
			if err != nil {
				errChan <- err
				return
			}

			client := chainapi.NewChainAPIClient(conn)

			for asset := range assets {
				for a := range saMap {
					resp, err := client.GetBalance(ctx, &chainapi.BalanceRequest{
						Address: a,
						Asset:   asset,
					})
					if err != nil {
						errChan <- err
						return
					}
					if resp == nil {
						errChan <- errors.New("GetBalance returned nil response")
						return
					}

					balance, ok := big.NewInt(0).SetString(resp.Balance, 10)
					if !ok {
						errChan <- errors.New("GetBalance returned invalid response")
						return
					}

					mu.Lock()
					if systemBalances[bcCfg.BlockchainId] == nil {
						systemBalances[bcCfg.BlockchainId] = make(map[string]*big.Int)
					}
					if systemBalances[bcCfg.BlockchainId][asset] == nil {
						systemBalances[bcCfg.BlockchainId][asset] = big.NewInt(0)
					}
					systemBalances[bcCfg.BlockchainId][asset].Add(systemBalances[bcCfg.BlockchainId][asset], balance)
					mu.Unlock()
				}

			}
		}(bc, assets)
	}

	wg.Wait()
	close(errChan)

	if len(errChan) > 0 {
		return nil, errors.New("error fetching balances")
	}

	return systemBalances, nil
}

// getSystemBalance return bcId => asset => balance
func (c *Check) getOnChainBalance(sess db.Session, blockchains map[uint64]map[string]map[string]bool) (systemBalances map[uint64]map[string]*big.Int, err error) {
	if len(blockchains) == 0 {
		return nil, fmt.Errorf("no blockchains set")
	}

	var cfgList []database.Config
	err = sess.SQL().SelectFrom(database.TableOfConfig).All(&cfgList)
	if err != nil {
		return nil, err
	}

	// bc ==> address ==> true
	addresses := make(map[string]map[string]bool)
	for _, cfg := range cfgList {
		vList := strings.Split(cfg.Variable, "-")
		if len(vList) != 3 {
			continue
		}

		bc := fmt.Sprintf("%s-%s", vList[0], vList[1]) // network + chainId
		if _, ok := addresses[bc]; !ok {
			addresses[bc] = make(map[string]bool)
		}

		if cfg.Variable == fmt.Sprintf("%s-%s", bc, utils.WithdrawMainAddress) {
			addresses[bc][cfg.Value] = true
		} else if cfg.Variable == fmt.Sprintf("%s-%s", bc, utils.ColdAddress) {
			addresses[bc][cfg.Value] = true
		} else if cfg.Variable == fmt.Sprintf("%s-%s", bc, utils.ColdAddresses) {
			colds := strings.Split(cfg.Value, utils.ColdAddressesSplit)
			for _, cold := range colds {
				addresses[bc][cold] = true
			}
		}
	}

	// if no main address, no need to check addresses in blockchains
	if len(addresses) == 0 {
		return nil, fmt.Errorf("no main addresses set")
	}

	var wg sync.WaitGroup
	var mu sync.Mutex
	systemBalances = make(map[uint64]map[string]*big.Int) // bcId => asset => balance
	var errOnce sync.Once
	var firstErr error

	for bcId, assets := range blockchains {
		slug, ok := c.slugs[bcId]
		if !ok {
			continue
		}
		bcCfg, ok := c.blockchains[slug]
		if !ok {
			continue
		}

		maMap, ok := addresses[fmt.Sprintf("%s-%s", bcCfg.Network, bcCfg.ChainId)]
		if !ok {
			errOnce.Do(func() {
				firstErr = fmt.Errorf("no main address for blockchain: %s(%s)", bcCfg.Network, bcCfg.ChainId)
			})
			continue
		}

		conn, err := grpc.NewClient(bcCfg.ChainAPIHost, grpc.WithTransportCredentials(insecure.NewCredentials()))
		if err != nil {
			errOnce.Do(func() { firstErr = err })
			continue
		}

		for asset, aMap := range assets {
			if aMap == nil {
				aMap = make(map[string]bool)
			}
			for a := range maMap {
				aMap[a] = true
			}
			for a := range aMap {
				wg.Add(1)
				go func(addr, asset string, conn grpc.ClientConnInterface) {
					defer wg.Done()

					client := chainapi.NewChainAPIClient(conn)
					resp, err := client.GetBalance(context.Background(), &chainapi.BalanceRequest{
						Address: addr,
						Asset:   asset,
					})
					if err != nil || resp == nil {
						errOnce.Do(func() {
							firstErr = fmt.Errorf("GetBalance error for %s: %v", addr, err)
						})
						return
					}

					balance, ok := big.NewInt(0).SetString(resp.Balance, 10)
					if !ok {
						errOnce.Do(func() {
							firstErr = fmt.Errorf("invalid balance format from address %s", addr)
						})
						return
					}

					mu.Lock()
					if systemBalances[bcCfg.BlockchainId] == nil {
						systemBalances[bcCfg.BlockchainId] = make(map[string]*big.Int)
					}
					if systemBalances[bcCfg.BlockchainId][asset] == nil {
						systemBalances[bcCfg.BlockchainId][asset] = big.NewInt(0)
					}
					systemBalances[bcCfg.BlockchainId][asset].Add(systemBalances[bcCfg.BlockchainId][asset], balance)
					mu.Unlock()
				}(a, asset, conn)
			}
		}
	}

	wg.Wait()

	if firstErr != nil {
		return nil, firstErr
	}

	return systemBalances, nil
}

// getBlockHeight return blockchainId => blockHeight
func (c *Check) getBlockHeight(sess db.Session, blockchains []uint64) (blockHeights map[uint64]uint64, err error) {
	var cfgList []database.Config
	err = sess.SQL().SelectFrom(database.TableOfConfig).All(&cfgList)
	if err != nil {
		return nil, err
	}

	if len(blockchains) == 0 {
		return nil, fmt.Errorf("no blockchains or main addresses set")
	}

	ctx := context.Background()
	var wg sync.WaitGroup
	var mu sync.Mutex
	errChan := make(chan error, len(blockchains))
	blockHeights = make(map[uint64]uint64) // bcId => blockHeight

	for _, bcId := range blockchains {
		slug, ok := c.slugs[bcId]
		if !ok {
			continue
		}
		bc, ok := c.blockchains[slug]
		if !ok {
			continue
		}

		wg.Add(1)
		go func(bcCfg *config.ChainConfig) {
			defer wg.Done()

			conn, err := grpc.NewClient(bcCfg.ChainAPIHost, grpc.WithTransportCredentials(insecure.NewCredentials()))
			if err != nil {
				errChan <- err
				return
			}

			client := chainapi.NewChainAPIClient(conn)

			resp, err := client.GetBlockNumber(ctx, &chainapi.BlockNumberRequest{})

			if err != nil {
				errChan <- err
				return
			}
			if resp == nil {
				errChan <- errors.New("GetBalance returned nil response")
				return
			}

			mu.Lock()
			blockHeights[bcCfg.BlockchainId] = resp.Number
			mu.Unlock()

		}(bc)
	}

	wg.Wait()
	close(errChan)

	if len(errChan) > 0 {
		return nil, errors.New("error fetching balances")
	}

	return blockHeights, nil
}

func GetChainInfo(target string) (*chainapi.ChainInfoReply, error) {
	conn, err := grpc.NewClient(target, grpc.WithTransportCredentials(insecure.NewCredentials()))
	if err != nil {
		return nil, err
	}
	defer conn.Close()
	ec := chainapi.NewChainAPIClient(conn)

	return ec.GetChainInfo(context.Background(), &chainapi.ChainInfoRequest{})
}

func (c *Check) getTotalFee(sess db.Session, blockchainId uint64) (*big.Int, error) {

	var tasksList []database.Task
	err := sess.SQL().SelectFrom("tasks").Where("blockchain_id", blockchainId).All(&tasksList)
	if err != nil {
		return nil, err
	}

	totalFee := big.NewInt(0)
	for _, task := range tasksList {
		if task.ActionType == utils.TasksActionTypeOfNewBridge ||
			task.ActionType == utils.TasksActionTypeOfManagerMerge ||
			task.ActionType == utils.TasksActionTypeOfCold {
			if task.Fee == "" {
				continue
			}
			fee, ok := big.NewInt(0).SetString(task.Fee, 10)
			if !ok {
				return nil, fmt.Errorf("invalid fee %s", task.Fee)
			}

			totalFee.Add(totalFee, fee)
		} else if task.ActionType == utils.TasksActionTypeOfManagerCharge {
			if task.Fee != "" {
				fee, ok := big.NewInt(0).SetString(task.Fee, 10)
				if !ok {
					return nil, fmt.Errorf("invalid fee %s", task.Fee)
				}

				totalFee.Add(totalFee, fee)
			}

			if task.Value != "" {
				amount, ok := big.NewInt(0).SetString(task.Value, 10)
				if !ok {
					return nil, fmt.Errorf("invalid value %s", task.Fee)
				}

				totalFee.Add(totalFee, amount)
			}
		}
	}

	return totalFee, nil
}

func getAssetInfo(target string, asset string) (*chainapi.AssetInfoReply, error) {
	conn, err := grpc.NewClient(target, grpc.WithTransportCredentials(insecure.NewCredentials()))
	if err != nil {
		return nil, err
	}
	defer conn.Close()
	ec := chainapi.NewChainAPIClient(conn)

	return ec.GetAssetInfo(context.Background(), &chainapi.AssetInfoRequest{Asset: asset})
}
