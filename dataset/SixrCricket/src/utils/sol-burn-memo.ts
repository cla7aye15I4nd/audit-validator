import bs58 from 'bs58';
import {
  PublicKey,
  ParsedInstruction,
  PartiallyDecodedInstruction,
  ParsedTransactionWithMeta,
} from '@solana/web3.js';

export type BurnFound = { tonRecipient: string; amountRaw9: bigint; sig: string };

const TOKEN_LEGACY = new PublicKey('TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA');
const TOKEN_2022   = new PublicKey('TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnB35h2Jf2Q1i');
const MEMO_V1      = new PublicKey('Memo1UhkJRfHyvLMcVucJwxXeuD728EqVDDwQDxFMNo');
const MEMO_V2      = new PublicKey('MemoSq4gqABAXKb96qnH8TysNcWxMyWCqXgDLGmfcHr');

function b58ToUtf8(b58: string): string {
  try { return Buffer.from(bs58.decode(b58)).toString('utf8'); }
  catch { return ''; }
}

function isFriendlyTon(addr: string) {
  // basic pattern check for TON friendly addresses (starts with E/Q etc.)
  return /^[EU]Q[0-9A-Za-z\-_]{46}$/.test(addr);
}

function parseTonFromMemo(memo: string): string | null {
  const s = memo.trim();
  const m = s.startsWith('TON:') ? s.slice(4).trim() : s;
  return isFriendlyTon(m) ? m : null;
}

/**
 * Try extracting burn amount / decimals / memo TON from a single instruction
 */
function tryPickFromInstr(i: ParsedInstruction | PartiallyDecodedInstruction | any): {
  amountRaw?: bigint;
  decimals?: number;
  memoTon?: string;
} {
  let amountRaw: bigint | undefined;
  let decimals: number | undefined;
  let memoTon: string | undefined;

  const pid = (typeof i?.programId?.toBase58 === 'function')
    ? i.programId.toBase58()
    : (i?.programId?.toString?.() || '');

  // parsed memo as plain string (some RPCs return string)
  if ((pid === MEMO_V1.toBase58() || pid === MEMO_V2.toBase58()) && typeof i?.parsed === 'string') {
    const maybe = parseTonFromMemo(i.parsed as string);
    if (maybe) memoTon = maybe;
  }

  // parsed memo as { type:'memo', info:{ memo } }
  const parsedType = i?.parsed?.type;
  const parsedInfo = i?.parsed?.info;
  if ((pid === MEMO_V1.toBase58() || pid === MEMO_V2.toBase58()) && parsedType === 'memo') {
    const memoStr = parsedInfo?.memo || '';
    const maybe = parseTonFromMemo(memoStr);
    if (maybe) memoTon = maybe;
  }

  // partially-decoded with base58 data field
  if ((pid === MEMO_V1.toBase58() || pid === MEMO_V2.toBase58()) && typeof i?.data === 'string') {
    const memo = b58ToUtf8(i.data);
    const maybe = parseTonFromMemo(memo);
    if (maybe) memoTon = maybe;
  }

  // SPL token program burn / burnChecked detection (legacy or 2022)
  const isTokenProg = (pid === TOKEN_LEGACY.toBase58() || pid === TOKEN_2022.toBase58());
  if (isTokenProg && (parsedType === 'burn' || parsedType === 'burnChecked')) {
    const rawStr = parsedInfo?.amount ?? parsedInfo?.tokenAmount?.amount ?? '0';
    const dec    = parsedInfo?.tokenAmount?.decimals ?? parsedInfo?.decimals ?? 9;
    amountRaw = BigInt(rawStr);
    decimals  = Number(dec);
  }

  return { amountRaw, decimals, memoTon };
}

/**
 * Exported: scan parsed transaction (outer + inner instructions + token balance delta)
 * Returns normalized 9-decimals bigint (amountRaw9) and TON memo recipient if found
 */
export function pickBurnAndMemo(tx: ParsedTransactionWithMeta | null, mintStr: string): BurnFound | null {
  if (!tx) return null;

  const sig = tx.transaction?.signatures?.[0] || '';
  const msg = tx.transaction?.message;
  const meta = tx.meta;
  const ix: (ParsedInstruction | PartiallyDecodedInstruction)[] = msg?.instructions || [];
  const inner = meta?.innerInstructions || [];

  let tonRecipient: string | undefined;
  let amountRaw: bigint | undefined;
  let decimals: number | undefined;

  // scan outer instructions
  for (const i of ix) {
    const { amountRaw: raw, decimals: dec, memoTon } = tryPickFromInstr(i);
    if (memoTon && !tonRecipient) tonRecipient = memoTon;
    if (raw !== undefined) amountRaw = raw;
    if (dec !== undefined) decimals = dec;
  }

  // scan inner instructions
  for (const group of inner) {
    for (const i of group.instructions || []) {
      const { amountRaw: raw, decimals: dec, memoTon } = tryPickFromInstr(i);
      if (memoTon && !tonRecipient) tonRecipient = memoTon;
      if (raw !== undefined) amountRaw = raw;
      if (dec !== undefined) decimals = dec;
    }
  }

  // fallback: compute delta from pre/post token balances (if the mint is touched)
  if ((amountRaw === undefined || amountRaw === 0n) && meta?.preTokenBalances?.length && meta?.postTokenBalances?.length) {
    for (const pre of meta.preTokenBalances) {
      const post = meta.postTokenBalances.find((p: any) => p.mint === pre.mint && p.accountIndex === pre.accountIndex);
      if (!post) continue;
      if (pre.mint !== mintStr) continue;
      const a0 = BigInt(pre.uiTokenAmount?.amount || '0');
      const a1 = BigInt(post.uiTokenAmount?.amount || '0');
      if (a0 > a1) {
        amountRaw = a0 - a1;
        decimals = Number(pre.uiTokenAmount?.decimals ?? 9);
        break;
      }
    }
  }

  if (!tonRecipient || !amountRaw || amountRaw <= 0n) return null;

  // normalize to 9-decimals
  let raw9 = amountRaw;
  const d = (decimals ?? 9);
  if (d > 9) raw9 = raw9 / (10n ** BigInt(d - 9));
  if (d < 9) raw9 = raw9 * (10n ** BigInt(9 - d));

  return { tonRecipient, amountRaw9: raw9, sig };
}
