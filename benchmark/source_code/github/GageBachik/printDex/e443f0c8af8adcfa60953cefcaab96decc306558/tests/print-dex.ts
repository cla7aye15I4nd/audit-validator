import * as anchor from "@coral-xyz/anchor";
import { BN, Program } from "@coral-xyz/anchor";
import { PrintDex } from "../target/types/print_dex";
import {
  AccountMeta,
  ComputeBudgetProgram,
  PublicKey,
  Transaction,
  TransactionMessage,
  VersionedTransaction,
} from "@solana/web3.js";
import crypto from "crypto";
import {
  ASSOCIATED_TOKEN_PROGRAM_ID,
  TOKEN_2022_PROGRAM_ID,
  TOKEN_PROGRAM_ID,
  addExtraAccountMetasForExecute,
  createAssociatedTokenAccount,
  createAssociatedTokenAccountIdempotent,
  createAssociatedTokenAccountIdempotentInstruction,
  createExecuteInstruction,
  createTransferCheckedInstruction,
  createTransferCheckedWithTransferHookInstruction,
  getAssociatedTokenAddressSync,
  getExtraAccountMetaAddress,
  getExtraAccountMetas,
  getMint,
  getTransferHook,
  resolveExtraAccountMeta,
  getAccount,
  transfer,
  unpackSeeds,
} from "@solana/spl-token";

import { bs58 } from "@coral-xyz/anchor/dist/cjs/utils/bytes";

// Create the priority fee instructions
const computePriceIx = ComputeBudgetProgram.setComputeUnitPrice({
  microLamports: 6,
});

const computeLimitIx = ComputeBudgetProgram.setComputeUnitLimit({
  units: 500_000,
});

const systemKey = new PublicKey("11111111111111111111111111111111");

const globalAddressLookupTableAddress = new PublicKey(
  "HXymiEoZzgb5emVa1NLexeMqmwx1wQegTB3dN6Yh8x1i"
);

// Utility Functions
function absBigInt(n) {
  return n < BigInt(0) ? -n : n;
}
function hashStrings(strings: string[]): Uint8Array {
  const wordSet = new Set<string>();
  // Iterate through each string and add its characters to the set
  for (const str of strings) {
    for (const char of str) {
      wordSet.add(char);
    }
  }
  // Convert the set back to a string
  const combinedString = Array.from(wordSet).sort().join("");
  // Calculate the SHA-256 hash
  const hash = crypto
    .createHash("sha256")
    .update(combinedString, "utf-8")
    .digest("hex");
  return Uint8Array.from(Buffer.from(hash, "hex"));
}
function deEscalateAccountMeta(
  accountMeta: AccountMeta,
  accountMetas: AccountMeta[]
): AccountMeta {
  const maybeHighestPrivileges = accountMetas
    .filter((x) => x.pubkey === accountMeta.pubkey)
    .reduce<{ isSigner: boolean; isWritable: boolean } | undefined>(
      (acc, x) => {
        if (!acc) return { isSigner: x.isSigner, isWritable: x.isWritable };
        return {
          isSigner: acc.isSigner || x.isSigner,
          isWritable: acc.isWritable || x.isWritable,
        };
      },
      undefined
    );
  if (maybeHighestPrivileges) {
    const { isSigner, isWritable } = maybeHighestPrivileges;
    if (!isSigner && isSigner !== accountMeta.isSigner) {
      accountMeta.isSigner = false;
    }
    if (!isWritable && isWritable !== accountMeta.isWritable) {
      accountMeta.isWritable = false;
    }
  }
  return accountMeta;
}

describe("print-dex", () => {
  const provider = anchor.AnchorProvider.env();
  anchor.setProvider(provider);
  const wallet = provider.wallet as anchor.Wallet;
  const connection = provider.connection;
  const program = anchor.workspace.PrintDex as Program<PrintDex>;

  const [config] = anchor.web3.PublicKey.findProgramAddressSync(
    [Buffer.from("config")],
    program.programId
  );

  console.log("config", config.toString());

  // Transfer hook mint:
  const hookMint = new PublicKey("6rN7ooKeSarPQBCzifeCdHTG3k2yT7UgEpMDUKTVS1G");

  // Wrapped Solana mint:
  const wrappedSolanaMint = new PublicKey(
    "So11111111111111111111111111111111111111112"
  );

  const poolSeeds = hashStrings([
    hookMint.toString(),
    wrappedSolanaMint.toString(),
  ]);
  // Pool address
  const [pool] = anchor.web3.PublicKey.findProgramAddressSync(
    [poolSeeds],
    program.programId
  );
  console.log("pool", pool.toString());
  // Vault address
  const [vault] = anchor.web3.PublicKey.findProgramAddressSync(
    [pool.toBuffer()],
    program.programId
  );
  console.log("vault", vault.toString());
  // Liquidity token address
  const [liquidityToken] = anchor.web3.PublicKey.findProgramAddressSync(
    [vault.toBuffer()],
    program.programId
  );
  console.log("liquidityToken", liquidityToken.toString());
  // authority hook token account
  const authorityHookAccount = getAssociatedTokenAddressSync(
    hookMint,
    wallet.publicKey,
    true,
    TOKEN_2022_PROGRAM_ID,
    ASSOCIATED_TOKEN_PROGRAM_ID
  );
  // const authorityHookAccountWrong = getAssociatedTokenAddressSync(
  //   hookMint,
  //   wallet.publicKey,
  //   true,
  //   TOKEN_PROGRAM_ID,
  //   ASSOCIATED_TOKEN_PROGRAM_ID
  // );
  // console.log(
  //   "authorityHookAccountWrong",
  //   authorityHookAccountWrong.toString()
  // );
  // vault hook token account
  const vaultHookAccount = getAssociatedTokenAddressSync(
    hookMint,
    vault,
    true,
    TOKEN_2022_PROGRAM_ID,
    ASSOCIATED_TOKEN_PROGRAM_ID
  );
  // const vaultHookAccountWrong = getAssociatedTokenAddressSync(
  //   hookMint,
  //   vault,
  //   true,
  //   TOKEN_PROGRAM_ID,
  //   ASSOCIATED_TOKEN_PROGRAM_ID
  // );
  // console.log("vaultHookAccountWrong", vaultHookAccountWrong.toString());
  // authority wrapped solana token account
  const authorityWSOLAccount = getAssociatedTokenAddressSync(
    wrappedSolanaMint,
    wallet.publicKey,
    true,
    TOKEN_PROGRAM_ID,
    ASSOCIATED_TOKEN_PROGRAM_ID
  );
  // const authorityWSOLAccountWrong = getAssociatedTokenAddressSync(
  //   wrappedSolanaMint,
  //   wallet.publicKey,
  //   true,
  //   TOKEN_2022_PROGRAM_ID,
  //   ASSOCIATED_TOKEN_PROGRAM_ID
  // );
  // console.log(
  //   "authorityWSOLAccountWrong",
  //   authorityWSOLAccountWrong.toString()
  // );
  // vault wrapped solana token account
  const vaultWSOLAccount = getAssociatedTokenAddressSync(
    wrappedSolanaMint,
    vault,
    true,
    TOKEN_PROGRAM_ID,
    ASSOCIATED_TOKEN_PROGRAM_ID
  );
  // const vaultWSOLAccountWrong = getAssociatedTokenAddressSync(
  //   wrappedSolanaMint,
  //   vault,
  //   true,
  //   TOKEN_2022_PROGRAM_ID,
  //   ASSOCIATED_TOKEN_PROGRAM_ID
  // );
  // console.log("vaultWSOLAccountWrong", vaultWSOLAccountWrong.toString());
  // authority liquidity token account
  const authorityLiquidityAccount = getAssociatedTokenAddressSync(
    liquidityToken,
    wallet.publicKey,
    true,
    TOKEN_PROGRAM_ID,
    ASSOCIATED_TOKEN_PROGRAM_ID
  );

  // it("Init The Platform!", async () => {
  //   const [config, _] = anchor.web3.PublicKey.findProgramAddressSync(
  //     [Buffer.from("config")],
  //     program.programId
  //   );
  //   // Add your test here.
  //   const tx = await program.methods
  //     .initPlatform()
  //     .accounts({
  //       config,
  //       authority: wallet.publicKey,
  //     })
  //     .rpc();
  //   console.log("Your transaction signature", tx);
  // });

  it("Create a pool!", async () => {
    // Get Transfer Hook Accounts
    const remainingAccounts: AccountMeta[] = [];
    // first grab mint info
    // const mintInfo = await getMint(
    //   connection,
    //   hookMint,
    //   "processed",
    //   TOKEN_2022_PROGRAM_ID
    // );
    // console.log("mintInfo", mintInfo);
    // // then grab xfer hook info
    // const transferHook = getTransferHook(mintInfo);
    // console.log("transferHook", transferHook);

    const info = await connection.getAccountInfo(wrappedSolanaMint);
    console.log("info", info);

    const infotwo = await connection.getAccountInfo(hookMint);
    console.log("infotwo", infotwo);

    // const validateStatePubkey = getExtraAccountMetaAddress(
    //   hookMint,
    //   transferHook.programId
    // );
    // const validateStateAccount = await connection.getAccountInfo(
    //   validateStatePubkey,
    //   "processed"
    // );
    // // grab the extra meta account make sure its valid
    // if (validateStateAccount == null) {
    //   throw new Error("Invalid validation state account");
    // }
    // const validateStateData = getExtraAccountMetas(validateStateAccount);
    // // create an execute instruction
    // const executeInstruction = createExecuteInstruction(
    //   transferHook.programId,
    //   authorityHookAccount,
    //   hookMint,
    //   vaultHookAccount,
    //   wallet.publicKey,
    //   validateStatePubkey,
    //   BigInt(20000000000)
    // );
    // // resolve the extra accounts from the extra meta account
    // for (const extraAccountMeta of validateStateData) {
    //   executeInstruction.keys.push(
    //     deEscalateAccountMeta(
    //       await resolveExtraAccountMeta(
    //         connection,
    //         extraAccountMeta,
    //         executeInstruction.keys,
    //         executeInstruction.data,
    //         executeInstruction.programId
    //       ),
    //       executeInstruction.keys
    //     )
    //   );
    // }

    // // Add only the extra accounts resolved from the validation state
    // remainingAccounts.push(...executeInstruction.keys.slice(5));

    // // Add the transfer hook program ID and the validation state account
    // remainingAccounts.push({
    //   pubkey: transferHook.programId,
    //   isSigner: false,
    //   isWritable: false,
    // });
    // remainingAccounts.push({
    //   pubkey: validateStatePubkey,
    //   isSigner: false,
    //   isWritable: false,
    // });

    // const createVaultHookMintAccountIx =
    //   createAssociatedTokenAccountIdempotentInstruction(
    //     wallet.publicKey,
    //     vaultHookAccount,
    //     vault,
    //     hookMint,
    //     TOKEN_2022_PROGRAM_ID
    //   );

    // const createVaultWSOLAccountAccountIx =
    //   createAssociatedTokenAccountIdempotentInstruction(
    //     wallet.publicKey,
    //     vaultWSOLAccount,
    //     vault,
    //     wrappedSolanaMint,
    //     TOKEN_PROGRAM_ID
    //   );

    // console.log("--------------------");
    // console.log("vaultHookAccount", vaultHookAccount.toString());
    // console.log("vaultWSOLAccount", vaultWSOLAccount.toString());
    // console.log("authorityWSOLAccount", authorityWSOLAccount.toString());
    // console.log("authorityHookAccount", authorityHookAccount.toString());

    // const createPoolAccountsIx = await program.methods
    //   .createPoolAccounts()
    //   .accounts({
    //     authority: wallet.publicKey,
    //     pool,
    //     vault,
    //     mintA: hookMint,
    //     mintB: wrappedSolanaMint,
    //     liquidityToken,
    //     authorityLiquidityTokenAccount: authorityLiquidityAccount,
    //     tokenProgram: TOKEN_PROGRAM_ID,
    //     associatedTokenProgram: ASSOCIATED_TOKEN_PROGRAM_ID,
    //     systemProgram: systemKey,
    //   })
    //   .instruction();
    // const createPoolIx = await program.methods
    //   .createPool(new BN(20000000000), new BN(10000000))
    //   .accounts({
    //     config,
    //     authority: wallet.publicKey,
    //     pool,
    //     vault,
    //     mintA: hookMint,
    //     mintB: wrappedSolanaMint,
    //     authorityTokenAccountA: authorityHookAccount,
    //     authorityTokenAccountB: authorityWSOLAccount,
    //     vaultTokenAccountA: vaultHookAccount,
    //     vaultTokenAccountB: vaultWSOLAccount,
    //     liquidityToken,
    //     authorityLiquidityTokenAccount: authorityLiquidityAccount,
    //     tokenProgram: TOKEN_PROGRAM_ID,
    //     tokenProgramA: TOKEN_2022_PROGRAM_ID,
    //     tokenProgramB: TOKEN_PROGRAM_ID,
    //     hookProgramA: transferHook.programId,
    //     hookProgramB: null,
    //     associatedTokenProgram: ASSOCIATED_TOKEN_PROGRAM_ID,
    //     systemProgram: systemKey,
    //   })
    //   .remainingAccounts(remainingAccounts)
    //   .instruction();

    // // get the table from the cluster
    // const lookupTableAccount = (
    //   await connection.getAddressLookupTable(globalAddressLookupTableAddress)
    // ).value;

    // // had to move the create account ix's off the create pool function to save on stack space
    // // construct a v0 compatible transaction `Message`
    // const messageV0 = new TransactionMessage({
    //   payerKey: wallet.publicKey,
    //   recentBlockhash: (await connection.getLatestBlockhash()).blockhash,
    //   instructions: [
    //     computePriceIx,
    //     computeLimitIx,
    //     createPoolAccountsIx,
    //     createVaultHookMintAccountIx,
    //     createVaultWSOLAccountAccountIx,
    //     createPoolIx,
    //   ], // note this is an array of instructions
    // }).compileToV0Message([lookupTableAccount]);

    // // create a v0 transaction from the v0 message
    // const transactionV0 = new VersionedTransaction(messageV0);

    // try {
    //   const tx = await provider.sendAndConfirm(transactionV0, [], {
    //     // skipPreflight: true,
    //   });
    //   console.log("Your transaction signature", tx);
    // } catch (e) {
    //   console.log(e);
    // }
  });

  // it("Swap!", async () => {
  //   // Get Transfer Hook Accounts
  //   const remainingAccounts: AccountMeta[] = [];
  //   // first grab mint info
  //   const mintInfo = await getMint(
  //     connection,
  //     hookMint,
  //     "processed",
  //     TOKEN_2022_PROGRAM_ID
  //   );
  //   // console.log("mintInfo", mintInfo);
  //   // then grab xfer hook info
  //   const transferHook = getTransferHook(mintInfo);
  //   const validateStatePubkey = getExtraAccountMetaAddress(
  //     hookMint,
  //     transferHook.programId
  //   );
  //   const validateStateAccount = await connection.getAccountInfo(
  //     validateStatePubkey,
  //     "processed"
  //   );
  //   // grab the extra meta account make sure its valid
  //   if (validateStateAccount == null) {
  //     throw new Error("Invalid validation state account");
  //   }
  //   const validateStateData = getExtraAccountMetas(validateStateAccount);
  //   // create an execute instruction
  //   const executeInstruction = createExecuteInstruction(
  //     transferHook.programId,
  //     authorityHookAccount,
  //     hookMint,
  //     vaultHookAccount,
  //     wallet.publicKey,
  //     validateStatePubkey,
  //     BigInt(20000000000)
  //   );
  //   // resolve the extra accounts from the extra meta account
  //   for (const extraAccountMeta of validateStateData) {
  //     executeInstruction.keys.push(
  //       deEscalateAccountMeta(
  //         await resolveExtraAccountMeta(
  //           connection,
  //           extraAccountMeta,
  //           executeInstruction.keys,
  //           executeInstruction.data,
  //           executeInstruction.programId
  //         ),
  //         executeInstruction.keys
  //       )
  //     );
  //   }

  //   // Add only the extra accounts resolved from the validation state
  //   remainingAccounts.push(...executeInstruction.keys.slice(5));

  //   // Add the transfer hook program ID and the validation state account
  //   remainingAccounts.push({
  //     pubkey: transferHook.programId,
  //     isSigner: false,
  //     isWritable: false,
  //   });
  //   remainingAccounts.push({
  //     pubkey: validateStatePubkey,
  //     isSigner: false,
  //     isWritable: false,
  //   });

  //   const createVaultWSOLAccountAccountIx =
  //     createAssociatedTokenAccountIdempotentInstruction(
  //       wallet.publicKey,
  //       vaultWSOLAccount,
  //       vault,
  //       wrappedSolanaMint,
  //       TOKEN_PROGRAM_ID
  //     );

  //   console.log("--------------------");
  //   console.log("vaultHookAccount", vaultHookAccount.toString());
  //   console.log("vaultWSOLAccount", vaultWSOLAccount.toString());
  //   console.log("authorityWSOLAccount", authorityWSOLAccount.toString());
  //   console.log("authorityHookAccount", authorityHookAccount.toString());

  //   const vaultHookAccountInfo = await getAc\count(
  //     connection,
  //     vaultHookAccount,
  //     "processed",
  //     TOKEN_2022_PROGRAM_ID
  //   );
  //   // console.log("vaultHookAccountInfo", vaultHookAccountInfo);

  //   const vaultWSOLAccountInfo = await getAccount(
  //     connection,
  //     vaultWSOLAccount,
  //     "processed",
  //     TOKEN_PROGRAM_ID
  //   );
  //   // console.log("vaultWSOLAccountInfo", vaultWSOLAccountInfo);

  //   // let pool_constant = (pool_amount_a as u128) * (pool_amount_b as u128);
  //   // let new_a_amount = (pool_amount_a as u128) + (amount_a_in as u128);
  //   // let new_b_amount = (pool_constant / new_a_amount) as u64;
  //   // let real_amount_b_out = pool_amount_b - new_b_amount;
  //   // let b_out_after_fees = ((real_amount_b_out as f64) *
  //   //     (1.0 - (pool.pool_fee as f64) / 10000.0)) as u64;

  //   console.log("pool amount a", vaultHookAccountInfo.amount.toString());
  //   console.log("pool amount b", vaultWSOLAccountInfo.amount.toString());
  //   // calculate the amount out
  //   const amountToSwap = BigInt(1000000000);
  //   // Expected out
  //   const poolRatio = vaultHookAccountInfo.amount / vaultWSOLAccountInfo.amount;
  //   const amountToRecieve = amountToSwap / poolRatio;
  //   console.log("Expected out:", amountToRecieve.toString());
  //   // Real out
  //   const poolConstant =
  //     vaultHookAccountInfo.amount * vaultWSOLAccountInfo.amount;
  //   console.log("poolConstant", poolConstant.toString());
  //   const newAAmount = vaultHookAccountInfo.amount + amountToSwap;
  //   console.log("newAAmount", newAAmount.toString());
  //   const newBAmount = poolConstant / newAAmount;
  //   console.log("newBAmount", newBAmount.toString());
  //   const amountOut = vaultWSOLAccountInfo.amount - newBAmount;
  //   console.log("Real out:", amountOut.toString());

  //   // let ratio =
  //   // ((real_amount_b_out as f64) - (expected_amount_b_out as f64)) /
  //   // (real_amount_b_out as f64);

  //   const expectedSlippage =
  //     Number(amountOut - amountToRecieve) / Number(amountOut);
  //   console.log("expectedSlippage", expectedSlippage);

  //   const swapIx = await program.methods
  //     .swap(new BN(1000000000), new BN(amountOut.toString()), new BN(50))
  //     .accounts({
  //       config,
  //       authority: wallet.publicKey,
  //       pool,
  //       vault,
  //       mintA: hookMint,
  //       mintB: wrappedSolanaMint,
  //       authorityTokenAccountA: authorityHookAccount,
  //       authorityTokenAccountB: authorityWSOLAccount,
  //       vaultTokenAccountA: vaultHookAccount,
  //       vaultTokenAccountB: vaultWSOLAccount,
  //       tokenProgram: TOKEN_PROGRAM_ID,
  //       tokenProgramA: TOKEN_2022_PROGRAM_ID,
  //       tokenProgramB: TOKEN_PROGRAM_ID,
  //       hookProgramA: transferHook.programId,
  //       hookProgramB: null,
  //       associatedTokenProgram: ASSOCIATED_TOKEN_PROGRAM_ID,
  //       systemProgram: systemKey,
  //     })
  //     .remainingAccounts(remainingAccounts)
  //     .instruction();

  //   // get the table from the cluster
  //   const lookupTableAccount = (
  //     await connection.getAddressLookupTable(globalAddressLookupTableAddress)
  //   ).value;

  //   // had to move the create account ix's off the create pool function to save on stack space
  //   // construct a v0 compatible transaction `Message`
  //   const messageV0 = new TransactionMessage({
  //     payerKey: wallet.publicKey,
  //     recentBlockhash: (await connection.getLatestBlockhash()).blockhash,
  //     instructions: [
  //       computePriceIx,
  //       computeLimitIx,
  //       createVaultWSOLAccountAccountIx,
  //       swapIx,
  //     ], // note this is an array of instructions
  //   }).compileToV0Message([lookupTableAccount]);

  //   // create a v0 transaction from the v0 message
  //   const transactionV0 = new VersionedTransaction(messageV0);

  //   try {
  //     const tx = await provider.sendAndConfirm(transactionV0, [], {
  //       // skipPreflight: true,
  //     });
  //     console.log("Your transaction signature", tx);
  //   } catch (e) {
  //     console.log(e);
  //   }
  // });

  // it("Add liquidity!", async () => {
  //   // Get Transfer Hook Accounts
  //   const remainingAccounts: AccountMeta[] = [];
  //   // first grab mint info
  //   const mintInfo = await getMint(
  //     connection,
  //     hookMint,
  //     "processed",
  //     TOKEN_2022_PROGRAM_ID
  //   );
  //   // console.log("mintInfo", mintInfo);
  //   // then grab xfer hook info
  //   const transferHook = getTransferHook(mintInfo);
  //   const validateStatePubkey = getExtraAccountMetaAddress(
  //     hookMint,
  //     transferHook.programId
  //   );
  //   const validateStateAccount = await connection.getAccountInfo(
  //     validateStatePubkey,
  //     "processed"
  //   );
  //   // grab the extra meta account make sure its valid
  //   if (validateStateAccount == null) {
  //     throw new Error("Invalid validation state account");
  //   }
  //   const validateStateData = getExtraAccountMetas(validateStateAccount);
  //   // create an execute instruction
  //   const executeInstruction = createExecuteInstruction(
  //     transferHook.programId,
  //     authorityHookAccount,
  //     hookMint,
  //     vaultHookAccount,
  //     wallet.publicKey,
  //     validateStatePubkey,
  //     BigInt(20000000000)
  //   );
  //   // resolve the extra accounts from the extra meta account
  //   for (const extraAccountMeta of validateStateData) {
  //     executeInstruction.keys.push(
  //       deEscalateAccountMeta(
  //         await resolveExtraAccountMeta(
  //           connection,
  //           extraAccountMeta,
  //           executeInstruction.keys,
  //           executeInstruction.data,
  //           executeInstruction.programId
  //         ),
  //         executeInstruction.keys
  //       )
  //     );
  //   }

  //   // Add only the extra accounts resolved from the validation state
  //   remainingAccounts.push(...executeInstruction.keys.slice(5));

  //   // Add the transfer hook program ID and the validation state account
  //   remainingAccounts.push({
  //     pubkey: transferHook.programId,
  //     isSigner: false,
  //     isWritable: false,
  //   });
  //   remainingAccounts.push({
  //     pubkey: validateStatePubkey,
  //     isSigner: false,
  //     isWritable: false,
  //   });

  //   const vaultHookAccountInfo = await getAccount(
  //     connection,
  //     vaultHookAccount,
  //     "processed",
  //     TOKEN_2022_PROGRAM_ID
  //   );
  //   // console.log("vaultHookAccountInfo", vaultHookAccountInfo);

  //   const vaultWSOLAccountInfo = await getAccount(
  //     connection,
  //     vaultWSOLAccount,
  //     "processed",
  //     TOKEN_PROGRAM_ID
  //   );
  //   // console.log("vaultWSOLAccountInfo", vaultWSOLAccountInfo);

  //   console.log("--------------------");
  //   console.log("vaultHookAccount", vaultHookAccount.toString());
  //   console.log("vaultWSOLAccount", vaultWSOLAccount.toString());
  //   console.log("authorityWSOLAccount", authorityWSOLAccount.toString());
  //   console.log("authorityHookAccount", authorityHookAccount.toString());
  //   console.log(
  //     "authorityLiquidityAccount",
  //     authorityLiquidityAccount.toString()
  //   );

  //   // calculate the amount out
  //   const amountToSwap = BigInt(1000000000);
  //   const poolRatio = vaultHookAccountInfo.amount / vaultWSOLAccountInfo.amount;
  //   const amountToRecieve = amountToSwap / poolRatio;

  //   const addLiquidityIx = await program.methods
  //     .addLiquidity(
  //       new BN(1000000000),
  //       new BN(amountToRecieve.toString()),
  //       new BN(50)
  //     )
  //     .accounts({
  //       config,
  //       authority: wallet.publicKey,
  //       pool,
  //       vault,
  //       mintA: hookMint,
  //       mintB: wrappedSolanaMint,
  //       authorityTokenAccountA: authorityHookAccount,
  //       authorityTokenAccountB: authorityWSOLAccount,
  //       vaultTokenAccountA: vaultHookAccount,
  //       vaultTokenAccountB: vaultWSOLAccount,
  //       liquidityToken,
  //       authorityLiquidityTokenAccount: authorityLiquidityAccount,
  //       tokenProgram: TOKEN_PROGRAM_ID,
  //       tokenProgramA: TOKEN_2022_PROGRAM_ID,
  //       tokenProgramB: TOKEN_PROGRAM_ID,
  //       hookProgramA: transferHook.programId,
  //       hookProgramB: null,
  //       associatedTokenProgram: ASSOCIATED_TOKEN_PROGRAM_ID,
  //       systemProgram: systemKey,
  //     })
  //     .remainingAccounts(remainingAccounts)
  //     .instruction();

  //   // get the table from the cluster
  //   const lookupTableAccount = (
  //     await connection.getAddressLookupTable(globalAddressLookupTableAddress)
  //   ).value;

  //   // had to move the create account ix's off the create pool function to save on stack space
  //   // construct a v0 compatible transaction `Message`
  //   const messageV0 = new TransactionMessage({
  //     payerKey: wallet.publicKey,
  //     recentBlockhash: (await connection.getLatestBlockhash()).blockhash,
  //     instructions: [computePriceIx, computeLimitIx, addLiquidityIx], // note this is an array of instructions
  //   }).compileToV0Message([lookupTableAccount]);

  //   // create a v0 transaction from the v0 message
  //   const transactionV0 = new VersionedTransaction(messageV0);

  //   try {
  //     const tx = await provider.sendAndConfirm(transactionV0, [], {
  //       // skipPreflight: true,
  //     });
  //     console.log("Your transaction signature", tx);
  //   } catch (e) {
  //     console.log(e);
  //   }
  // });

  // it("Remove Liquidity!", async () => {
  //   // Get Transfer Hook Accounts
  //   const remainingAccounts: AccountMeta[] = [];
  //   // first grab mint info
  //   const mintInfo = await getMint(
  //     connection,
  //     hookMint,
  //     "processed",
  //     TOKEN_2022_PROGRAM_ID
  //   );
  //   // console.log("mintInfo", mintInfo);
  //   // then grab xfer hook info
  //   const transferHook = getTransferHook(mintInfo);
  //   const validateStatePubkey = getExtraAccountMetaAddress(
  //     hookMint,
  //     transferHook.programId
  //   );
  //   const validateStateAccount = await connection.getAccountInfo(
  //     validateStatePubkey,
  //     "processed"
  //   );
  //   // grab the extra meta account make sure its valid
  //   if (validateStateAccount == null) {
  //     throw new Error("Invalid validation state account");
  //   }
  //   const validateStateData = getExtraAccountMetas(validateStateAccount);
  //   // create an execute instruction
  //   const executeInstruction = createExecuteInstruction(
  //     transferHook.programId,
  //     authorityHookAccount,
  //     hookMint,
  //     vaultHookAccount,
  //     wallet.publicKey,
  //     validateStatePubkey,
  //     BigInt(20000000000)
  //   );
  //   // resolve the extra accounts from the extra meta account
  //   for (const extraAccountMeta of validateStateData) {
  //     executeInstruction.keys.push(
  //       deEscalateAccountMeta(
  //         await resolveExtraAccountMeta(
  //           connection,
  //           extraAccountMeta,
  //           executeInstruction.keys,
  //           executeInstruction.data,
  //           executeInstruction.programId
  //         ),
  //         executeInstruction.keys
  //       )
  //     );
  //   }

  //   // Add only the extra accounts resolved from the validation state
  //   remainingAccounts.push(...executeInstruction.keys.slice(5));

  //   // Add the transfer hook program ID and the validation state account
  //   remainingAccounts.push({
  //     pubkey: transferHook.programId,
  //     isSigner: false,
  //     isWritable: false,
  //   });
  //   remainingAccounts.push({
  //     pubkey: validateStatePubkey,
  //     isSigner: false,
  //     isWritable: false,
  //   });

  //   const createAuthoritytHookMintAccountIx =
  //     createAssociatedTokenAccountIdempotentInstruction(
  //       wallet.publicKey,
  //       authorityHookAccount,
  //       wallet.publicKey,
  //       hookMint,
  //       TOKEN_2022_PROGRAM_ID
  //     );

  //   const createAuthoritytWSOLAccountAccountIx =
  //     createAssociatedTokenAccountIdempotentInstruction(
  //       wallet.publicKey,
  //       authorityWSOLAccount,
  //       wallet.publicKey,
  //       wrappedSolanaMint,
  //       TOKEN_PROGRAM_ID
  //     );

  //   console.log("--------------------");
  //   console.log("vaultHookAccount", vaultHookAccount.toString());
  //   console.log("vaultWSOLAccount", vaultWSOLAccount.toString());
  //   console.log("authorityWSOLAccount", authorityWSOLAccount.toString());
  //   console.log("authorityHookAccount", authorityHookAccount.toString());
  //   const poolAccount = await program.account.pool.fetch(pool);
  //   console.log("poolAccount", poolAccount);
  //   const removeLiquiditylIx = await program.methods
  //     // .removeLiquidity(new BN(447212595))
  //     .removeLiquidity(new BN(22360629))
  //     .accounts({
  //       config,
  //       authority: wallet.publicKey,
  //       pool,
  //       vault,
  //       mintA: hookMint,
  //       mintB: wrappedSolanaMint,
  //       authorityTokenAccountA: authorityHookAccount,
  //       authorityTokenAccountB: authorityWSOLAccount,
  //       vaultTokenAccountA: vaultHookAccount,
  //       vaultTokenAccountB: vaultWSOLAccount,
  //       liquidityToken,
  //       authorityLiquidityTokenAccount: authorityLiquidityAccount,
  //       tokenProgram: TOKEN_PROGRAM_ID,
  //       tokenProgramA: TOKEN_2022_PROGRAM_ID,
  //       tokenProgramB: TOKEN_PROGRAM_ID,
  //       hookProgramA: transferHook.programId,
  //       hookProgramB: null,
  //       associatedTokenProgram: ASSOCIATED_TOKEN_PROGRAM_ID,
  //       systemProgram: systemKey,
  //     })
  //     .remainingAccounts(remainingAccounts)
  //     .instruction();

  //   // get the table from the cluster
  //   const lookupTableAccount = (
  //     await connection.getAddressLookupTable(globalAddressLookupTableAddress)
  //   ).value;

  //   // had to move the create account ix's off the create pool function to save on stack space
  //   // construct a v0 compatible transaction `Message`
  //   const messageV0 = new TransactionMessage({
  //     payerKey: wallet.publicKey,
  //     recentBlockhash: (await connection.getLatestBlockhash()).blockhash,
  //     instructions: [
  //       computePriceIx,
  //       computeLimitIx,
  //       createAuthoritytHookMintAccountIx,
  //       createAuthoritytWSOLAccountAccountIx,
  //       removeLiquiditylIx,
  //     ], // note this is an array of instructions
  //   }).compileToV0Message([lookupTableAccount]);

  //   // create a v0 transaction from the v0 message
  //   const transactionV0 = new VersionedTransaction(messageV0);

  //   try {
  //     const tx = await provider.sendAndConfirm(transactionV0, [], {
  //       // skipPreflight: true,
  //     });
  //     console.log("Your transaction signature", tx);
  //   } catch (e) {
  //     console.log(e);
  //   }
  // });

  it("Get Pool Info!", async () => {
    const poolAccount = await program.account.pool.fetch(pool);
    // console.log("poolAccount", poolAccount);
    // Pool fee:
    console.log("Pool fee:", poolAccount.poolFee.toNumber() / 1000, "%");

    // Mint A
    const vaultHookAccountInfo = await getAccount(
      connection,
      vaultHookAccount,
      "processed",
      TOKEN_2022_PROGRAM_ID
    );
    // Mint B
    const vaultWSOLAccountInfo = await getAccount(
      connection,
      vaultWSOLAccount,
      "processed",
      TOKEN_PROGRAM_ID
    );

    console.log("Liquidity Mint A", vaultHookAccountInfo.amount.toString());
    console.log("Liquidity Mint B", vaultWSOLAccountInfo.amount.toString());
  });
});
