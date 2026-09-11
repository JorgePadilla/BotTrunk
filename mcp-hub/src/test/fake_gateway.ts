import http from "node:http";
import { TESTNET } from "../config.js";

/**
 * A stand-in for api.bottrunk.com + an Algorand node, good enough to drive the
 * real x402 client through a 402 → sign → retry → 200 round trip offline.
 */
export interface FakeGateway {
  url: string;
  payments: { header: string; body: unknown }[];
  close(): Promise<void>;
  priceAtomic: string;
}

const GENESIS_HASH = TESTNET.split(":")[1];

export const PAY_TO = "UTWS33TM7IT7NINJSFWS5KVGL73G4ERJMYDKHF7KE4WDXHYO4L7V2PNMRE";

export function catalogBody(priceAtomic: string) {
  return {
    services: [
      {
        slug: "scrape-markdown",
        name: "Scrape URL to Markdown",
        summary: "Any public page as clean, LLM-ready markdown.",
        description: "Any public page as clean, LLM-ready markdown.",
        category: "Data",
        provider: "By BotTrunk",
        endpoint: "REPLACED",
        method: "POST",
        status: "live",
        network: { id: TESTNET, asset: "10458941", name: "Algorand TestNet" },
        price: { amount: priceAtomic, asset: "USDC", decimals: 6 },
        inputs: [
          { name: "url", type: "string", description: "Public http(s) URL to fetch.", example: "https://example.com" },
          { name: "selector", type: "string", description: "Optional CSS selector." },
        ],
        outputs: [{ name: "markdown", type: "string", description: "Body as markdown." }],
      },
      {
        slug: "pdf-extract",
        name: "PDF to JSON",
        summary: "Send a PDF and a schema, get the fields back.",
        description: "Send a PDF URL and a JSON schema.",
        category: "Data",
        provider: "By BotTrunk",
        endpoint: "REPLACED",
        method: "POST",
        status: "coming_soon",
        network: { id: TESTNET, asset: "10458941", name: "Algorand TestNet" },
        price: { amount: "20000", asset: "USDC", decimals: 6 },
        inputs: [{ name: "url", type: "string", description: "PDF URL." }],
        outputs: [{ name: "data", type: "object", description: "Fields." }],
      },
    ],
  };
}

export async function startFakeGateway(priceAtomic = "5000"): Promise<FakeGateway> {
  const payments: FakeGateway["payments"] = [];
  const server = http.createServer(async (req, res) => {
    const url = new URL(req.url ?? "/", "http://x");
    const json = (status: number, body: unknown, headers: Record<string, string> = {}) => {
      res.writeHead(status, { "content-type": "application/json", ...headers });
      res.end(JSON.stringify(body));
    };

    // --- algod ---
    if (url.pathname === "/v2/transactions/params") {
      return json(200, {
        "consensus-version": "future",
        fee: 0,
        "genesis-hash": GENESIS_HASH,
        "genesis-id": "testnet-v1.0",
        "last-round": 1000,
        "min-fee": 1000,
      });
    }
    if (url.pathname.startsWith("/v2/accounts/")) {
      return json(200, { amount: 2_000_000, assets: [{ "asset-id": 10458941, amount: 1_500_000 }] });
    }

    // --- gateway ---
    if (url.pathname === "/api/v1/catalog") {
      const body = catalogBody(priceAtomic);
      for (const s of body.services) s.endpoint = `${base}/s/${s.slug}`;
      return json(200, body);
    }
    if (url.pathname === "/s/scrape-markdown" && req.method === "POST") {
      let raw = "";
      for await (const chunk of req) raw += chunk;
      const input = JSON.parse(raw || "{}") as { url?: string };
      const requirements = {
        scheme: "exact",
        network: TESTNET,
        asset: "10458941",
        amount: priceAtomic,
        payTo: PAY_TO,
        maxTimeoutSeconds: 60,
        extra: { decimals: 6, tag: "x402-global-challenge" },
      };
      const paymentRequired = {
        x402Version: 2,
        error: "Payment required",
        resource: { url: `${base}/s/scrape-markdown`, description: "Scrape", mimeType: "application/json" },
        accepts: [requirements],
        extensions: { bazaar: { info: { input: { type: "http", method: "POST" } } } },
      };
      const header = req.headers["payment-signature"] ?? req.headers["x-payment"];
      if (!header) {
        return json(402, paymentRequired, {
          "payment-required": Buffer.from(JSON.stringify(paymentRequired)).toString("base64"),
        });
      }
      const payload = JSON.parse(Buffer.from(String(header), "base64").toString("utf8"));
      payments.push({ header: String(header), body: payload });

      // The same sanity checks the real gateway runs before it calls the
      // facilitator. Without them this fake accepted any shape at all, so the
      // round-trip test passed for months while production answered every
      // call from this client with "scheme mismatch".
      const scheme = payload?.accepted?.scheme ?? payload?.scheme;
      const network = payload?.accepted?.network ?? payload?.network;
      if (payload?.x402Version !== 2) return json(402, { ...paymentRequired, error: "unsupported x402 version" });
      if (scheme !== requirements.scheme) return json(402, { ...paymentRequired, error: "scheme mismatch" });
      if (network !== requirements.network) return json(402, { ...paymentRequired, error: "network mismatch" });

      if (!input.url) return json(422, { error: "url is required" });
      const receipt = { success: true, transaction: "FAKETXN", network: TESTNET, payer: payload?.payload?.paymentGroup ? "signed" : "unknown" };
      return json(
        200,
        { markdown: `# ${input.url}`, title: "Example", word_count: 2 },
        { "payment-response": Buffer.from(JSON.stringify(receipt)).toString("base64") },
      );
    }
    json(404, { error: "not found" });
  });

  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const addr = server.address() as { port: number };
  const base = `http://127.0.0.1:${addr.port}`;
  return {
    url: base,
    payments,
    priceAtomic,
    close: () => new Promise((resolve) => server.close(() => resolve())),
  };
}
