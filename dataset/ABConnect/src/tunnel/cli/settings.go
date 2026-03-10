package cli

import (
	"errors"
	"fmt"
	"math/big"
	"os"
	"regexp"

	"github.com/olekukonko/tablewriter"
	"github.com/sirupsen/logrus"
	"github.com/spf13/cobra"
	db "github.com/upper/db/v4"
	"gitlab.weinvent.org/yangchenzhong/tunnel/database"
	"gitlab.weinvent.org/yangchenzhong/tunnel/utils"
	"gitlab.weinvent.org/yangchenzhong/tunnel/utils/config"
)

/*
 * disable auto_confirm
 * enable auto_confirm
 * confirm tx_hash
 */

func (cli *CLI) buildConfigCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:                   "config <disable|enable|list>",
		Short:                 "Manager system config",
		DisableFlagsInUseLine: true,
		Args:                  cobra.MinimumNArgs(1),
		Run: func(cmd *cobra.Command, args []string) {
			fmt.Fprint(os.Stderr, cmd.UsageString())

			os.Exit(-1)
		},
	}

	cmd.AddCommand(cli.buildConfigDisableCmd())
	cmd.AddCommand(cli.buildConfigEnableCmd())
	cmd.AddCommand(cli.buildConfigListCmd())

	return cmd
}

const (
	DisableAutoConfirm = iota
	EnableAutoConfirm
)

func (cli *CLI) buildConfigDisableCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:                   "disable <auto_confirm>",
		Short:                 "Disable specified feature",
		DisableFlagsInUseLine: true,
		Args:                  cobra.MinimumNArgs(1),
		Run: func(cmd *cobra.Command, args []string) {
			fmt.Fprint(os.Stderr, cmd.UsageString())

			os.Exit(-1)
		},
	}

	cmd.AddCommand(cli.buildConfigDisableAutoConfirmCmd())

	return cmd
}

func (cli *CLI) buildConfigEnableCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:                   "enable <auto_confirm>",
		Short:                 "Enable specified feature",
		DisableFlagsInUseLine: true,
		Args:                  cobra.MinimumNArgs(1),
		Run: func(cmd *cobra.Command, args []string) {
			fmt.Fprint(os.Stderr, cmd.UsageString())

			os.Exit(-1)
		},
	}

	cmd.AddCommand(cli.buildConfigEnableAutoConfirmCmd())

	return cmd
}

func (cli *CLI) buildConfigListCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:                   "list",
		Short:                 "List config",
		DisableFlagsInUseLine: true,
		Run: func(cmd *cobra.Command, args []string) {
			cli.configList(cmd, args)
		},
	}

	return cmd
}

func (cli *CLI) buildConfigDisableAutoConfirmCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:                   "auto_confirm",
		Short:                 "Disable auto_confirm",
		DisableFlagsInUseLine: true,
		Run: func(cmd *cobra.Command, args []string) {
			cli.autoConfirmCmd(cmd, args, DisableAutoConfirm)
		},
	}

	return cmd
}

func (cli *CLI) buildConfigEnableAutoConfirmCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:                   "auto_confirm",
		Short:                 "Enable auto_confirm",
		DisableFlagsInUseLine: true,
		Run: func(cmd *cobra.Command, args []string) {
			cli.autoConfirmCmd(cmd, args, EnableAutoConfirm)
		},
	}

	return cmd
}

func (cli *CLI) autoConfirmCmd(cmd *cobra.Command, args []string, action int) {

	cb, err := loadBridge()
	if err != nil {
		fmt.Println(err)
		return
	}

	// open db
	sess, err := database.OpenDatabase(cb.DB.Adapter, cb.DB.ConnectionURL)
	if err != nil {
		fmt.Println("Open db err: ", err)
		return
	}
	defer sess.Close()

	// update config
	autoConfirmValue := utils.AutoConfirmDefault
	if action == DisableAutoConfirm {
		autoConfirmValue = utils.AutoConfirmDisable
	}

	// INSERT INTO config (variable, value) VALUES("", 1) ON DUPLICATE KEY UPDATE value = 1;
	sqlStr := fmt.Sprintf(`INSERT INTO config(variable, value) VALUES("%s", "%v")
		 ON DUPLICATE KEY UPDATE value = "%v"`,
		utils.AutoConfirm.Text(), autoConfirmValue, autoConfirmValue)

	_, err = sess.SQL().Exec(sqlStr)
	if err != nil {
		fmt.Println("Update db error: ", err)
		return
	}

	if autoConfirmValue == utils.AutoConfirmDefault {
		fmt.Println(utils.AutoConfirm.String(), "enabled")
	} else {
		fmt.Println(utils.AutoConfirm.String(), "disabled")
	}

	return
}

func (cli *CLI) configList(cmd *cobra.Command, args []string) {

	cb, err := loadBridge()
	if err != nil {
		fmt.Println(err)
		return
	}

	// load default
	scDefault := utils.GetSystemConfigDefaultText()

	// open db
	sess, err := database.OpenDatabase(cb.DB.Adapter, cb.DB.ConnectionURL)
	if err != nil {
		fmt.Println("Open db err: ", err)
		return
	}
	defer sess.Close()

	var configList []struct {
		Variable string `db:"variable"`
		Value    string `db:"value"`
	}
	err = sess.SQL().Select("variable", "value").From(database.TableOfConfig).Where(
		"variable like", fmt.Sprintf("%s%%", utils.SystemConfigPrefix)).All(&configList)
	if err != nil {
		fmt.Println("Update db error: ", err)
		return
	}

	for _, c := range configList {
		sc := utils.SystemConfigUnmarshal(c.Variable)
		if sc == utils.Default {
			fmt.Printf("Unmarshal %s error\n", c.Variable)
			continue
		}
		scDefault[sc] = c.Value
	}

	table := tablewriter.NewWriter(os.Stdout)
	table.SetHeader([]string{"Key", "Value"})
	for k, v := range scDefault {
		table.Append([]string{k.String(), fmt.Sprintf("%v", v)})
	}
	table.Render()

	return
}

func (cli *CLI) buildConfirmCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:                   "confirm <list|tx_hash>",
		Short:                 "Confirm the deposit tx hash",
		DisableFlagsInUseLine: true,
		Args:                  cobra.MinimumNArgs(1),
		Aliases:               []string{"approve"},
		Run: func(cmd *cobra.Command, args []string) {

			var err error

			cb, err := loadBridge()
			if err != nil {
				fmt.Println(err)
				return
			}

			// open db
			sess, err := database.OpenDatabase(cb.DB.Adapter, cb.DB.ConnectionURL)
			if err != nil {
				fmt.Println("Open db err: ", err)
				return
			}
			defer sess.Close()

			if args[0] == "list" {
				var historyList []database.HistoryDetail
				err := sess.SQL().Select(
					"h.*",
					"a1.id AS asset_id",
					"a1.name AS asset_name",
					"a1.symbol AS asset_symbol",
					"a1.decimals AS asset_decimals",
					"a1.asset_type AS asset_type",
					"b1.network AS network",
					"b1.chain_id AS chain_id",
					"b1.base_chain AS base_chain",
					"a2.id AS target_asset_id",
					"a2.name AS target_asset_name",
					"a2.symbol AS target_asset_symbol",
					"a2.decimals AS target_asset_decimals",
					"a2.asset_type AS target_asset_type",
					"b2.network AS target_network",
					"b2.chain_id AS target_chain_id",
					"b2.base_chain AS target_base_chain").From("history h").
					LeftJoin("assets a1").On("h.blockchain_id = a1.blockchain_id and h.asset = a1.asset").
					LeftJoin("blockchains b1").On("a1.blockchain_id = b1.id").
					LeftJoin("assets a2").On("h.target_blockchain_id = a2.blockchain_id and h.target_asset = a2.asset").
					LeftJoin("blockchains b2").On("a2.blockchain_id = b2.id").Where("h.status", utils.BridgeDeposit).OrderBy("h.id DESC").All(&historyList)
				if err != nil {
					fmt.Println(err)
					return
				}
				if len(historyList) == 0 {
					fmt.Println("No transaction need to be confirmed.")
					return
				}

				fmt.Println("These transactions have been confirmed on the chain and require manual confirmation:")
				table := tablewriter.NewWriter(os.Stdout)
				table.SetColumnAlignment([]int{
					tablewriter.ALIGN_RIGHT,
					tablewriter.ALIGN_LEFT,
				})
				table.SetAutoWrapText(false)
				table.SetBorder(false)
				table.SetColumnSeparator("")
				table.SetRowSeparator("")
				table.SetCenterSeparator("")
				if true {

					for i, h := range historyList {
						fmt.Printf("*************************** %v. row ***************************\n", i+1)

						amount, ok := big.NewInt(0).SetString(h.Amount, 10)
						if !ok {
							fmt.Println("Amount error: ", h.Amount)
							return
						}

						table.Append([]string{"Id:", fmt.Sprintf("%d", h.Id)})
						table.Append([]string{"Network:", h.Network})
						table.Append([]string{"InternalAddress:", h.Address})
						table.Append([]string{"Asset:", h.Asset})
						table.Append([]string{"AssetName:", h.AssetName})
						table.Append([]string{"BlockNumber:", fmt.Sprintf("%v", h.BlockNumber)})
						table.Append([]string{"TxHash:", h.TxHash})
						table.Append([]string{"TxIndex:", fmt.Sprintf("%v", h.TxIndex)})
						table.Append([]string{"Sender:", h.Sender})
						table.Append([]string{"Amount:", fmt.Sprintf("%v (%s %v)", h.Amount, utils.GetAmountTextFromISAACWithDecimals(amount, h.AssetDecimals), h.AssetSymbol)})

						table.Render()
						table.ClearRows()
					}

					return
				}
			}

			hash := args[0]
			re := regexp.MustCompile(`^(0x)?[a-fA-F0-9]{64}$`)
			if !re.MatchString(hash) {
				fmt.Println("Hash invalid: ", hash)
				return
			}

			var history database.History
			err = sess.SQL().SelectFrom("history").Where(
				"tx_hash", hash).One(&history)
			if errors.Is(err, db.ErrNoMoreRows) {
				log.WithFields(logrus.Fields{
					"tx_hash": hash,
				}).Errorln("not such tx hash")
				return
			} else if err != nil {
				fmt.Println(err)
				return
			}

			if history.Id == 0 {
				fmt.Println("Get history id error")
				return
			}
			if history.Status == utils.BridgeDeposit {

			} else if history.Status == utils.BridgeDepositConfirmed {
				log.WithFields(logrus.Fields{
					"tx_hash": hash,
					"id":      history.Id,
				}).Info("tx hash been confirmed")
				return
			} else {
				log.WithFields(logrus.Fields{
					"tx_hash": hash,
					"id":      history.Id,
					"status":  history.Status,
				}).Errorln("not support status for cmd confirm")
				return
			}

			var blockchain database.Blockchain
			err = sess.SQL().SelectFrom(database.TableOfBlockchains).Where("id", history.BlockchainId).One(&blockchain)
			if err != nil {
				fmt.Println(err)
				return
			}
			var bcCfg *config.ChainConfig
			for _, cfg := range cb.Router.Blockchains {
				if cfg.Network == blockchain.Network && cfg.ChainId == blockchain.ChainId {
					bcCfg = cfg
					break
				}
			}
			if bcCfg == nil {
				fmt.Println("blockchain config not found")
				return
			}
			if !database.Verify(&history, bcCfg.MonitorSignKeyId) && !database.Verify(&history, cb.CoreSignKeyId) {
				fmt.Println("history invalid: ", history.Id)
				return
			}

			err = sess.Tx(func(dbTx db.Session) error {
				_, err = dbTx.SQL().Update("history").Set(
					"status", utils.BridgeDepositConfirmed).Where(
					"status", utils.BridgeDeposit).And(
					"id", history.Id).Exec()
				if err != nil {
					return err
				}

				err = database.UpdateSign(dbTx, database.TableOfHistory, history.Id, cb.ToolsSignKeyId)
				if err != nil {
					return err
				}

				return nil
			})
			if err != nil {
				fmt.Println(err)
				return
			}

			log.WithFields(logrus.Fields{
				"tx_hash": hash,
				"id":      history.Id,
			}).Info("tx hash confirmed")
		},
	}

	return cmd
}
