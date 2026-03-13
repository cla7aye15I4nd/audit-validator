package monitor

import (
	"context"
	"errors"
	"fmt"
	"math/big"
	"time"

	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/ethclient"
	db "github.com/upper/db/v4"
	"gitlab.weinvent.org/yangchenzhong/tunnel/database"
	"gitlab.weinvent.org/yangchenzhong/tunnel/utils"
)

var (
	// k256('transfer(address,uint256)') = "0xa9059cbb2ab09eb219583f4a59a5d0623ade346d962bcd4e46b11da047c9049b"
	TransferSigData = common.Hex2Bytes("a9059cbb")

	// k256('transferFrom(address,address,uint256)') = "0x23b872dd7302113369cda2901243429419bec145408fa8b352b3dd92b66c680b"
	TransferFromSigData = common.Hex2Bytes("23b872dd")

	// k256('Transfer(address,address,uint256)') = "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"
	TopicOfTransfer = common.HexToHash("ddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef")
)

func (m *Monitor) openDatabase() (db.Session, error) {
	return database.OpenDatabase(m.adapterName, m.settings)
}

func (m *Monitor) saveBlockHeight(number *big.Int) error {
	if number == nil {
		return nil
	}

	if m.cc == nil || m.cc.Network == "" || m.cc.ChainId == "" {
		return fmt.Errorf("LatestBlockHeight format error")
	}
	variable := fmt.Sprintf("%s-%s-%s", m.Blockchain.Network, m.Blockchain.ChainId, utils.LatestBlockHeight)

	sess, err := m.openDatabase()
	if err != nil {
		return Error(err)
	}
	defer sess.Close()

	sql := fmt.Sprintf(`INSERT INTO %s (variable, value) VALUES("%s", %s) 
				ON DUPLICATE KEY UPDATE value = %s`,
		database.TableOfConfig, variable, number.String(), number.String())
	_, err = sess.SQL().Exec(sql)
	if err != nil {
		return err
	}

	return nil
}

func (m *Monitor) loadBlockHeight() (*big.Int, error) {
	if m.cc == nil || m.cc.Network == "" || m.cc.ChainId == "" {
		return nil, fmt.Errorf("LatestBlockHeight format error")
	}
	variable := fmt.Sprintf("%s-%s-%s", m.Blockchain.Network, m.Blockchain.ChainId, utils.LatestBlockHeight)

	sess, err := m.openDatabase()
	if err != nil {
		return nil, Error(err)
	}
	defer sess.Close()

	var v database.Config
	err = sess.SQL().SelectFrom(
		database.TableOfConfig).Where(
		"variable", variable).One(&v)
	if errors.Is(err, db.ErrNoMoreRows) {
		return nil, nil
	} else if err != nil {
		return nil, err
	}

	if v.Value == "" {
		return nil, err
	}
	n, ok := big.NewInt(0).SetString(v.Value, 10)
	if !ok {
		return nil, ErrorCode(errStringToBigInt)
	}

	return n, nil
}

func getBlockInterval(client *ethclient.Client) (time.Duration, error) {
	ctx := context.Background()
	latest, err := client.HeaderByNumber(ctx, nil)
	if err != nil {
		return time.Duration(0), err
	}

	// ignore latest is before block 100
	header10, err := client.HeaderByNumber(ctx, big.NewInt(latest.Number.Int64()-100))
	if err != nil {
		return time.Duration(0), err
	}

	return time.Duration(latest.Time-header10.Time) * time.Second / 100, nil
}
