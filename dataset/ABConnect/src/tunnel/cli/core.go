package cli

import (
	"encoding/json"
	"fmt"

	"github.com/spf13/cobra"
	"gitlab.weinvent.org/yangchenzhong/tunnel/core"
)

func (cli *CLI) buildCoreCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "core",
		Short: "Manager deposit and withdraw",
		// Args:  cobra.MinimumNArgs(1),
		Run: func(cmd *cobra.Command, args []string) {

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

			m, err := core.New(cb)
			if err != nil {
				fmt.Println(err)
				return
			}
			if err := m.Init(); err != nil {
				fmt.Println(err)
				return
			}

			if err := m.RunExchangeTasks(); err != nil {
				fmt.Println(err)
				return
			}

			return
		},
	}

	return cmd
}
