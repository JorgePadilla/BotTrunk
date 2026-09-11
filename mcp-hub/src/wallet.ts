import fs from "node:fs";
import path from "node:path";
import algosdk from "algosdk";
import { toClientAvmSigner, type ClientAvmSigner } from "@x402-avm/avm";
import { NETWORK_NAME, USDC_ASSET, type Config } from "./config.js";

/**
 * The agent's own Algorand account.
 *
 * Two sources, in order: BOTTRUNK_MNEMONIC (people who already run an agent
 * wallet), otherwise a JSON file the CLI generates on first run. The file is
 * written 0600 and holds the 25-word mnemonic, so treat ~/.bottrunk like ~/.ssh.
 * The key never leaves this process: it signs the USDC transfer locally and
 * only the signed transaction travels to the gateway.
 */
export interface Wallet {
  address: string;
  signer: ClientAvmSigner;
  /** Where the key came from, for the `wallet` CLI output. */
  source: "env" | "file";
}

interface WalletFile {
  version: 1;
  address: string;
  mnemonic: string;
  createdAt: string;
}

export function walletFromMnemonic(mnemonic: string, source: Wallet["source"]): Wallet {
  const account = algosdk.mnemonicToSecretKey(mnemonic.trim().split(/\s+/).join(" "));
  const signer = toClientAvmSigner(Buffer.from(account.sk).toString("base64"));
  return { address: account.addr.toString(), signer, source };
}

/** Loads the wallet, or returns null when neither source exists. Never creates one. */
export function loadWallet(config: Config): Wallet | null {
  if (config.mnemonic) return walletFromMnemonic(config.mnemonic, "env");
  if (!fs.existsSync(config.walletFile)) return null;
  const parsed = JSON.parse(fs.readFileSync(config.walletFile, "utf8")) as WalletFile;
  if (parsed.version !== 1 || typeof parsed.mnemonic !== "string") {
    throw new Error(`Unrecognised wallet file at ${config.walletFile}`);
  }
  return walletFromMnemonic(parsed.mnemonic, "file");
}

/** Creates a brand-new account and writes it to the wallet file (refuses to overwrite). */
export function createWallet(config: Config): Wallet {
  if (fs.existsSync(config.walletFile)) {
    throw new Error(`A wallet already exists at ${config.walletFile}; move it away first if you really want a new one.`);
  }
  const account = algosdk.generateAccount();
  const file: WalletFile = {
    version: 1,
    address: account.addr.toString(),
    mnemonic: algosdk.secretKeyToMnemonic(account.sk),
    createdAt: new Date().toISOString(),
  };
  fs.mkdirSync(path.dirname(config.walletFile), { recursive: true, mode: 0o700 });
  fs.writeFileSync(config.walletFile, JSON.stringify(file, null, 2) + "\n", { mode: 0o600 });
  return walletFromMnemonic(file.mnemonic, "file");
}

export interface Balances {
  network: string;
  algo: string;
  usdc: string | null; // null = not opted in
  optedIn: boolean;
}

/** Reads ALGO + USDC balances from algod for every configured network. */
export async function balances(config: Config, address: string, fetchImpl: typeof fetch = fetch): Promise<Balances[]> {
  const out: Balances[] = [];
  for (const [network, url] of Object.entries(config.algod)) {
    let res: Response;
    try {
      res = await fetchImpl(`${url}/v2/accounts/${address}`);
    } catch (e) {
      // Naming the host matters: the usual cause is an offline laptop or a
      // proxy, and "fetch failed" alone sends people looking at their wallet.
      throw new Error(`could not reach algod at ${url}: ${(e as Error).message}`);
    }
    if (res.status === 404) {
      out.push({ network: NETWORK_NAME[network] ?? network, algo: "0", usdc: null, optedIn: false });
      continue;
    }
    if (!res.ok) throw new Error(`algod ${url} answered ${res.status}`);
    const acct = (await res.json()) as { amount: number; assets?: { "asset-id": number; amount: number }[] };
    const holding = acct.assets?.find((a) => a["asset-id"] === USDC_ASSET[network]);
    out.push({
      network: NETWORK_NAME[network] ?? network,
      algo: (acct.amount / 1e6).toFixed(6),
      usdc: holding ? (holding.amount / 1e6).toFixed(6) : null,
      optedIn: Boolean(holding),
    });
  }
  return out;
}

/**
 * Opts the wallet in to USDC on one network (a 0-amount transfer to itself).
 * Needs ~0.2 ALGO in the account: 0.1 min-balance bump + fee.
 */
export async function optInToUsdc(config: Config, wallet: Wallet, network: string, mnemonic: string): Promise<string> {
  const assetId = USDC_ASSET[network];
  if (!assetId) throw new Error(`Unknown network ${network}`);
  const algod = new algosdk.Algodv2("", config.algod[network]);
  const params = await algod.getTransactionParams().do();
  const txn = algosdk.makeAssetTransferTxnWithSuggestedParamsFromObject({
    sender: wallet.address,
    receiver: wallet.address,
    amount: 0,
    assetIndex: assetId,
    suggestedParams: params,
  });
  const { sk } = algosdk.mnemonicToSecretKey(mnemonic);
  const { txid } = await algod.sendRawTransaction(txn.signTxn(sk)).do();
  await algosdk.waitForConfirmation(algod, txid, 4);
  return txid;
}

/**
 * Minimum ALGO to fund a fresh agent with, in microAlgos.
 *
 * The protocol floor is 0.2: 0.1 for the account to exist plus 0.1 for the
 * USDC holding. Funding exactly that leaves the account unable to pay a single
 * fee, so the first client that signs a plain transfer instead of a fee-payer
 * group drops below minimum balance and fails. The spare 0.1 is what prevents
 * that, and it is why the CLI asks for 0.3.
 */
export const FUND_ALGO_MICRO = 300_000;
const OPT_IN_FLOOR_MICRO = 201_000; // 0.1 base + 0.1 holding + one fee

export interface Readiness {
  network: string;
  networkName: string;
  address: string;
  algo: number;
  usdc: number | null;
  optedIn: boolean;
  /** Set when this call performed the opt-in itself. */
  optedInNow?: string;
  /** null when the wallet can pay; otherwise what a person has to do. */
  problem: string | null;
}

/**
 * Checks the wallet can actually pay, and opts in to USDC by itself when the
 * ALGO has arrived — the step that used to sit between two manual sends and
 * had to happen in the right order or the USDC bounced silently.
 *
 * Called before every paid tool, so an agent never signs into a wall, and by
 * bottrunk_wallet so asking "am I ready?" is also what makes it ready.
 */
export async function ensureReady(
  config: Config,
  wallet: Wallet,
  network: string,
  needAtomic: bigint,
  fetchImpl: typeof fetch = fetch,
): Promise<Readiness> {
  const name = NETWORK_NAME[network] ?? network;
  const url = config.algod[network];
  const base: Readiness = { network, networkName: name, address: wallet.address, algo: 0, usdc: null, optedIn: false, problem: null };
  if (!url) return { ...base, problem: `No algod endpoint configured for ${name}.` };

  const account = await readAccount(url, wallet.address, fetchImpl);
  const algo = account.microAlgos;
  const assetId = USDC_ASSET[network];
  const holding = account.assets.find((a) => a.assetId === assetId);
  const need = Number(needAtomic) / 1e6;

  if (!holding && algo < OPT_IN_FLOOR_MICRO) {
    return {
      ...base,
      algo: algo / 1e6,
      problem:
        `This wallet holds ${(algo / 1e6).toFixed(6)} ALGO and needs at least 0.3 to hold USDC at all ` +
        `(0.1 to exist, 0.1 per asset, the rest for fees). Send 0.3 ALGO on ${name} to ${wallet.address}, ` +
        `then call this again — the opt-in happens by itself.`,
    };
  }

  let optedInNow: string | undefined;
  if (!holding) {
    try {
      optedInNow = await optInToUsdc(config, wallet, network, readMnemonic(config));
    } catch (e) {
      return { ...base, algo: algo / 1e6, problem: `The ALGO is here but the USDC opt-in failed: ${(e as Error).message}` };
    }
  }

  const usdc = holding ? holding.amount / 1e6 : 0;
  if (usdc < need) {
    return {
      ...base,
      algo: algo / 1e6,
      usdc,
      optedIn: true,
      optedInNow,
      problem:
        `This wallet holds ${usdc.toFixed(6)} USDC and this call costs ${need.toFixed(6)}. ` +
        `Send USDC on ${name} to ${wallet.address}.` +
        (optedInNow ? ` (It just opted in to USDC — txn ${optedInNow} — so the transfer will arrive now.)` : ""),
    };
  }

  return { ...base, algo: algo / 1e6, usdc, optedIn: true, optedInNow, problem: null };
}

async function readAccount(url: string, address: string, fetchImpl: typeof fetch) {
  let res: Response;
  try {
    res = await fetchImpl(`${url}/v2/accounts/${address}`);
  } catch (e) {
    throw new Error(`could not reach algod at ${url}: ${(e as Error).message}`);
  }
  if (res.status === 404) return { microAlgos: 0, assets: [] as { assetId: number; amount: number }[] };
  if (!res.ok) throw new Error(`algod ${url} answered ${res.status}`);
  const acct = (await res.json()) as { amount: number; assets?: { "asset-id": number; amount: number }[] };
  return { microAlgos: acct.amount, assets: (acct.assets ?? []).map((a) => ({ assetId: a["asset-id"], amount: a.amount })) };
}

/** Mnemonic backing a wallet, for opt-in. Only the CLI calls this. */
export function readMnemonic(config: Config): string {
  if (config.mnemonic) return config.mnemonic;
  const parsed = JSON.parse(fs.readFileSync(config.walletFile, "utf8")) as WalletFile;
  return parsed.mnemonic;
}
