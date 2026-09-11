import { x402Client } from "@x402-avm/core/client";
import { decodePaymentResponseHeader } from "@x402-avm/core/http";
import { ExactAvmScheme } from "@x402-avm/avm/exact/client";
import { wrapFetchWithPayment } from "@x402-avm/fetch";
import { atomicToUsdc, type Config } from "./config.js";
import { SpendTracker } from "./spend.js";
import type { Wallet } from "./wallet.js";

/** What a paid call hands back to the tool layer. */
export interface PaidResult {
  status: number;
  contentType: string;
  body: string;
  payment?: {
    amountUsdc: string;
    network: string;
    transaction?: string;
    payer?: string;
  };
}

/**
 * A `fetch` that answers 402s with a signed USDC transfer from the wallet.
 *
 * The x402 client only knows the network once it has the 402 in hand, and the
 * AVM scheme's default algod is TestNet, so a scheme is registered per network
 * with its own algod URL instead of the `algorand:*` wildcard.
 */
export function createPayingFetch(config: Config, wallet: Wallet, spend: SpendTracker, fetchImpl: typeof fetch = fetch) {
  const client = new x402Client();
  for (const [network, algodUrl] of Object.entries(config.algod)) {
    client.register(network as `${string}:${string}`, new ExactAvmScheme(wallet.signer, { algodUrl }));
  }

  // Set by the hook below while the wrapper is answering a 402; read after the retry.
  const quote = new Map<"last", { amount: bigint; network: string }>();
  client.onBeforePaymentCreation(async ({ selectedRequirements }) => {
    const amount = BigInt(selectedRequirements.amount);
    try {
      spend.assertAllowed(amount);
    } catch (e) {
      return { abort: true as const, reason: (e as Error).message };
    }
    quote.set("last", { amount, network: selectedRequirements.network });
  });

  const paying = wrapFetchWithPayment(fetchImpl, client);

  return async function paidFetch(url: string, init: RequestInit): Promise<PaidResult> {
    quote.delete("last");
    const res = await paying(url, init);
    const body = await res.text();
    const result: PaidResult = {
      status: res.status,
      contentType: res.headers.get("content-type") ?? "",
      body,
    };
    const header = res.headers.get("payment-response") ?? res.headers.get("x-payment-response");
    const paid = quote.get("last");
    if (header && paid) {
      spend.record(paid.amount);
      result.payment = { amountUsdc: atomicToUsdc(paid.amount), network: paid.network };
      try {
        const decoded = decodePaymentResponseHeader(header) as { transaction?: string; payer?: string };
        result.payment.transaction = decoded.transaction;
        result.payment.payer = decoded.payer;
      } catch {
        /* receipt was unreadable; the payment still happened */
      }
    }
    return result;
  };
}

export type PaidFetch = ReturnType<typeof createPayingFetch>;
