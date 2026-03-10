use anchor_lang::prelude::*;
use anchor_lang::solana_program::program::{ invoke, invoke_signed };
use anchor_lang::solana_program::system_instruction::transfer;
use anchor_spl::{
    token::Token,
    associated_token::AssociatedToken,
    token_interface::{
        Mint,
        TokenAccount,
        TokenInterface,
        MintTo,
        mint_to,
        transfer_checked,
        TransferChecked,
        burn,
        Burn,
    },
};
use spl_token_2022::instruction::transfer_checked as hook_transfer_checked;
use solana_program::{ clock::Clock, sysvar::Sysvar };
use spl_token_2022::extension::{
    StateWithExtensions,
    transfer_fee::TransferFeeConfig,
    BaseStateWithExtensions,
};
use spl_token_2022::state::Mint as MintState;
use spl_transfer_hook_interface::onchain::add_extra_accounts_for_execute_cpi;
use std::cmp;
use sha2::{ Digest, Sha256 };
use std::collections::HashSet;

declare_id!("pDEX9VxuEnKR9LS3w7QFTrX9L8EpQfftw3y3a8rp59h");

// Data Logics
#[program]
pub mod print_dex {
    use super::*;

    #[inline(never)]
    pub fn init_platform<'info>(
        ctx: Context<'_, '_, '_, 'info, InitPlatform<'info>>
    ) -> Result<()> {
        let config = &mut ctx.accounts.config;
        let authority = &mut ctx.accounts.authority;
        config.authority = authority.key();
        config.fee_wallet = authority.key();
        config.platform_fee = 500000;
        config.pools_enabled = true;
        Ok(())
    }

    #[inline(never)]
    pub fn update_platform_config<'info>(
        ctx: Context<'_, '_, '_, 'info, UpdatePlatformConfig<'info>>,
        platform_fee: u64,
        pools_enabled: bool
    ) -> Result<()> {
        let config = &mut ctx.accounts.config;
        let authority = &mut ctx.accounts.authority;
        let fee_wallet = &mut ctx.accounts.fee_wallet;
        config.authority = authority.key();
        config.fee_wallet = fee_wallet.key();
        config.platform_fee = platform_fee;
        config.pools_enabled = pools_enabled;
        Ok(())
    }

    #[inline(never)]
    pub fn create_pool_accounts<'info>(
        ctx: Context<'_, '_, '_, 'info, CreatePoolAccounts<'info>>
    ) -> Result<()> {
        let authority = &mut ctx.accounts.authority;
        let vault = &mut ctx.accounts.vault;
        // Init the vault
        invoke(
            &transfer(authority.key, &vault.key, 10000000),
            &[authority.to_account_info(), vault.to_account_info()]
        )?;
        Ok(())
    }

    #[inline(never)]
    pub fn create_pool<'info>(
        ctx: Context<'_, '_, '_, 'info, CreatePool<'info>>,
        amount_a: u64,
        amount_b: u64
    ) -> Result<()> {
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
        let hook_program_a = &ctx.accounts.hook_program_a;
        let hook_program_b = &ctx.accounts.hook_program_b;
        let remaining_accounts = &ctx.remaining_accounts;

        // Transfer tokens to the vault
        if hook_program_a.is_some() {
            let hook_program = hook_program_a.as_ref().unwrap();
            let mut cpi_instruction = hook_transfer_checked(
                token_program_a.key,
                &authority_token_account_a.key(),
                &mint_a.key(),
                &vault_token_account_a.key(),
                &authority.key(),
                &[],
                amount_a,
                mint_a.decimals
            )?;
            let mut cpi_account_infos = vec![
                authority_token_account_a.to_account_info(),
                mint_a.to_account_info(),
                vault_token_account_a.to_account_info(),
                authority.to_account_info()
            ];
            add_extra_accounts_for_execute_cpi(
                &mut cpi_instruction,
                &mut cpi_account_infos,
                hook_program.key,
                authority_token_account_a.to_account_info(),
                mint_a.to_account_info(),
                vault_token_account_a.to_account_info(),
                authority.to_account_info(),
                amount_a,
                remaining_accounts
            )?;
            invoke(&cpi_instruction, &cpi_account_infos)?;
        } else {
            transfer_checked(
                CpiContext::new(token_program_a.to_account_info(), TransferChecked {
                    from: authority_token_account_a.to_account_info(),
                    mint: mint_a.to_account_info(),
                    to: vault_token_account_a.to_account_info(),
                    authority: authority.to_account_info(),
                }),
                amount_a,
                mint_a.decimals
            )?;
        }

        if hook_program_b.is_some() {
            let hook_program = hook_program_b.as_ref().unwrap();
            let mut cpi_instruction = hook_transfer_checked(
                token_program_b.key,
                &authority_token_account_a.key(),
                &mint_a.key(),
                &vault_token_account_a.key(),
                &authority.key(),
                &[],
                amount_b,
                mint_b.decimals
            )?;
            let mut cpi_account_infos = vec![
                authority_token_account_b.to_account_info(),
                mint_b.to_account_info(),
                vault_token_account_b.to_account_info(),
                authority.to_account_info()
            ];
            add_extra_accounts_for_execute_cpi(
                &mut cpi_instruction,
                &mut cpi_account_infos,
                hook_program.key,
                authority_token_account_b.to_account_info(),
                mint_b.to_account_info(),
                vault_token_account_b.to_account_info(),
                authority.to_account_info(),
                amount_b,
                remaining_accounts
            )?;
            invoke(&cpi_instruction, &cpi_account_infos)?;
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
        let hook_program_a = &ctx.accounts.hook_program_a;
        let hook_program_b = &ctx.accounts.hook_program_b;
        let remaining_accounts = &ctx.remaining_accounts;

        // make sure adding the lp doesn't exceed the users slippage
        let ratio = (
            (amount_a as f64) / (amount_b as f64) -
            (pool_amount_a as f64) / (pool_amount_b as f64)
        ).abs();
        if ratio > (slippage as f64) / 1000.0 {
            return err!(Error::SlippageExceeded);
        }

        // Transfer tokens to the vault
        if hook_program_a.is_some() {
            let hook_program = hook_program_a.as_ref().unwrap();
            let mut cpi_instruction = hook_transfer_checked(
                token_program_a.key,
                &authority_token_account_a.key(),
                &mint_a.key(),
                &vault_token_account_a.key(),
                &authority.key(),
                &[],
                amount_a,
                mint_a.decimals
            )?;
            let mut cpi_account_infos = vec![
                authority_token_account_a.to_account_info(),
                mint_a.to_account_info(),
                vault_token_account_a.to_account_info(),
                authority.to_account_info()
            ];
            add_extra_accounts_for_execute_cpi(
                &mut cpi_instruction,
                &mut cpi_account_infos,
                hook_program.key,
                authority_token_account_a.to_account_info(),
                mint_a.to_account_info(),
                vault_token_account_a.to_account_info(),
                authority.to_account_info(),
                amount_a,
                remaining_accounts
            )?;
            invoke(&cpi_instruction, &cpi_account_infos)?;
        } else {
            transfer_checked(
                CpiContext::new(token_program_a.to_account_info(), TransferChecked {
                    from: authority_token_account_a.to_account_info(),
                    mint: mint_a.to_account_info(),
                    to: vault_token_account_a.to_account_info(),
                    authority: authority.to_account_info(),
                }),
                amount_a,
                mint_a.decimals
            )?;
        }

        if hook_program_b.is_some() {
            let hook_program = hook_program_b.as_ref().unwrap();
            let mut cpi_instruction = hook_transfer_checked(
                token_program_b.key,
                &authority_token_account_b.key(),
                &mint_b.key(),
                &vault_token_account_b.key(),
                &authority.key(),
                &[],
                amount_b,
                mint_b.decimals
            )?;
            let mut cpi_account_infos = vec![
                authority_token_account_b.to_account_info(),
                mint_b.to_account_info(),
                vault_token_account_b.to_account_info(),
                authority.to_account_info()
            ];
            add_extra_accounts_for_execute_cpi(
                &mut cpi_instruction,
                &mut cpi_account_infos,
                hook_program.key,
                authority_token_account_b.to_account_info(),
                mint_b.to_account_info(),
                vault_token_account_b.to_account_info(),
                authority.to_account_info(),
                amount_b,
                remaining_accounts
            )?;
            invoke(&cpi_instruction, &cpi_account_infos)?;
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

        // Mint LP Tokens
        let upcasted_a = amount_a as u128;
        let upcasted_b = amount_b as u128;
        let upcasted_a_pool = pool_amount_a as u128;
        let upcasted_b_pool = pool_amount_b as u128;
        let upcasted_token_supply = pool.token_supply as u128;
        let parsed_amount_a = (upcasted_token_supply * upcasted_a) / upcasted_a_pool;
        let parsed_amount_b = (upcasted_token_supply * upcasted_b) / upcasted_b_pool;
        let liquidity_token_to_mint = cmp::min(parsed_amount_a, parsed_amount_b) as u64;
        mint_to(
            CpiContext::new(token_program.to_account_info(), MintTo {
                mint: liquidity_token.to_account_info(),
                to: authority_liquidity_token_account.to_account_info(),
                authority: vault.to_account_info(),
            }).with_signer(&[&[pool.key().as_ref(), &[vault_bump]]]),
            liquidity_token_to_mint
        )?;
        pool.token_supply += liquidity_token_to_mint;

        // Pay the platform fee
        invoke(
            &transfer(authority.key, &vault.key, config.platform_fee),
            &[authority.to_account_info(), vault.to_account_info()]
        )?;

        Ok(())
    }

    #[inline(never)]
    pub fn remove_liquidity<'info>(
        ctx: Context<'_, '_, '_, 'info, RemoveLiquidity<'info>>,
        liquidity: u64
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
        let hook_program_a = &ctx.accounts.hook_program_a;
        let hook_program_b = &ctx.accounts.hook_program_b;
        let remaining_accounts = &ctx.remaining_accounts;

        let upcasted_liquidity = liquidity as u128;
        let upcasted_pool_amount_a = pool_amount_a as u128;
        let upcasted_pool_amount_b = pool_amount_b as u128;
        let upcasted_liquidity_config = pool.token_supply as u128;
        let a_to_send = ((upcasted_liquidity * upcasted_pool_amount_a) /
            upcasted_liquidity_config) as u64;
        let b_to_send = ((upcasted_liquidity * upcasted_pool_amount_b) /
            upcasted_liquidity_config) as u64;

        // Transfer tokens from the vault
        if hook_program_a.is_some() {
            let hook_program = hook_program_a.as_ref().unwrap();
            let mut cpi_instruction = hook_transfer_checked(
                token_program_a.key,
                &vault_token_account_a.key(),
                &mint_a.key(),
                &authority_token_account_a.key(),
                &vault.key(),
                &[],
                a_to_send,
                mint_a.decimals
            )?;
            let mut cpi_account_infos = vec![
                vault_token_account_a.to_account_info(),
                mint_a.to_account_info(),
                authority_token_account_a.to_account_info(),
                vault.to_account_info()
            ];
            add_extra_accounts_for_execute_cpi(
                &mut cpi_instruction,
                &mut cpi_account_infos,
                hook_program.key,
                vault_token_account_a.to_account_info(),
                mint_a.to_account_info(),
                authority_token_account_a.to_account_info(),
                vault.to_account_info(),
                a_to_send,
                remaining_accounts
            )?;
            invoke_signed(
                &cpi_instruction,
                &cpi_account_infos,
                &[&[pool.key().as_ref(), &[vault_bump]]]
            )?;
        } else {
            transfer_checked(
                CpiContext::new(token_program_a.to_account_info(), TransferChecked {
                    from: vault_token_account_a.to_account_info(),
                    mint: mint_a.to_account_info(),
                    to: authority_token_account_a.to_account_info(),
                    authority: vault.to_account_info(),
                }).with_signer(&[&[pool.key().as_ref(), &[vault_bump]]]),
                a_to_send,
                mint_a.decimals
            )?;
        }

        if hook_program_b.is_some() {
            let hook_program = hook_program_b.as_ref().unwrap();
            let mut cpi_instruction = hook_transfer_checked(
                token_program_b.key,
                &vault_token_account_b.key(),
                &mint_b.key(),
                &authority_token_account_b.key(),
                &vault.key(),
                &[],
                b_to_send,
                mint_b.decimals
            )?;
            let mut cpi_account_infos = vec![
                vault_token_account_b.to_account_info(),
                mint_b.to_account_info(),
                authority_token_account_b.to_account_info(),
                vault.to_account_info()
            ];
            add_extra_accounts_for_execute_cpi(
                &mut cpi_instruction,
                &mut cpi_account_infos,
                hook_program.key,
                vault_token_account_b.to_account_info(),
                mint_b.to_account_info(),
                authority_token_account_b.to_account_info(),
                vault.to_account_info(),
                b_to_send,
                remaining_accounts
            )?;
            invoke_signed(
                &cpi_instruction,
                &cpi_account_infos,
                &[&[pool.key().as_ref(), &[vault_bump]]]
            )?;
        } else {
            transfer_checked(
                CpiContext::new(token_program_b.to_account_info(), TransferChecked {
                    from: vault_token_account_b.to_account_info(),
                    mint: mint_b.to_account_info(),
                    to: authority_token_account_b.to_account_info(),
                    authority: vault.to_account_info(),
                }).with_signer(&[&[pool.key().as_ref(), &[vault_bump]]]),
                b_to_send,
                mint_b.decimals
            )?;
        }

        // Burn LP Tokens
        burn(
            CpiContext::new(token_program.to_account_info(), Burn {
                mint: liquidity_token.to_account_info(),
                from: authority_liquidity_token_account.to_account_info(),
                authority: authority.to_account_info(),
            }).with_signer(&[&[pool.key().as_ref(), &[vault_bump]]]),
            liquidity
        )?;
        pool.token_supply -= liquidity;

        // Pay the platform fee
        invoke(
            &transfer(authority.key, &vault.key, config.platform_fee),
            &[authority.to_account_info(), vault.to_account_info()]
        )?;

        Ok(())
    }

    #[inline(never)]
    pub fn swap<'info>(
        ctx: Context<'_, '_, '_, 'info, Swap<'info>>,
        amount_a_in: u64,
        expected_amount_b_out: u64,
        slippage: u64
    ) -> Result<()> {
        // msg!("amount_a_in: {}", amount_a_in);
        // msg!("expected_amount_b_out: {}", expected_amount_b_out);
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
        let token_program_a = &ctx.accounts.token_program_a;
        let token_program_b = &ctx.accounts.token_program_b;
        let pool_amount_a = vault_token_account_a.amount;
        // msg!("pool_amount_a: {}", pool_amount_a);
        let pool_amount_b = vault_token_account_b.amount;
        // msg!("pool_amount_b: {}", pool_amount_b);
        let hook_program_a = &ctx.accounts.hook_program_a;
        let hook_program_b = &ctx.accounts.hook_program_b;
        let remaining_accounts = &ctx.remaining_accounts;

        let mint_binding = mint_a.to_account_info();
        let mint_data = &mint_binding.data.borrow();
        let mint = StateWithExtensions::<MintState>::unpack(&mint_data)?;
        let actual_amount = if
            let Ok(transfer_fee_config) = mint.get_extension::<TransferFeeConfig>()
        {
            let fee = transfer_fee_config
                .calculate_epoch_fee(Clock::get()?.epoch, amount_a_in)
                .ok_or(ProgramError::InvalidArgument)?;
            amount_a_in.saturating_sub(fee)
        } else {
            amount_a_in
        };

        let pool_constant = (pool_amount_a as u128) * (pool_amount_b as u128);
        // msg!("pool_constant: {}", pool_constant);
        let new_a_amount = (pool_amount_a as u128) + (actual_amount as u128);
        // msg!("new_a_amount: {}", new_a_amount);
        let new_b_amount = (pool_constant / new_a_amount) as u64;
        // msg!("new_b_amount: {}", new_b_amount);
        let real_amount_b_out = pool_amount_b - new_b_amount;
        // msg!("real_amount_b_out: {}", real_amount_b_out);
        let b_out_after_fees = ((real_amount_b_out as f64) *
            (1.0 - (pool.pool_fee as f64) / 10000.0)) as u64;
        // msg!("b_out_after_fees: {}", b_out_after_fees);

        // Fail on too much slippage
        let ratio = (
            ((real_amount_b_out as f64) - (expected_amount_b_out as f64)) /
            (real_amount_b_out as f64)
        ).abs();

        // msg!("ratio: {}", ratio);
        // msg!("slippage: {}", (slippage as f64) / 1000.0);

        if ratio > (slippage as f64) / 10000.0 {
            return err!(Error::SlippageExceeded);
        }

        // Transfer tokens to vault
        if hook_program_a.is_some() {
            let hook_program = hook_program_a.as_ref().unwrap();
            let mut cpi_instruction = hook_transfer_checked(
                token_program_a.key,
                &authority_token_account_a.key(),
                &mint_a.key(),
                &vault_token_account_a.key(),
                &authority.key(),
                &[],
                amount_a_in,
                mint_a.decimals
            )?;
            let mut cpi_account_infos = vec![
                authority_token_account_a.to_account_info(),
                mint_a.to_account_info(),
                vault_token_account_a.to_account_info(),
                authority.to_account_info()
            ];
            add_extra_accounts_for_execute_cpi(
                &mut cpi_instruction,
                &mut cpi_account_infos,
                hook_program.key,
                authority_token_account_a.to_account_info(),
                mint_a.to_account_info(),
                vault_token_account_a.to_account_info(),
                authority.to_account_info(),
                amount_a_in,
                remaining_accounts
            )?;
            invoke(&cpi_instruction, &cpi_account_infos)?;
        } else {
            transfer_checked(
                CpiContext::new(token_program_a.to_account_info(), TransferChecked {
                    from: authority_token_account_a.to_account_info(),
                    mint: mint_a.to_account_info(),
                    to: vault_token_account_a.to_account_info(),
                    authority: authority.to_account_info(),
                }),
                amount_a_in,
                mint_a.decimals
            )?;
        }

        // Transfer tokens from vault
        if hook_program_b.is_some() {
            let hook_program = hook_program_b.as_ref().unwrap();
            let mut cpi_instruction = hook_transfer_checked(
                token_program_b.key,
                &vault_token_account_b.key(),
                &mint_b.key(),
                &authority_token_account_b.key(),
                &vault.key(),
                &[],
                b_out_after_fees,
                mint_b.decimals
            )?;
            let mut cpi_account_infos = vec![
                vault_token_account_b.to_account_info(),
                mint_b.to_account_info(),
                authority_token_account_b.to_account_info(),
                vault.to_account_info()
            ];
            add_extra_accounts_for_execute_cpi(
                &mut cpi_instruction,
                &mut cpi_account_infos,
                hook_program.key,
                vault_token_account_b.to_account_info(),
                mint_b.to_account_info(),
                authority_token_account_b.to_account_info(),
                vault.to_account_info(),
                b_out_after_fees,
                remaining_accounts
            )?;
            invoke_signed(
                &cpi_instruction,
                &cpi_account_infos,
                &[&[pool.key().as_ref(), &[vault_bump]]]
            )?;
        } else {
            transfer_checked(
                CpiContext::new(token_program_b.to_account_info(), TransferChecked {
                    from: vault_token_account_b.to_account_info(),
                    mint: mint_b.to_account_info(),
                    to: authority_token_account_b.to_account_info(),
                    authority: vault.to_account_info(),
                }).with_signer(&[&[pool.key().as_ref(), &[vault_bump]]]),
                b_out_after_fees,
                mint_b.decimals
            )?;
        }

        // Pay the platform fee
        invoke(
            &transfer(authority.key, &vault.key, config.platform_fee),
            &[authority.to_account_info(), vault.to_account_info()]
        )?;

        Ok(())
    }

    #[inline(never)]
    pub fn collect_platform_fees<'info>(
        ctx: Context<'_, '_, '_, 'info, CollectPlatformFees<'info>>
    ) -> Result<()> {
        let pool = &ctx.accounts.pool;
        let vault = &ctx.accounts.vault;
        let vault_bump = ctx.bumps.vault;
        let fee_wallet = &ctx.accounts.fee_wallet;

        let accured_fees = vault.lamports() - 10000000;

        // Pay the platform fee
        invoke_signed(
            &transfer(vault.key, fee_wallet.key, accured_fees),
            &[vault.to_account_info(), fee_wallet.to_account_info()],
            &[&[pool.key().as_ref(), &[vault_bump]]]
        )?;

        Ok(())
    }
}

// Data Validation
#[derive(Accounts)]
pub struct InitPlatform<'info> {
    #[account(init, seeds = [b"config"], bump, payer = authority, space = 81)]
    pub config: Box<Account<'info, Config>>,
    #[account(mut)]
    pub authority: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct UpdatePlatformConfig<'info> {
    #[account(mut, seeds = [b"config"], bump, has_one = authority)]
    pub config: Box<Account<'info, Config>>,
    #[account(mut)]
    pub authority: Signer<'info>,
    /// CHECK: The config authority is allowed to change the fee wallet to any account
    pub fee_wallet: UncheckedAccount<'info>,
    pub system_program: Program<'info, System>,
}
// update
#[derive(Accounts)]
pub struct CreatePoolAccounts<'info> {
    #[account(mut)]
    pub authority: Signer<'info>,
    #[account(
        init,
        seeds = [&hash_strings([mint_a.key().to_string(), mint_b.key().to_string()])],
        bump,
        payer = authority,
        space = 120
    )]
    pub pool: Box<Account<'info, Pool>>,
    /// CHECK: Made safe by the seed check
    #[account(mut, seeds = [pool.key().as_ref()], bump)]
    pub vault: AccountInfo<'info>,
    pub mint_a: Box<InterfaceAccount<'info, Mint>>,
    pub mint_b: Box<InterfaceAccount<'info, Mint>>,
    #[account(
        init,
        seeds = [vault.key().as_ref()],
        bump,
        mint::decimals = 6,
        mint::authority = vault,
        payer = authority
    )]
    pub liquidity_token: Box<InterfaceAccount<'info, Mint>>,
    #[account(
        init,
        associated_token::mint = liquidity_token,
        associated_token::authority = authority,
        payer = authority
    )]
    pub authority_liquidity_token_account: Box<InterfaceAccount<'info, TokenAccount>>,
    pub token_program: Program<'info, Token>,
    pub associated_token_program: Program<'info, AssociatedToken>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
#[instruction(amount_a: u64, amount_b: u64)]
pub struct CreatePool<'info> {
    #[account(mut, seeds = [b"config"], bump, constraint = config.pools_enabled @ Error::DexDisabled)]
    pub config: Box<Account<'info, Config>>,
    #[account(mut, constraint = amount_a > 0 && amount_b > 0 @ Error::InvalidAmount)]
    pub authority: Signer<'info>,
    #[account(mut, seeds = [&hash_strings([mint_a.key().to_string(), mint_b.key().to_string()])], bump)]
    pub pool: Box<Account<'info, Pool>>,
    /// CHECK: Made safe by the seed check
    #[account(mut, seeds = [pool.key().as_ref()], bump)]
    pub vault: AccountInfo<'info>,
    pub mint_a: Box<InterfaceAccount<'info, Mint>>,
    pub mint_b: Box<InterfaceAccount<'info, Mint>>,
    #[account(
        mut,
        associated_token::mint = mint_a,
        associated_token::authority = authority,
        associated_token::token_program = token_program_a
    )]
    pub authority_token_account_a: Box<InterfaceAccount<'info, TokenAccount>>,
    #[account(
        mut,
        associated_token::mint = mint_b,
        associated_token::authority = authority,
        associated_token::token_program = token_program_b
    )]
    pub authority_token_account_b: Box<InterfaceAccount<'info, TokenAccount>>,
    #[account(
        mut,
        associated_token::mint = mint_a,
        associated_token::authority = vault,
        associated_token::token_program = token_program_a
    )]
    pub vault_token_account_a: Box<InterfaceAccount<'info, TokenAccount>>,
    #[account(
        mut,
        associated_token::mint = mint_b,
        associated_token::authority = vault,
        associated_token::token_program = token_program_b
    )]
    pub vault_token_account_b: Box<InterfaceAccount<'info, TokenAccount>>,
    #[account(mut, seeds = [vault.key().as_ref()], bump, mint::decimals = 6, mint::authority = vault)]
    pub liquidity_token: Box<InterfaceAccount<'info, Mint>>,
    #[account(mut, associated_token::mint = liquidity_token, associated_token::authority = authority)]
    pub authority_liquidity_token_account: Box<InterfaceAccount<'info, TokenAccount>>,
    pub token_program: Interface<'info, TokenInterface>,
    #[account(address = mint_a.to_account_info().owner.key())]
    pub token_program_a: Interface<'info, TokenInterface>,
    #[account(address = mint_b.to_account_info().owner.key())]
    pub token_program_b: Interface<'info, TokenInterface>,
    #[account(executable)]
    pub hook_program_a: Option<AccountInfo<'info>>,
    #[account(executable)]
    pub hook_program_b: Option<AccountInfo<'info>>,
    pub associated_token_program: Program<'info, AssociatedToken>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
#[instruction(amount_a: u64, amount_b: u64)]
pub struct AddLiquidity<'info> {
    #[account(mut, seeds = [b"config"], bump, constraint = config.pools_enabled @ Error::DexDisabled)]
    pub config: Box<Account<'info, Config>>,
    #[account(mut, constraint = amount_a > 0 && amount_b > 0 @ Error::InvalidAmount)]
    pub authority: Signer<'info>,
    #[account(mut, seeds = [&hash_strings([mint_a.key().to_string(), mint_b.key().to_string()])], bump)]
    pub pool: Box<Account<'info, Pool>>,
    #[account(mut, seeds = [pool.key().as_ref()], bump)]
    /// CHECK: Made safe by the seed check
    pub vault: AccountInfo<'info>,
    pub mint_a: Box<InterfaceAccount<'info, Mint>>,
    pub mint_b: Box<InterfaceAccount<'info, Mint>>,
    #[account(
        mut,
        associated_token::mint = mint_a,
        associated_token::authority = authority,
        associated_token::token_program = token_program_a
    )]
    pub authority_token_account_a: Box<InterfaceAccount<'info, TokenAccount>>,
    #[account(
        mut,
        associated_token::mint = mint_b,
        associated_token::authority = authority,
        associated_token::token_program = token_program_b
    )]
    pub authority_token_account_b: Box<InterfaceAccount<'info, TokenAccount>>,
    #[account(
        mut,
        associated_token::mint = mint_a,
        associated_token::authority = vault,
        associated_token::token_program = token_program_a
    )]
    pub vault_token_account_a: Box<InterfaceAccount<'info, TokenAccount>>,
    #[account(
        mut,
        associated_token::mint = mint_b,
        associated_token::authority = vault,
        associated_token::token_program = token_program_b
    )]
    pub vault_token_account_b: Box<InterfaceAccount<'info, TokenAccount>>,
    #[account(mut, seeds = [vault.key().as_ref()], bump, mint::decimals = 6, mint::authority = vault)]
    pub liquidity_token: Box<InterfaceAccount<'info, Mint>>,
    #[account(
        init_if_needed,
        associated_token::mint = liquidity_token,
        associated_token::authority = authority,
        payer = authority
    )]
    pub authority_liquidity_token_account: Box<InterfaceAccount<'info, TokenAccount>>,
    pub token_program: Program<'info, Token>,
    #[account(address = mint_a.to_account_info().owner.key())]
    pub token_program_a: Interface<'info, TokenInterface>,
    #[account(address = mint_b.to_account_info().owner.key())]
    pub token_program_b: Interface<'info, TokenInterface>,
    #[account(executable)]
    pub hook_program_a: Option<AccountInfo<'info>>,
    #[account(executable)]
    pub hook_program_b: Option<AccountInfo<'info>>,
    pub associated_token_program: Program<'info, AssociatedToken>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct RemoveLiquidity<'info> {
    #[account(mut, seeds = [b"config"], bump, constraint = config.pools_enabled @ Error::DexDisabled)]
    pub config: Box<Account<'info, Config>>,
    #[account(mut)]
    pub authority: Signer<'info>,
    #[account(mut, seeds = [&hash_strings([mint_a.key().to_string(), mint_b.key().to_string()])], bump)]
    pub pool: Box<Account<'info, Pool>>,
    /// CHECK: Made safe by the seed check
    #[account(mut, seeds = [pool.key().as_ref()], bump)]
    pub vault: AccountInfo<'info>,
    pub mint_a: Box<InterfaceAccount<'info, Mint>>,
    pub mint_b: Box<InterfaceAccount<'info, Mint>>,
    // cant init too big of the function do on front end
    #[account(
        mut,
        associated_token::mint = mint_a,
        associated_token::authority = authority,
        associated_token::token_program = token_program_a,
    )]
    pub authority_token_account_a: Box<InterfaceAccount<'info, TokenAccount>>,
    // cant init too big of the function do on front end
    #[account(
        mut,
        associated_token::mint = mint_b,
        associated_token::authority = authority,
        associated_token::token_program = token_program_b,
    )]
    pub authority_token_account_b: Box<InterfaceAccount<'info, TokenAccount>>,
    #[account(
        mut,
        associated_token::mint = mint_a,
        associated_token::authority = vault,
        associated_token::token_program = token_program_a
    )]
    pub vault_token_account_a: Box<InterfaceAccount<'info, TokenAccount>>,
    #[account(
        mut,
        associated_token::mint = mint_b,
        associated_token::authority = vault,
        associated_token::token_program = token_program_b
    )]
    pub vault_token_account_b: Box<InterfaceAccount<'info, TokenAccount>>,
    #[account(mut, seeds = [vault.key().as_ref()], bump, mint::decimals = 6, mint::authority = vault)]
    pub liquidity_token: Box<InterfaceAccount<'info, Mint>>,
    #[account(mut, associated_token::mint = liquidity_token, associated_token::authority = authority)]
    pub authority_liquidity_token_account: Box<InterfaceAccount<'info, TokenAccount>>,
    pub token_program: Program<'info, Token>,
    #[account(address = mint_a.to_account_info().owner.key())]
    pub token_program_a: Interface<'info, TokenInterface>,
    #[account(address = mint_b.to_account_info().owner.key())]
    pub token_program_b: Interface<'info, TokenInterface>,
    #[account(executable)]
    pub hook_program_a: Option<AccountInfo<'info>>,
    #[account(executable)]
    pub hook_program_b: Option<AccountInfo<'info>>,
    pub associated_token_program: Program<'info, AssociatedToken>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct Swap<'info> {
    #[account(mut, seeds = [b"config"], bump, constraint = config.pools_enabled @ Error::DexDisabled)]
    pub config: Box<Account<'info, Config>>,
    #[account(mut)]
    pub authority: Signer<'info>,
    #[account(seeds = [&hash_strings([mint_a.key().to_string(), mint_b.key().to_string()])], bump)]
    pub pool: Box<Account<'info, Pool>>,
    /// CHECK: Made safe by the seed check
    #[account(mut, seeds = [pool.key().as_ref()], bump)]
    pub vault: AccountInfo<'info>,
    pub mint_a: Box<InterfaceAccount<'info, Mint>>,
    pub mint_b: Box<InterfaceAccount<'info, Mint>>,
    #[account(
        mut,
        associated_token::mint = mint_a,
        associated_token::authority = authority,
        associated_token::token_program = token_program_a
    )]
    pub authority_token_account_a: Box<InterfaceAccount<'info, TokenAccount>>,
    #[account(
        init_if_needed,
        associated_token::mint = mint_b,
        associated_token::authority = authority,
        associated_token::token_program = token_program_b,
        payer = authority
    )]
    pub authority_token_account_b: Box<InterfaceAccount<'info, TokenAccount>>,
    #[account(
        mut,
        associated_token::mint = mint_a,
        associated_token::authority = vault,
        associated_token::token_program = token_program_a
    )]
    pub vault_token_account_a: Box<InterfaceAccount<'info, TokenAccount>>,
    #[account(
        mut,
        associated_token::mint = mint_b,
        associated_token::authority = vault,
        associated_token::token_program = token_program_b
    )]
    pub vault_token_account_b: Box<InterfaceAccount<'info, TokenAccount>>,
    #[account(address = mint_a.to_account_info().owner.key())]
    pub token_program_a: Interface<'info, TokenInterface>,
    #[account(address = mint_b.to_account_info().owner.key())]
    pub token_program_b: Interface<'info, TokenInterface>,
    #[account(executable)]
    pub hook_program_a: Option<AccountInfo<'info>>,
    #[account(executable)]
    pub hook_program_b: Option<AccountInfo<'info>>,
    pub associated_token_program: Program<'info, AssociatedToken>,
    pub token_program: Program<'info, Token>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct CollectPlatformFees<'info> {
    #[account(seeds = [b"config"], bump)]
    pub config: Box<Account<'info, Config>>,
    #[account(mut)]
    pub authority: Signer<'info>,
    /// CHECK: The is allowed to collect fees from any pool
    pub pool: AccountInfo<'info>,
    /// CHECK: Made safe by the seed check
    #[account(mut, seeds = [pool.key().as_ref()], bump)]
    pub vault: AccountInfo<'info>,
    /// CHECK: Made safe by the address check
    #[account(mut, address = config.fee_wallet)]
    pub fee_wallet: AccountInfo<'info>,
    pub system_program: Program<'info, System>,
}

// Data Structures

// Config Account 8 + 32 + 32 + 8 + 1 = 81 bytes
#[account]
pub struct Config {
    pub authority: Pubkey,
    pub fee_wallet: Pubkey,
    // in basis points
    pub platform_fee: u64,
    pub pools_enabled: bool,
}

// Config Account 8 + 32 + 32 + 32 + 8 + 8 = 120 bytes
#[account]
pub struct Pool {
    pub authority: Pubkey,
    pub vault: Pubkey,
    pub liquidity_token: Pubkey,
    pub token_supply: u64,
    // in basis points
    pub pool_fee: u64,
}

// Data Error Codes
#[error_code]
pub enum Error {
    #[msg("The dex is currently shut down")]
    DexDisabled,
    #[msg("Slippage exceeded the maximum allowed amount")]
    SlippageExceeded,
    #[msg("Both amounts must be greater than 0")]
    InvalidAmount,
}

// Data Utility Functions
#[inline(never)]
pub fn hash_strings(strings: [String; 2]) -> Vec<u8> {
    let mut char_set: HashSet<u8> = HashSet::new();
    // Iterate through each string and add its characters to the set
    for s in strings {
        for c in s.bytes() {
            char_set.insert(c);
        }
    }
    // Convert the set to a sorted vector of characters
    let mut char_vec: Vec<u8> = char_set.into_iter().collect();
    char_vec.sort();
    // Convert the sorted vector back to a string
    let combined_string: String = String::from_utf8(char_vec).unwrap();
    // Calculate the SHA-256 hash
    let hash = Sha256::digest(combined_string.as_bytes());
    hash.to_vec()
}

// Data Tests
#[cfg(test)]
mod tests {
    use solana_program::pubkey::Pubkey;
    use std::cmp;
    use crate::hash_strings;
    use solana_program::pubkey;

    #[test]
    fn hash_test() {
        let seeds = hash_strings([
            String::from("7fMhbovg7PtxQWcCffWZAYj5obSPEGtQbo5xSvE5B6zs"),
            String::from("So11111111111111111111111111111111111111112"),
        ]);
        let key = Pubkey::find_program_address(
            &[&seeds],
            &pubkey!("pDEX9VxuEnKR9LS3w7QFTrX9L8EpQfftw3y3a8rp59h")
        );
        println!("key: {}", key.0.to_string());
    }

    #[test]
    fn create_pool() {
        let amount_a: u64 = 100000000;
        let amount_b: u64 = 100000000;
        let k_last: u64 = amount_a * amount_b;
        println!("k_last: {}", k_last);
        let token_supply = (((amount_a as f64) * (amount_b as f64)).sqrt() - 1000.0) as u64;
        println!("token supply: {}", token_supply);
    }

    #[test]
    fn add_liquidity() {
        let amount_a: u128 = 100000000 + 50000;
        let amount_b: u128 = 100000000 + 100000;
        let token_supply: u128 = 99999000;
        let pool_amount_a: u128 = 100000000 + 50000;
        let pool_amount_b: u128 = 100000000 + 100000;
        let parsed_amount_a: u128 = (token_supply * amount_a) / pool_amount_a;
        let parsed_amount_b: u128 = (token_supply * amount_b) / pool_amount_b;
        let k_last: u128 = 10000000000000000;

        let liquidity_token_to_mint = cmp::min(parsed_amount_a, parsed_amount_b) as u64;
        println!("liquidity token to mint: {}", liquidity_token_to_mint);

        let root_k: f64 = ((pool_amount_a * pool_amount_b) as f64).sqrt();
        println!("root_k: {}", root_k);
        let root_k_last = (k_last as f64).sqrt();
        println!("root k last: {}", root_k_last);

        if root_k > root_k_last {
            let numerator = (token_supply as f64) * (root_k - root_k_last);
            let denominator = root_k * 3.0 + root_k_last;
            let liquidity = numerator / denominator;
            if liquidity > 0.0 {
                println!("Minting liquidity: {}", liquidity as u64);
            }
        }

        let k_next: u64 = ((pool_amount_a + amount_a) * (pool_amount_b + amount_b)) as u64;
        print!("k_next: {}", k_next);
    }

    #[test]
    fn remove_liquidity() {
        let liquidity: u128 = 99999000;
        let pool_amount_a: u128 = 100000000 + 50000 + 100000000 + 50000;
        let pool_amount_b: u128 = 100000000 + 50000 + 100000000 + 100000;
        let token_supply: u128 = 99999000 + 99999000 + 18738;
        let k_last: u128 = 40060020000000000;
        let amount_a: u128 = (liquidity * pool_amount_a) / token_supply;
        println!("amount_a: {}", amount_a as u64);
        let amount_b: u128 = (liquidity * pool_amount_b) / token_supply;
        println!("amount_b: {}", amount_b as u64);

        let root_k: f64 = ((pool_amount_a * pool_amount_b) as f64).sqrt();
        println!("root_k: {}", root_k);
        let root_k_last = (k_last as f64).sqrt();
        println!("root k last: {}", root_k_last);

        if root_k > root_k_last {
            let numerator = (token_supply as f64) * (root_k - root_k_last);
            let denominator = root_k * 3.0 + root_k_last;
            let liquidity = numerator / denominator;
            if liquidity > 0.0 {
                println!("Minting liquidity: {}", liquidity as u64);
            }
        }
        let k_next: u64 = ((pool_amount_a - amount_a) * (pool_amount_b - amount_b)) as u64;
        print!("k_next: {}", k_next);
    }
}

// TODO: add restrictions to create pool
// To create a pool you must add over 0 amount of both tokens
