package cli

import (
	"fmt"

	"github.com/spf13/cobra"
)

func (cli *CLI) buildVersionCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "version",
		Short: "Get version of " + cli.Name + " CLI",
		Run: func(cmd *cobra.Command, args []string) {
			fmt.Println(fmt.Sprintf("%v", ChainVersion()))
		},
	}

	return cmd
}
