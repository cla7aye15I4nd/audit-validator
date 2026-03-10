package cli

import (
	"fmt"
	"time"

	"github.com/spf13/cobra"
	"gitlab.weinvent.org/yangchenzhong/tunnel/check"
)

func (cli *CLI) buildCheckCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "check",
		Short: "Security Check",
		Run: func(cmd *cobra.Command, args []string) {

			cb, err := loadBridge()
			if err != nil {
				fmt.Println(err)
				return
			}

			c, err := check.New(cb)
			if err != nil {
				fmt.Println(err)
				return
			}

			daily, _ := cmd.Flags().GetBool("daily")
			if daily {
				c.Daily()
				return
			}

			timed, _ := cmd.Flags().GetBool("timed")
			if timed {
				duration, _ := cmd.Flags().GetDuration("duration")
				c.RunTimed(duration)
			} else {
				if err := c.RunInstant(); err != nil {
					log.Error(err)
					return
				}
			}

			return
		},
	}

	cmd.Flags().BoolP("timed", "t", false, "run as timed, default is instant")
	cmd.Flags().Duration("duration", time.Minute*5, "duration to run as timed")

	cmd.Flags().Bool("daily", false, "only run daily task")

	return cmd
}
