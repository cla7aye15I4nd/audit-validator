package cli

import (
	"github.com/spf13/cobra"
)

func (cli *CLI) buildRootCmd() {

	if cli.rootCmd != nil {
		cli.rootCmd.ResetFlags()
		cli.rootCmd.ResetCommands()
	}

	rootCmd := &cobra.Command{
		Use:              cli.Name,
		Short:            cli.Name + " is commandline client for extract Dogecoin blocks and transactions.",
		Run:              cli.help,
		PersistentPreRun: cli.setup,
	}
	rootCmd.CompletionOptions.DisableDefaultCmd = true
	cli.rootCmd = rootCmd

	// Global flags
	rootCmd.PersistentFlags().StringVarP(&cli.config, "config", "c", defaultConfigFile, "The `path` to config file")
	// rootCmd.PersistentFlags().StringP("rpcURL", "i", defaultRPCURL, "Geth json rpc or ipc `url`")

	rootCmd.PersistentFlags().StringP("log", "l", defaultLogFile, "The path of log file")

	// Basic commands
	rootCmd.AddCommand(cli.buildVersionCmd()) // version

	rootCmd.AddCommand(cli.buildMonitorCmd()) // monitor deposit

	rootCmd.AddCommand(cli.buildChainCmd()) // ChainId API and tasks

	rootCmd.AddCommand(cli.buildBlockchainCmd()) // blockchain
	rootCmd.AddCommand(cli.buildAssetCmd())      // asset
	rootCmd.AddCommand(cli.buildPairCmd())       // pair

	// system config
	rootCmd.AddCommand(cli.buildConfigCmd())  // config
	rootCmd.AddCommand(cli.buildConfirmCmd()) // confirm
	rootCmd.AddCommand(cli.buildExportCmd())  // export
	rootCmd.AddCommand(cli.buildCheckCmd())   // check

	// core
	rootCmd.AddCommand(cli.buildCoreCmd())   // core
	rootCmd.AddCommand(cli.buildServerCmd()) // API
}
