package cli

import (
	"fmt"
	"os"
	"time"

	"github.com/spf13/cobra"
	"gitlab.weinvent.org/yangchenzhong/tunnel/blockchain"
	"gitlab.weinvent.org/yangchenzhong/tunnel/manager"
)

const (
	ManagerDefault = iota
	ManagerList
	ManagerCold
)

func (cli *CLI) buildManagerCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:                   "manager <run|list|cold>",
		Short:                 "Manager accounts",
		DisableFlagsInUseLine: true,
		Args:                  cobra.MinimumNArgs(1),
		Run: func(cmd *cobra.Command, args []string) {
			fmt.Fprint(os.Stderr, cmd.UsageString())

			os.Exit(-1)
		},
	}

	cmd.AddCommand(cli.buildManagerRunCmd())
	cmd.AddCommand(cli.buildManagerListCmd())
	cmd.AddCommand(cli.buildManagerColdCmd())

	return cmd
}

func (cli *CLI) buildManagerRunCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "run",
		Short: "Manager tokens, transfer or burn",
		Run: func(cmd *cobra.Command, args []string) {

			cli.runManager(cmd, args, ManagerDefault)

		},
	}

	cmd.Flags().String("duration", "300s", "duration of exec manager check")

	return cmd
}

func (cli *CLI) buildManagerListCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "list",
		Short: "List accounts balance",
		Run: func(cmd *cobra.Command, args []string) {

			cli.runManager(cmd, args, ManagerList)

		},
	}

	return cmd
}

func (cli *CLI) buildManagerColdCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "cold <amount>",
		Short: "Transfer asset to cold account",
		Args:  cobra.ExactArgs(1),
		Run: func(cmd *cobra.Command, args []string) {

			cli.runManager(cmd, args, ManagerCold)

		},
	}

	return cmd
}

func (cli *CLI) runManager(cmd *cobra.Command, args []string, action int) {
	var err error
	cb, err := loadBridge()
	if err != nil {
		fmt.Println(err)
		return
	}

	err = handleBlockchain(cb)
	if err != nil {
		fmt.Println(err)
		return
	}
	baseChain := cb.Blockchain.BaseChain
	if baseChain == blockchain.UnknownChain {
		fmt.Println("base chain unknown")
		return
	}
	if err := applyDB(cb); err != nil {
		fmt.Println(err)
		return
	}

	m, err := manager.New(cb)
	if err != nil {
		fmt.Println(err)
		return
	}

	if action == ManagerList {
		err = m.ListAll()
		if err != nil {
			fmt.Println(err)
			return
		}
	} else if action == ManagerCold {
		err = m.RunCold(args)
		if err != nil {
			fmt.Println(err)
			return
		}
	} else {
		duration := time.Second * 300
		if cmd.Flags().Changed("duration") {
			durationStr, err := cmd.Flags().GetString("duration")
			if err != nil {
				fmt.Println(err)
				return
			}
			duration, err = time.ParseDuration(durationStr)
			if err != nil {
				fmt.Println(err)
				return
			}
		}

		err = m.Run(duration, m.RunEthTransfer)
		if err != nil {
			fmt.Println(err)
			return
		}
	}

	return
}
