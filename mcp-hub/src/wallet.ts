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
    const res = await fetchImpl(`${url}/v2/accounts/${address}`);
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
  const algod = new algosdk.Algodv2("", config.algod[network], "");
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

/** Mnemonic backing a wallet, for opt-in. Only the CLI calls this. */
export function readMnemonic(config: Config): string {
  if (config.mnemonic) return config.mnemonic;
  const parsed = JSON.parse(fs.readFileSync(config.walletFile, "utf8")) as WalletFile;
  return parsed.mnemonic;
}
