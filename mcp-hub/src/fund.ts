import algosdk from "algosdk";
import { USDC_ASSET, NETWORK_NAME, type Config } from "./config.js";
import { FUND_ALGO_MICRO, type Wallet } from "./wallet.js";

/**
 * One-approval onboarding: create, opt in and fund an agent wallet in a single
 * atomic group.
 *
 *   0  operator → agent   ALGO            (signed by the operator)
 *   1  agent opts in to USDC              (signed here, by the agent)
 *   2  operator → agent   USDC            (signed by the operator)
 *
 * All three land or none do, which is the whole point: the ordering trap
 * disappears, because USDC can never arrive before the opt-in that makes it
 * receivable. Only the key holder can sign an ASA opt-in, so transaction 1
 * has to be signed by the agent — and the group id covers all three, so the
 * group must be built before anyone signs anything.
 *
 * Fees are pooled onto transaction 0: Algorand checks the sum across a group,
 * not each transaction, so the operator pays for all three and the agent
 * needs no spendable ALGO at all.
 */
export interface FundGroup {
  network: string;
  networkName: string;
  operator: string;
  agent: string;
  algoMicro: number;
  usdcAtomic: bigint;
  assetId: number;
  /** Unsigned transactions, in group order, with the group id assigned. */
  txns: algosdk.Transaction[];
  /** Index of the transaction the agent signed (the opt-in). */
  agentIndex: number;
  groupId: string;
  /** base64 msgpack of each unsigned transaction, for a signer that takes a group. */
  unsigned: string[];
  /** The agent's signed opt-in, base64 msgpack of a SignedTxn. */
  agentSigned: string;
  /** Rounds the group is valid for; a pre-signed opt-in expires with it. */
  validRounds: { first: number; last: number };
}

export async function buildFundGroup(opts: {
  config: Config;
  wallet: Wallet;
  mnemonic: string;
  network: string;
  operator: string;
  algoMicro?: number;
  usdcAtomic: bigint;
}): Promise<FundGroup> {
  const { config, wallet, mnemonic, network, operator } = opts;
  const assetId = USDC_ASSET[network];
  if (!assetId) throw new Error(`Unknown network ${network}`);
  if (!isAddress(operator)) throw new Error(`${operator} is not an Algorand address`);
  if (operator === wallet.address) throw new Error("The operator and the agent cannot be the same account: the point is that a person funds the agent.");
  const algoMicro = opts.algoMicro ?? FUND_ALGO_MICRO;
  if (opts.usdcAtomic <= 0n) throw new Error("Ask for some USDC: a group that funds no USDC is two transactions you do not need.");

  const algod = new algosdk.Algodv2("", config.algod[network]);
  let params: algosdk.SuggestedParams;
  try {
    params = await algod.getTransactionParams().do();
  } catch (e) {
    throw new Error(`could not reach algod at ${config.algod[network]} to build the group: ${(e as Error).message}`);
  }
  const minFee = Number(params.minFee ?? 1000n);

  // Fee pooling: everything on transaction 0, so the agent spends nothing.
  const pooled = { ...params, flatFee: true, fee: BigInt(minFee * 3) };
  const free = { ...params, flatFee: true, fee: 0n };

  const txns = [
    algosdk.makePaymentTxnWithSuggestedParamsFromObject({
      sender: operator,
      receiver: wallet.address,
      amount: algoMicro,
      suggestedParams: pooled,
    }),
    algosdk.makeAssetTransferTxnWithSuggestedParamsFromObject({
      sender: wallet.address,
      receiver: wallet.address,
      amount: 0,
      assetIndex: assetId,
      suggestedParams: free,
    }),
    algosdk.makeAssetTransferTxnWithSuggestedParamsFromObject({
      sender: operator,
      receiver: wallet.address,
      amount: opts.usdcAtomic,
      assetIndex: assetId,
      suggestedParams: free,
    }),
  ];
  algosdk.assignGroupID(txns);

  const { sk } = algosdk.mnemonicToSecretKey(mnemonic.trim().split(/\s+/).join(" "));
  return {
    network,
    networkName: NETWORK_NAME[network] ?? network,
    operator,
    agent: wallet.address,
    algoMicro,
    usdcAtomic: opts.usdcAtomic,
    assetId,
    txns,
    agentIndex: 1,
    groupId: Buffer.from(txns[0].group ?? new Uint8Array()).toString("base64"),
    unsigned: txns.map((t) => Buffer.from(algosdk.encodeUnsignedTransaction(t)).toString("base64")),
    agentSigned: Buffer.from(txns[1].signTxn(sk)).toString("base64"),
    validRounds: { first: Number(txns[0].firstValid), last: Number(txns[0].lastValid) },
  };
}

export interface SimulationResult {
  ok: boolean;
  round?: number;
  failure?: string;
}

/**
 * Asks algod whether this group would succeed, against real chain state,
 * without submitting it. `allowEmptySignatures` is what lets the operator's
 * two unsigned transactions be evaluated — nothing is spent, nothing is
 * broadcast, and a group that cannot work is refused before a human is asked
 * to approve it.
 */
export async function simulateFundGroup(config: Config, group: FundGroup, fetchImpl: typeof fetch = fetch): Promise<SimulationResult> {
  // A SignedTransaction with no signature: that is what allowEmptySignatures
  // lets algod evaluate, and it is why nothing here needs the operator's key.
  //
  // The request goes as msgpack the SDK encodes for us — algod's canonical
  // JSON wants address fields in base32 and every other byte field in base64,
  // and hand-rolling that is how people lose an afternoon. The response comes
  // back as JSON because it is easier to read and to fake in a test.
  const request = new algosdk.modelsv2.SimulateRequest({
    txnGroups: [
      new algosdk.modelsv2.SimulateRequestTransactionGroup({
        txns: group.txns.map((txn) => new algosdk.SignedTransaction({ txn })),
      }),
    ],
    allowEmptySignatures: true,
  });

  const url = `${config.algod[group.network]}/v2/transactions/simulate`;
  try {
    const res = await fetchImpl(url, {
      method: "POST",
      headers: { "Content-Type": "application/msgpack", Accept: "application/json" },
      body: Buffer.from(algosdk.encodeMsgpack(request)),
    });
    if (!res.ok) return { ok: false, failure: `algod answered ${res.status} ${await res.text().catch(() => "")}`.trim() };

    const body = (await res.json()) as {
      "last-round"?: number;
      "txn-groups"?: { "failure-message"?: string }[];
    };
    const failure = body["txn-groups"]?.[0]?.["failure-message"];
    const round = body["last-round"];
    return failure ? { ok: false, round, failure } : { ok: true, round };
  } catch (e) {
    return { ok: false, failure: `simulation could not run against ${url}: ${(e as Error).message}` };
  }
}

function isAddress(value: string): boolean {
  try {
    algosdk.decodeAddress(value);
    return true;
  } catch {
    return false;
  }
}
