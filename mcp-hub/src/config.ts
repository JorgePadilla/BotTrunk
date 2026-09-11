import os from "node:os";
import path from "node:path";

/**
 * Everything the hub reads from the environment, in one place.
 *
 * Amounts are USDC as decimal strings ("1000" = 1000 USDC) and converted to
 * atomic µUSDC once here so the rest of the code only sees integers.
 */
export interface Config {
  /** Base URL of the BotTrunk gateway (catalog + paid endpoints). */
  apiBase: string;
  /** Where the generated wallet lives when no mnemonic is given. */
  walletFile: string;
  /** 25-word Algorand mnemonic, if the user brings their own wallet. */
  mnemonic?: string;
  /** Hard ceiling for a single call, in µUSDC. */
  maxPerCallAtomic: bigint;
  /** Hard ceiling for one UTC day, in µUSDC. */
  maxPerDayAtomic: bigint;
  /** Where the daily spend ledger is kept. */
  spendFile: string;
  /** Algod endpoints per CAIP-2 network id. */
  algod: Record<string, string>;
}

export const MAINNET = "algorand:wGHE2Pwdvd7S12BL5FaOP20EGYesN73ktiC1qzkkit8=";
export const TESTNET = "algorand:SGO1GKSzyE7IEPItTxCByw9x8FmnrCDexi9/cOUJOiI=";

export const USDC_ASSET: Record<string, number> = {
  [MAINNET]: 31566704,
  [TESTNET]: 10458941,
};

export const NETWORK_NAME: Record<string, string> = {
  [MAINNET]: "mainnet",
  [TESTNET]: "testnet",
};

const DEFAULTS = {
  apiBase: "https://api.bottrunk.com",
  maxPerCall: "1000",
  maxPerDay: "10000",
};

/** Parses a decimal USDC amount ("0.05", "1000") into µUSDC. Throws on garbage. */
export function usdcToAtomic(value: string): bigint {
  const m = /^(\d+)(?:\.(\d{1,6}))?$/.exec(value.trim());
  if (!m) throw new Error(`Not a USDC amount: "${value}" (use e.g. 0.05 or 1000)`);
  const whole = BigInt(m[1]);
  const frac = BigInt((m[2] ?? "").padEnd(6, "0"));
  return whole * 1_000_000n + frac;
}

/** Formats µUSDC for humans: 5000n → "0.005". */
export function atomicToUsdc(atomic: bigint): string {
  const whole = atomic / 1_000_000n;
  const frac = (atomic % 1_000_000n).toString().padStart(6, "0").replace(/0+$/, "");
  return frac ? `${whole}.${frac}` : whole.toString();
}

export function loadConfig(env: NodeJS.ProcessEnv = process.env): Config {
  const home = path.join(env.BOTTRUNK_HOME ?? path.join(os.homedir(), ".bottrunk"));
  return {
    apiBase: (env.BOTTRUNK_API ?? DEFAULTS.apiBase).replace(/\/+$/, ""),
    walletFile: env.BOTTRUNK_WALLET_FILE ?? path.join(home, "wallet.json"),
    mnemonic: env.BOTTRUNK_MNEMONIC?.trim() || undefined,
    maxPerCallAtomic: usdcToAtomic(env.BOTTRUNK_MAX_PER_CALL ?? DEFAULTS.maxPerCall),
    maxPerDayAtomic: usdcToAtomic(env.BOTTRUNK_MAX_PER_DAY ?? DEFAULTS.maxPerDay),
    spendFile: path.join(home, "spend.json"),
    algod: {
      [MAINNET]: env.BOTTRUNK_ALGOD_MAINNET ?? "https://mainnet-api.algonode.cloud",
      [TESTNET]: env.BOTTRUNK_ALGOD_TESTNET ?? "https://testnet-api.algonode.cloud",
    },
  };
}
