
/*
 * TODO: Replace this with cmd
 */

-- blockchains
INSERT INTO blockchains(network, chain_id, base_chain)
VALUES
    ("Newton", "1012", "NewChain"),
    ("Ethereum", "1", "Ethereum"), /* rpc.eth_chainId */
    ("Bitcoin", "main", "Bitcoin"), /* rpc.getblockchaininfo */
    ("Dogecoin", "main", "Dogecoin");

INSERT INTO blockchains(network, chain_id, base_chain)
VALUES
    ("Newton", "1007", "NewChain"),
    ("Ethereum", "11155111", "Ethereum"), /* Sepolia */
    ("Bitcoin", "test", "Bitcoin"),
    ("Dogecoin", "test", "Dogecoin");

INSERT INTO blockchains(network, chain_id, base_chain)
VALUES
    ("Dogelayer", "9888", "Ethereum"),
    ("Dogelayer", "16888", "Ethereum");


-- assets
INSERT INTO assets(blockchain_id, asset, name, symbol, decimals, attribute, asset_type)
VALUES
    (1, "", "Newton", "NEW", "18", 0, "Coin"),
    (2, "", "Ethereum", "ETH", "18", 0, "Coin"), /* Ether? */
    (3, "", "Bitcoin", "BTC", "8", 0, "Coin"),
    (4, "", "Dogecoin", "DOGE", "8", 0, "Coin");

INSERT INTO assets(blockchain_id, asset, name, symbol, decimals, attribute, asset_type)
VALUES
    (5, "", "Newton", "NEW", "18", 0, "Coin"),
    (6, "", "Ethereum", "ETH", "18", 0, "Coin"), /* Ether? */
    (7, "", "Bitcoin", "BTC", "8", 0, "Coin"),
    (8, "", "Dogecoin", "DOGE", "8", 0, "Coin");

INSERT INTO assets(blockchain_id, asset, name, symbol, decimals, attribute, asset_type)
VALUES
    (9, "", "Dogecoin", "DOGE", "18", 0, "Coin"),
    (10, "", "Dogecoin", "DOGE", "18", 0, "Coin");

/* Dogecoin main WDOGE(WRAPPED-DOGE) && DOGEL */
INSERT INTO assets(blockchain_id, asset, name, symbol, decimals, attribute, asset_type)
VALUES
    (4, "WDOGE(WRAPPED-DOGE)", "WDOGE(WRAPPED-DOGE)", "WDOGE(WRAPPED-DOGE)", "8", 0, "DRC-20"),
    (4, "DOGEL", "DOGEL", "DOGEL", "8", 0, "DRC-20");

/* ethereum Sepolia Testnet USDT <==> dogelayer testnet USDT */
INSERT INTO assets(blockchain_id, asset, name, symbol, decimals, attribute, asset_type)
VALUES
    (6, "0x9Fc54AAAd8ED0085CAE87e1c94F2b19eE10a1653", "Tether USD", "USDT", "6", 0, "ERC20"),
    (10, "0x95bD0804D9ddFe616316f6769E282510E1b8644f", "Tether USD", "USDT", "6", 3, "ERC20");

-- pairs_list
INSERT INTO pairs(asset_a_id, asset_b_id,
                       asset_a_min_deposit_amount, asset_b_min_deposit_amount,
                       asset_a_withdraw_fee_pct, asset_b_withdraw_fee_pct,
                       asset_a_withdraw_fee_min, asset_b_withdraw_fee_min,
                       asset_a_auto_confirm_deposit_amount, asset_b_auto_confirm_deposit_amount)
VALUES
      (13, 14, "0", "0", 0, 0, "0", "0", "0", "0");

INSERT INTO pairs(asset_a_id, asset_b_id,
                       asset_a_min_deposit_amount, asset_b_min_deposit_amount,
                       asset_a_withdraw_fee_pct, asset_b_withdraw_fee_pct,
                       asset_a_withdraw_fee_min, asset_b_withdraw_fee_min,
                       asset_a_auto_confirm_deposit_amount, asset_b_auto_confirm_deposit_amount)
VALUES
    (12, 14, "0", "0", 0, 0, "0", "0", "0", "0");


-- get pairs_list
SELECT
    p.*,
    a1.asset AS asset_a_asset,
    a1.name AS asset_a_name,
    a1.symbol AS asset_a_symbol,
    b1.network AS asset_a_network,
    b1.chain_id AS asset_a_chain_id,
    b1.base_chain AS asset_a_base_chain,
    a2.asset AS asset_b_asset,
    a2.name AS asset_b_name,
    a2.symbol AS asset_b_symbol,
    b2.network AS asset_b_network,
    b2.chain_id AS asset_b_chain_id,
    b2.base_chain AS asset_b_base_chain
FROM
    pairs p
        LEFT JOIN assets a1 ON p.asset_a_id = a1.id
        LEFT JOIN blockchains b1 ON a1.blockchain_id = b1.id
        LEFT JOIN assets a2 ON p.asset_b_id = a2.id
        LEFT JOIN blockchains b2 ON a2.blockchain_id = b2.id;


-- history details with asset and blockchain
select h.*,
    a1.id AS asset_id,
    a1.name AS asset_name,
    a1.symbol AS asset_symbol,
    a1.decimals AS asset_decimals,
    a1.asset_type AS asset_type,
    b1.network AS network,
    b1.chain_id AS chain_id,
    b1.base_chain AS base_chain,
    a2.id AS target_asset_id,
    a2.name AS target_asset_name,
    a2.symbol AS target_asset_symbol,
    a2.decimals AS target_asset_decimals,
    a2.asset_type AS target_asset_type,
    b2.network AS target_network,
    b2.chain_id AS target_chain_id,
    b2.base_chain AS target_base_chain
    from history h
    left join assets a1 on h.blockchain_id = a1.blockchain_id and h.asset = a1.asset
    left join blockchains b1 on h.blockchain_id = b1.id
    left join assets a2 on h.target_blockchain_id = a2.blockchain_id and h.target_asset = a2.asset
    left join blockchains b2 on h.blockchain_id = b2.id;
