package cli

import (
	"encoding/json"
	"fmt"

	"github.com/spf13/cobra"
	"github.com/spf13/viper"
	"gitlab.weinvent.org/yangchenzhong/tunnel/api"
	"gitlab.weinvent.org/yangchenzhong/tunnel/utils/config"
)

func (cli *CLI) buildServerCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:                   "api [--http]",
		Short:                 "Run as NewBridge API server",
		DisableFlagsInUseLine: true,
		Run: func(cmd *cobra.Command, args []string) {

			all := viper.AllSettings()
			allJson, err := json.Marshal(&all)
			if err != nil {
				fmt.Println(err)
				return
			}

			var cfg *config.Bridge
			err = json.Unmarshal(allJson, &cfg)
			if err != nil {
				fmt.Println(err)
				return
			}

			if cfg.Router.HostNetwork == "" {
				cfg.Router.HostNetwork = "tcp"
			}

			configB, err := json.MarshalIndent(cfg, " ", " ")
			if err != nil {
				fmt.Println("MarshalIndent: ", err)
				return
			}
			fmt.Println(string(configB))

			isHttp, _ := cmd.Flags().GetBool("http")
			isManager, _ := cmd.Flags().GetBool("manager")
			if isManager {
				am := api.NewManager(cfg, cfg.DB)
				if am == nil {
					fmt.Println("Create router error")
					return
				}

				if isHttp {
					if err := am.RunHttpAPIServer(); err != nil {
						fmt.Println(err)
						return
					}
				} else {

					if err := am.Init(); err != nil {
						fmt.Println(err)
						return
					}

					// configB, err := json.MarshalIndent(am, " ", " ")
					// if err != nil {
					// 	fmt.Println(err)
					// 	return
					// }
					// fmt.Println(string(configB))

					if err := am.RunAPIServer(); err != nil {
						fmt.Println(err)
						return
					}
				}
				return
			}

			r := api.New(cfg, cfg.DB)
			if r == nil {
				fmt.Println("Create router error")
				return
			}

			if isHttp {
				if err := r.RunHttpAPIServer(); err != nil {
					fmt.Println(err)
					return
				}
			} else {

				if err := r.Init(); err != nil {
					fmt.Println(err)
					return
				}

				// configB, err := json.MarshalIndent(r, " ", " ")
				// if err != nil {
				// 	fmt.Println(err)
				// 	return
				// }
				// fmt.Println(string(configB))

				if err := r.RunAPIServer(); err != nil {
					fmt.Println(err)
					return
				}
			}

			return
		},
	}

	cmd.Flags().Bool("http", false, "enable with http support")
	cmd.Flags().Bool("manager", false, "enable manager api")

	return cmd
}
