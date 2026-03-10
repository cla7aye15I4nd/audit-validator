package chain

import (
	"bytes"
	"cmp"
	"context"
	"encoding/hex"
	"errors"
	"fmt"
	"math/big"
	"slices"

	"gitlab.weinvent.org/yangchenzhong/tunnel/database"

	"github.com/btcsuite/btcd/btcec/v2"
	"github.com/upper/db/v4"

	dbtcec "github.com/dogecoinw/doged/btcec"
	dbtcutil "github.com/dogecoinw/doged/btcutil"
	dchaincfg "github.com/dogecoinw/doged/chaincfg"
	dtxscript "github.com/dogecoinw/doged/txscript"
	dwire "github.com/dogecoinw/doged/wire"

	"github.com/btcsuite/btcd/btcutil"
	"github.com/btcsuite/btcd/txscript"
	"github.com/btcsuite/btcd/wire"
)

const ContentType = "text/plain;charset=utf-8"

type DRC20Tx struct {
	P    string `json:"p"`
	Op   string `json:"op"`
	Tick string `json:"tick"`
	Amt  string `json:"amt"`
}

type DRX20Txs []DRC20Tx

type dogecoinWallet struct {
	// key        *ecdsa.PrivateKey
	utxos      UTXOs
	privateKey *dbtcec.PrivateKey
	publicKey  *dbtcec.PublicKey
}

func (w *dogecoinWallet) popUtxo(amount *big.Int) *UTXO {
	// TODO: base amount
	for i, utxo := range w.utxos {
		if utxo.Value != nil && utxo.Value.Cmp(amount) >= 0 {
			w.utxos = append(w.utxos[:i], w.utxos[i+1:]...)
			return utxo
		}
	}

	return nil
}

func (w *dogecoinWallet) pop() *UTXO {
	if w.utxos == nil {
		return nil
	}
	if len(w.utxos) == 0 {
		return nil
	}
	slices.SortFunc(w.utxos, func(a, b *UTXO) int {
		return cmp.Compare(a.Height, b.Height)
	})

	u := w.utxos[0]

	w.utxos = w.utxos[1:]

	return u
}

// inscribe
func inscribe(from, to dbtcutil.Address, data []byte, w, feeWallet *dogecoinWallet) ([]*dwire.MsgTx, UTXOs, error) {

	address, err := dbtcutil.NewAddressPubKeyHash(btcutil.Hash160(w.publicKey.SerializeCompressed()), &dchaincfg.MainNetParams)
	if err != nil {
		fmt.Println(err)
		return nil, nil, err
	}
	fmt.Println(address.EncodeAddress())
	if address.String() != from.String() {
		return nil, nil, fmt.Errorf("address error")
	}

	var txs []*dwire.MsgTx
	tx1 := dwire.NewMsgTx(wire.TxVersion)

	//  lock
	lockScriptBuilder := txscript.NewScriptBuilder()
	lockScriptBuilder.AddOp(txscript.OP_1).
		AddData(w.publicKey.SerializeCompressed()).
		AddOp(txscript.OP_1).
		AddOp(txscript.OP_CHECKMULTISIGVERIFY).
		AddData([]byte("ord")).
		AddData([]byte(ContentType)).
		AddData(data).
		AddOp(txscript.OP_DROP).
		AddOp(txscript.OP_DROP).
		AddOp(txscript.OP_DROP)
	lockScript, err := lockScriptBuilder.Script()
	if err != nil {
		return nil, nil, err
	}
	lockhash := btcutil.Hash160(lockScript)

	fmt.Println("lockScript: ", hex.EncodeToString(lockScript))

	p2shScriptBuilder := txscript.NewScriptBuilder()
	p2shScriptBuilder.AddOp(txscript.OP_HASH160).
		AddData(lockhash).
		AddOp(txscript.OP_EQUAL)
	p2shScript, err := p2shScriptBuilder.Script()
	if err != nil {
		return nil, nil, err
	}

	// TODO: update fee
	// fee: 100000 * MINT_REPEAT_TIMES + TX2_FEE(0.1DOGE)
	p2shOutput := dwire.NewTxOut(10100000, p2shScript) // 0.101 DOGE
	tx1.AddTxOut(p2shOutput)

	// in
	fee := big.NewInt(10000000) // 0.1 for current
	totalAmount := big.NewInt(0).Add(fee, big.NewInt(p2shOutput.Value))
	var (
		utxo    *UTXO
		feeUtxo *UTXO
	)
	if feeWallet == nil {
		utxo = w.popUtxo(totalAmount)
	} else if bytes.Compare(w.publicKey.SerializeCompressed(), feeWallet.publicKey.SerializeCompressed()) == 0 {
		utxo = w.popUtxo(totalAmount)
	} else {
		utxo = w.pop()
		if utxo == nil {
			return nil, nil, fmt.Errorf("no utxo for drc20")
		}
		if utxo.Value.Cmp(totalAmount) < 0 {
			// fee.And(fee, inputFee)
			feeUtxo = feeWallet.popUtxo(big.NewInt(0).Sub(totalAmount, utxo.Value))
			if utxo == nil {
				return nil, nil, fmt.Errorf("no fee utxo")
			}
		}
	}
	if utxo == nil {
		return nil, nil, fmt.Errorf("no utxo")
	}
	fmt.Println("PreHash: ", utxo.Txid.String())
	outPoint := dwire.NewOutPoint(&utxo.Txid, utxo.Vout)
	p2shIn := dwire.NewTxIn(outPoint, nil, nil)
	tx1.AddTxIn(p2shIn)

	if feeUtxo != nil {
		feeOutPoint := dwire.NewOutPoint(&feeUtxo.Txid, feeUtxo.Vout)
		feeP2shIn := dwire.NewTxIn(feeOutPoint, nil, nil)
		tx1.AddTxIn(feeP2shIn)
	}

	// change, from
	changeValue := big.NewInt(0)
	changeAddress := address
	if feeUtxo != nil {
		changeValue.Add(feeUtxo.Value, utxo.Value)
		changeValue.Sub(changeValue, totalAmount)

		feeAddress, err := dbtcutil.NewAddressPubKeyHash(btcutil.Hash160(feeWallet.publicKey.SerializeCompressed()), &dchaincfg.MainNetParams)
		if err != nil {
			fmt.Println(err)
			return nil, nil, err
		}
		changeAddress = feeAddress
	} else {
		changeValue.Sub(utxo.Value, totalAmount)
	}
	if !changeValue.IsInt64() {
		return nil, nil, fmt.Errorf("change value error")
	}
	changeScript, err := dtxscript.PayToAddrScript(changeAddress)
	if err != nil {
		log.Errorf("error creating pay-to-address script: %v", err)
		return nil, nil, err
	}
	change1 := dwire.NewTxOut(changeValue.Int64(), changeScript)
	tx1.AddTxOut(change1)

	// sign input
	tx1SubScript, err := hex.DecodeString(utxo.ScriptPubKey)
	if err != nil {
		return nil, nil, fmt.Errorf("decoe erro: %s", err)
	}
	fmt.Println("PreSubScript: ", hex.EncodeToString(tx1SubScript))
	sigScript, err := dtxscript.SignatureScript(tx1, 0, tx1SubScript, dtxscript.SigHashAll, w.privateKey, true)
	if err != nil {
		return nil, nil, fmt.Errorf("error creating signature script: %v", err)
	}
	tx1.TxIn[0].SignatureScript = sigScript

	if feeUtxo != nil {
		feeSubScript, err := hex.DecodeString(feeUtxo.ScriptPubKey)
		if err != nil {
			return nil, nil, fmt.Errorf("decoe erro: %s", err)
		}
		feeSigScript, err := dtxscript.SignatureScript(tx1, 1, feeSubScript, dtxscript.SigHashAll, feeWallet.privateKey, true)
		if err != nil {
			return nil, nil, fmt.Errorf("error creating signature script: %v", err)
		}
		tx1.TxIn[1].SignatureScript = feeSigScript
	}

	txs = append(txs, tx1) // txs.push(tx1)

	// ////////////////////////////////////////////
	// tx2
	tx2 := dwire.NewMsgTx(wire.TxVersion)

	// tx2 out
	pkScript2, err := dtxscript.PayToAddrScript(to)
	if err != nil {
		return nil, nil, fmt.Errorf("error creating pay-to-address script: %v", err)
	}
	recvOutput2 := dwire.NewTxOut(100000, pkScript2) // force 0.001
	tx2.AddTxOut(recvOutput2)

	// tx2 in
	tx1Hash := tx1.TxHash()
	outPoint2 := dwire.NewOutPoint(&tx1Hash, 0)
	txIn2 := dwire.NewTxIn(outPoint2, nil, nil)
	tx2.AddTxIn(txIn2)

	// tx2 in 0 sign
	sigScript2, err := dtxscript.RawTxInSignature(tx2, 0, lockScript, dtxscript.SigHashAll, w.privateKey)
	if err != nil {
		return nil, nil, fmt.Errorf("error creating RawTxInSignature signature script: %v", err)
	}

	unlockScriptBuilder := txscript.NewScriptBuilder()
	unlockScriptBuilder.AddOp(txscript.OP_10).
		AddOp(txscript.OP_0).
		AddData(sigScript2).
		AddData(lockScript)

	unlockScript, err := unlockScriptBuilder.Script()
	if err != nil {
		return nil, nil, err
	}
	tx2.TxIn[0].SignatureScript = unlockScript

	txs = append(txs, tx2)

	var stxo UTXOs
	stxo = append(stxo, utxo)
	if feeUtxo != nil {
		stxo = append(stxo, feeUtxo)
	}

	return txs, stxo, nil
}

func (x *Chain) getWallet(address dbtcutil.Address) (*dogecoinWallet, error) {
	sdbTasks, err := database.OpenDatabase(x.DB.Adapter, x.DB.ConnectionURL)
	if err != nil {
		log.Errorln(err)
		return nil, err
	}
	defer sdbTasks.Close()

	blockbookClient := NewBlockBookClient(x.DogecoinConfig.BlockbookURL)

	pkey, err := x.getKey(context.Background(), address)
	if err != nil {
		return nil, err
	}
	defer zeroKey(pkey)

	utxos, err := blockbookClient.GetAllUTXOs(address)
	if err != nil {
		return nil, err
	}
	utxos = slices.DeleteFunc(utxos, func(utxo *UTXO) bool {
		var u UTXO
		err = sdbTasks.SQL().Select("id").From("doge_stxo").Where(
			"hash", utxo.Txid.String()).And("pos", utxo.Vout).One(&u)
		return !errors.Is(err, db.ErrNoMoreRows)
	})

	privateKey, publicKey := btcec.PrivKeyFromBytes(pkey.D.Bytes())
	w := dogecoinWallet{
		utxos:      utxos,
		privateKey: privateKey,
		publicKey:  publicKey,
	}

	return &w, nil
}
