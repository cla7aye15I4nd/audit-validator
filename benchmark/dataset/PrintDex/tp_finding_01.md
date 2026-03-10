# Attacker Can Drain Any Pool


| Field | Value |
| --- | --- |
| Type | True Positive |
| Severity | 🔴 Critical |
| Triage Verdict | ✅ Valid |
| Project ID | `57a71af0-0f0f-11ef-b522-65e6a878d0aa` |
| Commit | `e443f0c8af8adcfa60953cefcaab96decc306558` |

## Location

- **Local path:** `./src/programs/print-dex/src/lib.rs`
- **ACC link:** https://acc.audit.certikpowered.info/project/57a71af0-0f0f-11ef-b522-65e6a878d0aa/source?file=$/github/GageBachik/printDex/e443f0c8af8adcfa60953cefcaab96decc306558/programs/print-dex/src/lib.rs
- **Lines:** 210–210

## Description

It is possible for an attacker to steal all vault reserves for any pool. The main reason is due to the fact that the `create_pool` instruction can be used with an existing, already initialized, pool.

The `create_pool` instruction initializes pool parameters. The most important parameter initialized is the `token_supply` value, which is meant to denote the number of LP tokens.

```rust=195
        let liquidity_token_to_mint = (((amount_a as f64) * (amount_b as f64)).sqrt() -
            1000.0) as u64;
```
```rust=210
        pool.token_supply = liquidity_token_to_mint;
```

By using `create_pool` on an already operational pool, an attacker can decide the value of `token_supply`, greatly changing the worth of an LP token. For example, changing the `token_supply` value to 1 would mean that burning 1 LP token would allow a user to acquire all reserve tokens.

Two additional issues make this vulnerability more severe:
1. The lack of access control on `create_pool` means any user, not just the `pool.authority`, be allowed to change the token supply
2. The value set to `pool.token_supply` is incorrect. The value should be `liquidity_token_to_mint + 1000` in order to combat inflation attacks

## Recommendation

It is recommended to not allow pools to be initialized twice. One possible way to do this is to add a boolean `initialized` field in the `Pool` account and check this field for all pool operations.

## Vulnerable Code

```
} else {
            transfer_checked(
                CpiContext::new(token_program_b.to_account_info(), TransferChecked {
                    from: authority_token_account_b.to_account_info(),
                    mint: mint_b.to_account_info(),
                    to: vault_token_account_b.to_account_info(),
                    authority: authority.to_account_info(),
                }),
                amount_b,
                mint_b.decimals
            )?;
        }

        // Mint LP Tokens - min amount to avoid inflation attack
        let liquidity_token_to_mint = (((amount_a as f64) * (amount_b as f64)).sqrt() -
            1000.0) as u64;
        mint_to(
            CpiContext::new(token_program.to_account_info(), MintTo {
                mint: liquidity_token.to_account_info(),
                to: authority_liquidity_token_account.to_account_info(),
                authority: vault.to_account_info(),
            }).with_signer(&[&[pool.key().as_ref(), &[vault_bump]]]),
            liquidity_token_to_mint
        )?;

        // Initialize the pool
        pool.authority = authority.key();
        pool.vault = vault.key();
        pool.liquidity_token = liquidity_token.key();
        pool.token_supply = liquidity_token_to_mint;
        pool.pool_fee = 25;

        Ok(())
    }

    #[inline(never)]
    pub fn add_liquidity<'info>(
        ctx: Context<'_, '_, '_, 'info, AddLiquidity<'info>>,
        amount_a: u64,
        amount_b: u64,
        slippage: u64
    ) -> Result<()> {
        let config = &ctx.accounts.config;
        let authority = &ctx.accounts.authority;
        let pool = &mut ctx.accounts.pool;
        let vault = &ctx.accounts.vault;
        let vault_bump = ctx.bumps.vault;
        let mint_a = &ctx.accounts.mint_a;
        let mint_b = &ctx.accounts.mint_b;
        let authority_token_account_a = &ctx.accounts.authority_token_account_a;
        let authority_token_account_b = &ctx.accounts.authority_token_account_b;
        let vault_token_account_a = &ctx.accounts.vault_token_account_a;
        let vault_token_account_b = &ctx.accounts.vault_token_account_b;
        let liquidity_token = &ctx.accounts.liquidity_token;
        let authority_liquidity_token_account = &ctx.accounts.authority_liquidity_token_account;
        let token_program = &ctx.accounts.token_program;
        let token_program_a = &ctx.accounts.token_program_a;
        let token_program_b = &ctx.accounts.token_program_b;
        let pool_amount_a = vault_token_account_a.amount;
        let pool_amount_b = vault_token_account_b.amount;
```
