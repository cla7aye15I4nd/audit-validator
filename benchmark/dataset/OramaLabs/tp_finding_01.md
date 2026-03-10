# LaunchPool Account Can Be Falsified Allowing Unauthorized Token Withdrawal


| Field | Value |
| --- | --- |
| Type | True Positive |
| Severity | 🟠 Major |
| Triage Verdict | ✅ Valid |
| Project ID | `775c3200-9199-11f0-8f30-3de48404a1d9` |
| Commit | `7d27638f77c1bf7a8d0928fa3d7acab92afa8763` |

## Location

- **Local path:** `./src/programs/launchpad/src/instructions/claim_creator_tokens.rs`
- **ACC link:** https://acc.audit.certikpowered.info/project/775c3200-9199-11f0-8f30-3de48404a1d9/source?file=$/github/AllBlockChain/launchpad-program/7d27638f77c1bf7a8d0928fa3d7acab92afa8763/programs/launchpad/src/instructions/claim_creator_tokens.rs
- **Lines:** 28–33

## Description

The `ClaimCreatorTokens` instruction allows withdrawal of tokens to the `creator_token_account`. The instruction enforces that the caller is the project creator, but the `launch_pool` account itself is not protected by a PDA constraint—it can be any account provided by the caller. An attacker can create a fake `launch_pool` account with the `status` field set to `Migrated`, bypassing the checks. Since the instruction relies on `launch_pool.token_vault` to transfer tokens, the attacker can redirect assets to their own account or any arbitrary account, effectively stealing all tokens in the pool. This vulnerability stems from a missing deterministic derivation and validation of the `launch_pool` account. Other functions also have similar issues.

**instructions/claim_creator_tokens.rs**
```rust=28
    #[account(
        mut,
        constraint = launch_pool.status == LaunchStatus::Migrated @ LaunchpadError::InvalidStatus,
    )]
    pub launch_pool: Box<Account<'info, LaunchPool>>,

```

**instructions/claim_creator_tokens.rs**
```rust=25
    #[account(
        mut,
        constraint = launch_pool.status == LaunchStatus::Failed || launch_pool.status == LaunchStatus::Migrated @ LaunchpadError::InvalidStatus,
    )]
    pub launch_pool: Box<Account<'info, LaunchPool>>,

```

**instructions/collect_pool_fees.rs**
```rust=19
    #[account(
        mut,
        constraint = launch_pool.is_migrated() @ LaunchpadError::NotMigrated,
    )]
    pub launch_pool: Box<Account<'info, LaunchPool>>,
```
**instructions/finalize_launch.rs**
```rust=14
    #[account(
        mut,
        constraint = launch_pool.is_active() @ LaunchpadError::LaunchNotActive,
    )]
    pub launch_pool: Box<Account<'info, LaunchPool>>,
```

**instructions/meteora_pool.rs**
```rust=17
    #[account(
        mut,
        constraint = launch_pool.is_success() @ LaunchpadError::LaunchFailed,
    )]
    pub launch_pool: Box<Account<'info, LaunchPool>>,
```
**instructions/participate_with_points.rs**

```rust=42
    #[account(
        mut,
        constraint = launch_pool.is_active() @ LaunchpadError::LaunchNotActive,
    )]
    pub launch_pool: Box<Account<'info, LaunchPool>>,
```

## Recommendation

Derive the `launch_pool` account from deterministic seeds and the program ID using PDA. Include a `seeds` constraint in the account validation to ensure that only legitimate `launch_pool` accounts can be used in `ClaimCreatorTokens`.

## Vulnerable Code

```
use anchor_lang::prelude::*;
use anchor_spl::token::{self, Token, TokenAccount, Transfer};

use crate::const_pda::const_authority::VAULT_BUMP;
use crate::constants::{TOKEN_VAULT, VAULT_AUTHORITY};
use crate::errors::LaunchpadError;
use crate::state::{LaunchPool, LaunchStatus};
use crate::events::CreatorTokensClaimed;

#[derive(Accounts)]
pub struct ClaimCreatorTokens<'info> {
    /// Creator account, must be the project creator
    #[account(
        mut,
        constraint = creator.key() == launch_pool.creator @ LaunchpadError::NotCreator
    )]
    pub creator: Signer<'info>,

    /// vault authority
    #[account(
        mut,
        seeds = [VAULT_AUTHORITY.as_ref()],
        bump,
    )]
    pub vault_authority: SystemAccount<'info>,

    /// Launch pool account, must be migrated
    #[account(
        mut,
        constraint = launch_pool.status == LaunchStatus::Migrated @ LaunchpadError::InvalidStatus,
    )]
    pub launch_pool: Box<Account<'info, LaunchPool>>,

    /// Launch pool token vault
    #[account(
        mut,
        seeds = [TOKEN_VAULT, vault_authority.key().as_ref(), launch_pool.token_mint.as_ref()],
        bump,
        token::mint = launch_pool.token_mint,
        token::authority = vault_authority,
        address = launch_pool.token_vault,
        constraint = launch_pool.token_vault == pool_token_vault.key() @ LaunchpadError::InvalidTokenVault
    )]
    pub pool_token_vault: Box<Account<'info, TokenAccount>>,

    /// Creator token receiving account
    #[account(
        mut,
        token::mint = launch_pool.token_mint,
        token::authority = creator,
    )]
    pub creator_token_account: Box<Account<'info, TokenAccount>>,

    pub token_program: Program<'info, Token>,
}

/// Creator claim tokens (supports batch claiming)
pub fn claim_creator_tokens(ctx: Context<ClaimCreatorTokens>) -> Result<()> {
    let launch_pool = &mut ctx.accounts.launch_pool;
    let clock = Clock::get()?;
    let current_time = clock.unix_timestamp;

    // Calculate current new claimable amount (already automatically deducts claimed amount)
```
