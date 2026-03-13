package cli

import (
	"crypto/elliptic"
	"encoding/json"
	"errors"
	"fmt"
	"math/big"
	"os"
	"strings"

	dbtcutil "github.com/dogecoinw/doged/btcutil"
	dchaincfg "github.com/dogecoinw/doged/chaincfg"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/crypto"
	"github.com/spf13/cobra"
	"github.com/spf13/viper"
	db "github.com/upper/db/v4"
	"gitlab.weinvent.org/yangchenzhong/tunnel/blockchain"
	"gitlab.weinvent.org/yangchenzhong/tunnel/chain"
	"gitlab.weinvent.org/yangchenzhong/tunnel/database"
	"gitlab.weinvent.org/yangchenzhong/tunnel/utils"
	"gitlab.weinvent.org/yangchenzhong/tunnel/utils/coins/newton"
	"gitlab.weinvent.org/yangchenzhong/tunnel/utils/config"
)

func (cli *CLI) buildChainCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:                   "chain <api|init|tasks|manager|version>",
		Short:                 "Run as XChain API server",
		DisableFlagsInUseLine: true,
		Args:                  cobra.MinimumNArgs(1),
		Run: func(cmd *cobra.Command, args []string) {
			fmt.Fprint(os.Stderr, cmd.UsageString())

			os.Exit(-1)
		},
	}

	cmd.AddCommand(cli.buildActionAPICmd())
	cmd.AddCommand(cli.buildActionInitCmd())
	cmd.AddCommand(cli.buildActionTasksCmd())
	cmd.AddCommand(cli.buildChainVersionCmd())
	cmd.AddCommand(cli.buildManagerCmd())

	cmd.PersistentFlags().Bool("standard", false, "Use StandardScrypt for keystore, default is LightScrypt")
	cmd.PersistentFlags().StringP("walletype", "w", "", "The wallet type of aws 'kms' or node 'rpc'")

	cmd.PersistentFlags().Bool("skip", false, "Skip onchain verification for blockchain")

	return cmd
}

func (cli *CLI) buildActionAPICmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:                   "api",
		Short:                 "Run as XChain API server",
		DisableFlagsInUseLine: true,
		Run: func(cmd *cobra.Command, args []string) {
			cli.runChain(cmd, args, chain.ActionAPI)
		},
	}

	return cmd
}

func (cli *CLI) buildActionTasksCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:                   "tasks",
		Short:                 "Run XChain tasks to send and check txs",
		DisableFlagsInUseLine: true,
		Run: func(cmd *cobra.Command, args []string) {
			cli.runChain(cmd, args, chain.ActionTasks)

		},
	}

	return cmd
}

func (cli *CLI) runChain(cmd *cobra.Command, args []string, action int) {
	var err error

	cb, err := loadBridge()
	if err != nil {
		fmt.Println(err)
		return
	}

	skipOnChainVerify, _ := cmd.Flags().GetBool("skip")
	err = handleBlockchainWithOption(cb, skipOnChainVerify)
	if err != nil {
		fmt.Println(err)
		return
	}

	var walletType chain.WalletType
	if cmd.Flags().Changed("wallet") {
		x, err := cmd.Flags().GetString("wallet")
		if err != nil {
			fmt.Println(err)
			return
		}
		err = walletType.UnmarshalText([]byte(x))
		if err != nil {
			fmt.Println(err)
			return
		}
	} else {
		log.Warnln("use default wallet type of WalletKMS")
		walletType = chain.WalletKMS
	}

	if action == chain.ActionTasks {
		err = applyDB(cb)
		if err != nil {
			fmt.Println(err)
			return
		}

		err = applyChainDB(cb)
		if err != nil {
			fmt.Println(err)
			return
		}
	}

	cbb, err := json.MarshalIndent(*cb, "", " ")
	if err != nil {
		fmt.Println(err)
		return
	}
	fmt.Println(string(cbb))

	c, err := chain.New(cb, walletType)
	if err != nil {
		fmt.Println(err)
		return
	}

	if action == chain.ActionAPI {
		script := chain.ScryptLight
		if useStandard, _ := cmd.Flags().GetBool("standard"); useStandard {
			script = chain.ScryptStandard
			log.Warnln("use ScryptStandard for keystore")
		} else {
			log.Warnln("use default ScryptLight for keystore")
		}
		if err := c.SetScript(script); err != nil {
			fmt.Println(err)
			return
		}

		hostAddress := cb.Blockchain.ChainAPIHost

		network := viper.GetString("network")
		if network == "" {
			network = "tcp"
		}

		log.Printf("Listening at %s:%v...", network, hostAddress)

		if err := c.RunAPIServer(network, hostAddress); err != nil {
			fmt.Println(err)
			return
		}
	} else if action == chain.ActionTasks {
		if err := c.RunTasks(); err != nil {
			fmt.Println(err)
			return
		}
	}

	return
}

func isP256() bool {
	p1 := crypto.S256().Params()
	p2 := elliptic.P256().Params()

	return p1.Gx.Cmp(p2.Gx) == 0 &&
		p1.Gy.Cmp(p2.Gy) == 0 &&
		p1.N.Cmp(p2.N) == 0 &&
		p1.B.Cmp(p2.B) == 0
}

func ChainVersion() string {
	if isP256() {
		return fmt.Sprintf("%v-%v", utils.Version(), blockchain.NewChain.String())
	}

	return fmt.Sprintf("%v-%v", utils.Version(), blockchain.Ethereum.String())
}

func (cli *CLI) buildChainVersionCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:                   "version",
		Short:                 "Get chain version",
		DisableFlagsInUseLine: true,
		Run: func(cmd *cobra.Command, args []string) {
			fmt.Println(ChainVersion())
		},
	}

	return cmd
}

func (cli *CLI) buildActionInitCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:                   "init [cold|fee] [--skip]",
		Short:                 "Initialize main withdraw address",
		DisableFlagsInUseLine: true,
		Run: func(cmd *cobra.Command, args []string) {
			// config.toml
			// run AChain API
			// run BChain API
			// run chain init

			var err error

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

			skipOnChainVerify, _ := cmd.Flags().GetBool("skip")
			err = handleBlockchainWithOption(&b, skipOnChainVerify)
			if err != nil {
				fmt.Println(err)
				return
			}
			baseChain := b.Blockchain.BaseChain
			if baseChain == blockchain.UnknownChain {
				fmt.Println("base chain unknown")
				return
			}

			// err = CheckChain(&b)
			// if err != nil {
			// 	fmt.Println(err)
			// 	return
			// }

			sess, err := database.OpenDatabase(b.DB.Adapter, b.DB.ConnectionURL)
			if err != nil {
				fmt.Println(err)
				return
			}
			defer sess.Close()

			name := fmt.Sprintf("%s-%s-%s",
				b.Blockchain.Network,
				b.Blockchain.ChainId,
				utils.WithdrawMainAddress)
			var vList []struct {
				Variable string `db:"variable"`
				Value    string `db:"value"`
			}
			err = sess.SQL().Select("variable", "value").From("config").Where("variable", name).All(&vList)
			if err == db.ErrNoMoreRows {

			} else if err != nil {
				fmt.Println(err)
				return
			}

			if len(vList) == 0 {

			} else if len(vList) != 1 {
				fmt.Println("len error: ", len(vList))
				return
			} else {
				v := vList[0]
				switch baseChain {
				case blockchain.Dogecoin:
					address, err := dbtcutil.DecodeAddress(v.Value, &dchaincfg.MainNetParams)
					if err != nil {
						fmt.Println("convert string to address error: ", v.Value)
						return
					}
					fmt.Println(v.Variable, address.String())
				case blockchain.Ethereum, blockchain.NewChain:
					if !common.IsHexAddress(v.Value) {
						fmt.Println("convert string to address error: ", v.Value)
						return
					}
					fmt.Println(v.Variable, common.HexToAddress(v.Value).String())
				default:
					fmt.Println("config variable error: ", v.Variable)
					return
				}

				fmt.Println("main withdraw address has inited")
				return
			}

			// create
			var (
				wm config.Address
			)
			if baseChain == blockchain.Dogecoin {
				wm, err = createInternalDogecoinAddress(name, b.Blockchain.ChainAPIHost)

			} else {
				wm, err = createInternalAddress(name, b.Blockchain.ChainAPIHost)
			}
			if err != nil {
				fmt.Println(err)
				return
			}

			fmt.Printf("%s is: %s\n", name, wm.String())

			err = sess.Tx(func(tx db.Session) error {
				_, err := tx.SQL().InsertInto(database.TableOfConfig).Columns(
					"variable", "value").Values(
					name, wm.String()).Exec()
				if err != nil {
					return err
				}

				err = database.UpdateConfigSign(tx, name, b.ToolsSignKeyId)
				if err != nil {
					return err
				}

				return nil
			})
			if err != nil {
				fmt.Println(err)
				return
			}

			err = sess.SQL().Select("variable", "value").From(
				database.TableOfConfig).Where("variable", name).All(&vList)
			if err == db.ErrNoMoreRows {
				fmt.Println("init to db fail")
				return
			} else if err != nil {
				fmt.Println(err)
				return
			}

			if len(vList) != 1 {
				fmt.Println("len error: ", len(vList))
				return
			}
			v := vList[0]
			switch baseChain {
			case blockchain.Dogecoin:
				address, err := dbtcutil.DecodeAddress(v.Value, &dchaincfg.MainNetParams)
				if err != nil {
					fmt.Println("convert string to address error: ", v.Value)
					return
				}
				fmt.Println(v.Variable, address.String())
			case blockchain.Ethereum, blockchain.NewChain:
				if !common.IsHexAddress(v.Value) {
					fmt.Println("convert string to address error: ", v.Value)
					return
				}
				fmt.Println(v.Variable, common.HexToAddress(v.Value).String())
			default:
				fmt.Println("config variable error: ", v.Variable)
				return
			}

			return

		},
	}

	cmd.AddCommand(cli.buildActionInitColdCmd())
	cmd.AddCommand(cli.buildActionInitFeeCmd())

	return cmd
}

func (cli *CLI) buildActionInitColdCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:                   "cold <address|empty>",
		Short:                 "Initialize or remove cold address",
		DisableFlagsInUseLine: true,
		Args:                  cobra.ExactArgs(1),
		Run: func(cmd *cobra.Command, args []string) {
			var err error

			coldStr := args[0]

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

			err = handleBlockchain(&b)
			if err != nil {
				fmt.Println(err)
				return
			}
			baseChain := b.Blockchain.BaseChain
			if baseChain == blockchain.UnknownChain {
				fmt.Println("base chain unknown")
				return
			}

			coldName := fmt.Sprintf("%s-%s-%s",
				b.Blockchain.Network,
				b.Blockchain.ChainId,
				utils.ColdAddress)

			sess, err := database.OpenDatabase(b.DB.Adapter, b.DB.ConnectionURL)
			if err != nil {
				fmt.Println(err)
				return
			}
			defer sess.Close()

			var cfg *database.Config
			err = sess.SQL().SelectFrom("config").Where("variable", coldName).One(&cfg)
			if err == db.ErrNoMoreRows {

			} else if err != nil {
				fmt.Println(err)
				return
			}

			if cfg == nil {
			} else {
				switch baseChain {
				case blockchain.Dogecoin:
					address, err := dbtcutil.DecodeAddress(cfg.Value, &dchaincfg.MainNetParams)
					if err != nil {
						fmt.Println("convert string to address error: ", cfg.Value)
						return
					}
					fmt.Println(cfg.Variable, address.String())
				case blockchain.Ethereum, blockchain.NewChain:
					if !common.IsHexAddress(cfg.Value) {
						fmt.Println("convert string to address error: ", cfg.Value)
						return
					}
					fmt.Println(cfg.Variable, common.HexToAddress(cfg.Value).String())
				default:
					fmt.Println("config variable error: ", cfg.Variable)
					return
				}

				if coldStr == "" {
					fmt.Println("try to delete cold address...")
					if !utils.Confirm() {
						fmt.Println("delete cold address canceled.")
						return
					}

					err = sess.Tx(func(dbtx db.Session) error {
						_, err = dbtx.SQL().DeleteFrom(database.TableOfConfig).Where("variable", coldName).Exec()
						if err != nil {
							fmt.Println(err)
							return err
						}

						usedColdsName := fmt.Sprintf("%s-%s-%s",
							b.Blockchain.Network,
							b.Blockchain.ChainId,
							utils.ColdAddresses)
						var usedColdsNameCfg database.Config
						err = dbtx.SQL().SelectFrom("config").Where("variable", usedColdsName).One(&usedColdsNameCfg)
						if errors.Is(err, db.ErrNoMoreRows) {
							_, err = dbtx.SQL().InsertInto(database.TableOfConfig).Columns("variable", "value").Values(
								usedColdsName, cfg.Value).Exec()
							if err != nil {
								return err
							}
						} else if err != nil {
							fmt.Println(err)
							return err
						} else {
							usedColdsMap := make(map[string]bool)
							if usedColdsNameCfg.Value != "" {
								usedColsList := strings.Split(usedColdsNameCfg.Value, ",")
								for _, usedColsStr := range usedColsList {
									usedColdsMap[usedColsStr] = true
								}
							}
							usedColdsMap[cfg.Value] = true

							useColdsList := make([]string, 0)
							for usedColsStr := range usedColdsMap {
								useColdsList = append(useColdsList, usedColsStr)
							}

							_, err = dbtx.SQL().Update(database.TableOfConfig).Set(
								"value", strings.Join(useColdsList, ","),
								"sign_info", "").Where("variable", usedColdsName).Exec()
							if err != nil {
								return err
							}
						}

						err = database.UpdateConfigSign(dbtx, usedColdsName, b.ToolsSignKeyId)
						if err != nil {
							fmt.Println("UpdateConfigSign err: ", err)
							return err
						}

						return nil
					})
					if err != nil {
						fmt.Println(err)
						return
					}
					fmt.Println("Cold address has been deleted.")

					return
				}

				fmt.Println("cold address has initialized")
				return
			}

			if coldStr == "" {
				fmt.Println("No cold address set.")
				return
			}

			var (
				wm config.Address
			)

			err = nil
			switch baseChain {
			case blockchain.Dogecoin:
				wm, err = dbtcutil.DecodeAddress(coldStr, &dchaincfg.MainNetParams)
			case blockchain.Ethereum:
				if !common.IsHexAddress(coldStr) {
					fmt.Println("convert string to address error: ", coldStr)
					return
				}
				wm = common.HexToAddress(coldStr)
			case blockchain.NewChain:
				chainId, ok := big.NewInt(0).SetString(b.Blockchain.ChainId, 10)
				if !ok {
					fmt.Println("convert chain id to big int error")
					return
				}

				if coldStr[:3] == "NEW" {
					wm, err = newton.ToAddress(chainId, coldStr)
					if err != nil {
						fmt.Println(err)
						return
					}
				} else {
					if !common.IsHexAddress(coldStr) {
						fmt.Println("convert string to address error: ", coldStr)
						return
					}
					wm = common.HexToAddress(coldStr)
				}
			default:
				fmt.Println("unknown BaseChain", baseChain.String())
				return
			}
			if err != nil {
				fmt.Println(err)
				return
			}

			fmt.Printf("%s is: %s\n", coldName, wm.String())

			if !utils.Confirm() {
				fmt.Println("add cold address canceled.")
				return
			}
			err = sess.Tx(func(tx db.Session) error {
				_, err := tx.SQL().InsertInto(database.TableOfConfig).Columns(
					"variable", "value").Values(
					coldName, wm.String()).Exec()
				if err != nil {
					fmt.Println("InsertInto error: ", err)
					return err
				}

				err = database.UpdateConfigSign(tx, coldName, b.ToolsSignKeyId)
				if err != nil {
					fmt.Println("UpdateConfigSign err: ", err)
					return err
				}

				return nil
			})
			if err != nil {
				fmt.Println(err)
				return
			}

			err = sess.SQL().SelectFrom(
				database.TableOfConfig).Where("variable", coldName).One(&cfg)
			if err == db.ErrNoMoreRows {
				fmt.Println("init to db failed")
				return
			} else if err != nil {
				fmt.Println(err)
				return
			}

			if cfg == nil {
				fmt.Println("init to db fail while select is nil")
				return
			}
			switch baseChain {
			case blockchain.Dogecoin:
				address, err := dbtcutil.DecodeAddress(cfg.Value, &dchaincfg.MainNetParams)
				if err != nil {
					fmt.Println("convert string to address error: ", cfg.Value)
					return
				}
				fmt.Println(cfg.Variable, address.String())
			case blockchain.Ethereum, blockchain.NewChain:
				if !common.IsHexAddress(cfg.Value) {
					fmt.Println("convert string to address error: ", cfg.Value)
					return
				}
				fmt.Println(cfg.Variable, common.HexToAddress(cfg.Value).String())
			default:
				fmt.Println("config variable error: ", cfg.Variable)
				return
			}

			return

		},
	}

	return cmd
}

func (cli *CLI) buildActionInitFeeCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:                   "fee <address|empty>",
		Short:                 "Initialize or remove fee address",
		DisableFlagsInUseLine: true,
		Args:                  cobra.ExactArgs(1),
		Run: func(cmd *cobra.Command, args []string) {
			var err error

			feeStr := args[0]

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

			err = handleBlockchain(&b)
			if err != nil {
				fmt.Println(err)
				return
			}
			baseChain := b.Blockchain.BaseChain
			if baseChain == blockchain.UnknownChain {
				fmt.Println("base chain unknown")
				return
			}

			feeName := fmt.Sprintf("%s-%s-%s",
				b.Blockchain.Network,
				b.Blockchain.ChainId,
				utils.FeeAddress)

			sess, err := database.OpenDatabase(b.DB.Adapter, b.DB.ConnectionURL)
			if err != nil {
				fmt.Println(err)
				return
			}
			defer sess.Close()

			var cfg *database.Config
			err = sess.SQL().SelectFrom("config").Where("variable", feeName).One(&cfg)
			if err == db.ErrNoMoreRows {

			} else if err != nil {
				fmt.Println(err)
				return
			}

			if cfg == nil {
			} else {
				switch baseChain {
				case blockchain.Dogecoin:
					address, err := dbtcutil.DecodeAddress(cfg.Value, &dchaincfg.MainNetParams)
					if err != nil {
						fmt.Println("convert string to address error: ", cfg.Value)
						return
					}
					fmt.Println(cfg.Variable, address.String())
				case blockchain.Ethereum, blockchain.NewChain:
					if !common.IsHexAddress(cfg.Value) {
						fmt.Println("convert string to address error: ", cfg.Value)
						return
					}
					fmt.Println(cfg.Variable, common.HexToAddress(cfg.Value).String())
				default:
					fmt.Println("config variable error: ", cfg.Variable)
					return
				}

				if feeStr == "" {
					fmt.Println("try to delete fee address...")
					if !utils.Confirm() {
						fmt.Println("delete fee address canceled.")
						return
					}

					err = sess.Tx(func(dbtx db.Session) error {
						_, err = dbtx.SQL().DeleteFrom(database.TableOfConfig).Where("variable", feeName).Exec()
						if err != nil {
							fmt.Println(err)
							return err
						}

						return nil
					})
					if err != nil {
						fmt.Println(err)
						return
					}
					fmt.Println("fee address has been deleted.")

					return
				}

				fmt.Println("fee address has initialized")
				return
			}

			if feeStr == "" {
				fmt.Println("No fee address set.")
				return
			}

			var (
				wm config.Address
			)

			err = nil
			switch baseChain {
			case blockchain.Dogecoin:
				wm, err = dbtcutil.DecodeAddress(feeStr, &dchaincfg.MainNetParams)
			case blockchain.Ethereum:
				if !common.IsHexAddress(feeStr) {
					fmt.Println("convert string to address error: ", feeStr)
					return
				}
				wm = common.HexToAddress(feeStr)
			case blockchain.NewChain:
				chainId, ok := big.NewInt(0).SetString(b.Blockchain.ChainId, 10)
				if !ok {
					fmt.Println("convert chain id to big int error")
					return
				}

				if feeStr[:3] == "NEW" {
					wm, err = newton.ToAddress(chainId, feeStr)
					if err != nil {
						fmt.Println(err)
						return
					}
				} else {
					if !common.IsHexAddress(feeStr) {
						fmt.Println("convert string to address error: ", feeStr)
						return
					}
					wm = common.HexToAddress(feeStr)
				}
			default:
				fmt.Println("unknown BaseChain", baseChain.String())
				return
			}
			if err != nil {
				fmt.Println(err)
				return
			}

			fmt.Printf("%s is: %s\n", feeName, wm.String())

			if !utils.Confirm() {
				fmt.Println("add fee address canceled.")
				return
			}
			err = sess.Tx(func(tx db.Session) error {
				_, err := tx.SQL().InsertInto(database.TableOfConfig).Columns(
					"variable", "value").Values(
					feeName, wm.String()).Exec()
				if err != nil {
					fmt.Println("InsertInto error: ", err)
					return err
				}

				err = database.UpdateConfigSign(tx, feeName, b.ToolsSignKeyId)
				if err != nil {
					fmt.Println("UpdateConfigSign err: ", err)
					return err
				}

				return nil
			})
			if err != nil {
				fmt.Println(err)
				return
			}

			err = sess.SQL().SelectFrom(
				database.TableOfConfig).Where("variable", feeName).One(&cfg)
			if err == db.ErrNoMoreRows {
				fmt.Println("init to db failed")
				return
			} else if err != nil {
				fmt.Println(err)
				return
			}

			if cfg == nil {
				fmt.Println("init to db fail while select is nil")
				return
			}
			switch baseChain {
			case blockchain.Dogecoin:
				address, err := dbtcutil.DecodeAddress(cfg.Value, &dchaincfg.MainNetParams)
				if err != nil {
					fmt.Println("convert string to address error: ", cfg.Value)
					return
				}
				fmt.Println(cfg.Variable, address.String())
			case blockchain.Ethereum, blockchain.NewChain:
				if !common.IsHexAddress(cfg.Value) {
					fmt.Println("convert string to address error: ", cfg.Value)
					return
				}
				fmt.Println(cfg.Variable, common.HexToAddress(cfg.Value).String())
			default:
				fmt.Println("config variable error: ", cfg.Variable)
				return
			}

			return

		},
	}

	return cmd
}
