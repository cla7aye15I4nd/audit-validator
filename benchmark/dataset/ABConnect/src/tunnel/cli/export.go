package cli

import (
	"encoding/json"
	"fmt"
	"os"
	"time"

	"github.com/gocarina/gocsv"
	"github.com/spf13/cobra"
	"gitlab.weinvent.org/yangchenzhong/tunnel/database"
)

func (cli *CLI) buildExportCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:                   "export",
		Short:                 "Export all history",
		DisableFlagsInUseLine: true,
		Run: func(cmd *cobra.Command, args []string) {

			cli.exportCmd(cmd, args, 0)
		},
	}

	return cmd
}

func (cli *CLI) exportCmd(cmd *cobra.Command, args []string, action int) {

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

	// open db
	sess, err := database.OpenDatabase(cb.DB.Adapter, cb.DB.ConnectionURL)
	if err != nil {
		fmt.Println("Open db err: ", err)
		return
	}
	defer sess.Close()

	var historyList []database.HistoryDetail
	s := sess.SQL().Select(
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
		LeftJoin("blockchains b2").On("a2.blockchain_id = b2.id")
	err = s.All(&historyList)
	if err != nil {
		fmt.Println(err)
		return
	}

	nameHistory := fmt.Sprintf("history.%s.csv", time.Now().Format("20060102150405"))
	fileHistory, err := os.OpenFile(nameHistory, os.O_RDWR|os.O_CREATE|os.O_EXCL, 0666)
	if err != nil {
		fmt.Println(err)
		return
	}
	defer fileHistory.Close()

	err = gocsv.MarshalFile(&historyList, fileHistory)
	if err != nil {
		panic(err)
	}

	return
}
