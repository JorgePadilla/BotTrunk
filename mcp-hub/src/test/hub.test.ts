import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { after, before, describe, it } from "node:test";
import algosdk from "algosdk";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { InMemoryTransport } from "@modelcontextprotocol/sdk/inMemory.js";
import { atomicToUsdc, loadConfig, TESTNET, usdcToAtomic, type Config } from "../config.js";
import { inputSchema, liveServices, toolName } from "../catalog.js";
import { createPayingFetch } from "../pay.js";
import { buildServer } from "../server.js";
import { SpendCapError, SpendTracker } from "../spend.js";
import { createWallet, ensureReady, loadWallet, walletFromMnemonic } from "../wallet.js";
import { buildFundGroup, simulateFundGroup } from "../fund.js";
import { catalogBody, startFakeGateway, type FakeGateway } from "./fake_gateway.js";

// Quiet the AVM scheme's console.log so test output stays readable.
console.log = () => {};

function tmpHome(): string {
  return fs.mkdtempSync(path.join(os.tmpdir(), "bottrunk-test-"));
}

function configFor(gw: FakeGateway, home: string, extra: NodeJS.ProcessEnv = {}): Config {
  return loadConfig({
    BOTTRUNK_HOME: home,
    BOTTRUNK_API: gw.url,
    BOTTRUNK_ALGOD_MAINNET: gw.url,
    BOTTRUNK_ALGOD_TESTNET: gw.url,
    ...extra,
  });
}

describe("config", () => {
  it("parses USDC amounts to µUSDC and back", () => {
    assert.equal(usdcToAtomic("0.005"), 5000n);
    assert.equal(usdcToAtomic("1000"), 1_000_000_000n);
    assert.equal(atomicToUsdc(5000n), "0.005");
    assert.equal(atomicToUsdc(1_000_000_000n), "1000");
    assert.throws(() => usdcToAtomic("$5"), /Not a USDC amount/);
  });

  it("defaults to the production gateway and the agreed caps", () => {
    const c = loadConfig({});
    assert.equal(c.apiBase, "https://api.bottrunk.com");
    assert.equal(c.maxPerCallAtomic, usdcToAtomic("10000"));
    assert.equal(c.maxPerDayAtomic, usdcToAtomic("10000"));
  });
});

describe("catalog mapping", () => {
  const services = catalogBody("5000").services as Parameters<typeof liveServices>[0];

  it("exposes only live services as tools", () => {
    assert.deepEqual(liveServices(services).map((s) => s.slug), ["scrape-markdown"]);
  });

  it("derives MCP-safe tool names and a JSON schema from the fields", () => {
    assert.equal(toolName("scrape-markdown"), "bottrunk_scrape_markdown");
    const schema = inputSchema(services[0]) as { required: string[]; properties: Record<string, { type: string }> };
    assert.deepEqual(schema.required, ["url"]);
    assert.equal(schema.properties.selector.type, "string");
  });
});

describe("wallet", () => {
  it("creates a 0600 wallet file once and reloads the same address", () => {
    const home = tmpHome();
    const config = loadConfig({ BOTTRUNK_HOME: home });
    assert.equal(loadWallet(config), null);
    const created = createWallet(config);
    assert.match(created.address, /^[A-Z2-7]{58}$/);
    assert.equal(fs.statSync(config.walletFile).mode & 0o777, 0o600);
    assert.equal(loadWallet(config)?.address, created.address);
    assert.throws(() => createWallet(config), /already exists/);
  });

  it("prefers BOTTRUNK_MNEMONIC over the file", () => {
    const account = algosdk.generateAccount();
    const mnemonic = algosdk.secretKeyToMnemonic(account.sk);
    const wallet = walletFromMnemonic(mnemonic, "env");
    assert.equal(wallet.address, account.addr.toString());
    assert.equal(wallet.signer.address, account.addr.toString());
  });
});

describe("spend caps", () => {
  it("refuses a call above the per-call cap", () => {
    const home = tmpHome();
    const config = loadConfig({ BOTTRUNK_HOME: home, BOTTRUNK_MAX_PER_CALL: "0.004" });
    const spend = new SpendTracker(config);
    assert.throws(() => spend.assertAllowed(5000n), SpendCapError);
    assert.doesNotThrow(() => spend.assertAllowed(4000n));
  });

  it("accumulates a UTC-day total and resets the next day", () => {
    const home = tmpHome();
    const config = loadConfig({ BOTTRUNK_HOME: home, BOTTRUNK_MAX_PER_DAY: "0.01" });
    let now = new Date("2026-09-11T23:59:00Z");
    const spend = new SpendTracker(config, () => now);
    spend.record(5000n);
    spend.record(4000n);
    assert.equal(spend.spentToday(), 9000n);
    assert.throws(() => spend.assertAllowed(2000n), /today's cap/);
    now = new Date("2026-09-12T00:01:00Z");
    assert.equal(spend.spentToday(), 0n);
    assert.doesNotThrow(() => spend.assertAllowed(2000n));
  });
});

describe("paid call through the real x402 client", () => {
  let gw: FakeGateway;
  before(async () => {
    gw = await startFakeGateway("5000");
  });
  after(() => gw.close());

  it("answers a 402 with a signed USDC transfer and records the spend", async () => {
    const home = tmpHome();
    const config = configFor(gw, home);
    const wallet = createWallet(config);
    const spend = new SpendTracker(config);
    const paid = createPayingFetch(config, wallet, spend);

    const result = await paid(`${gw.url}/s/scrape-markdown`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ url: "https://example.com" }),
    });

    assert.equal(result.status, 200);
    assert.equal(JSON.parse(result.body).markdown, "# https://example.com");
    assert.equal(result.payment?.amountUsdc, "0.005");
    assert.equal(result.payment?.transaction, "FAKETXN");
    assert.equal(spend.spentToday(), 5000n);

    // The payload the gateway received is a complete v2 envelope with a signed ASA transfer.
    assert.equal(gw.payments.length, 1);
    const envelope = gw.payments[0].body as {
      x402Version: number;
      accepted: { network: string; amount: string };
      resource: { url: string };
      extensions: Record<string, unknown>;
      payload: { paymentGroup: string[]; paymentIndex: number };
    };
    assert.equal(envelope.x402Version, 2);
    assert.equal(envelope.accepted.network, TESTNET);
    assert.equal(envelope.accepted.amount, "5000");
    assert.ok(envelope.resource.url.endsWith("/s/scrape-markdown"));
    assert.ok("bazaar" in envelope.extensions);
    // The fake gateway now runs the real gateway's sanity checks, so a 200
    // here means the scheme and network are where the Ruby parser looks.
    assert.equal(envelope.payload.paymentGroup.length, 1);
    const signed = algosdk.decodeSignedTransaction(Buffer.from(envelope.payload.paymentGroup[0], "base64"));
    assert.equal(signed.txn.sender.toString(), wallet.address);
    assert.equal(signed.txn.assetTransfer?.amount, 5000n);
    assert.equal(signed.txn.assetTransfer?.assetIndex, 10458941n);
  });

  it("does not sign anything when the price is over the per-call cap", async () => {
    const home = tmpHome();
    const config = configFor(gw, home, { BOTTRUNK_MAX_PER_CALL: "0.001" });
    const wallet = createWallet(config);
    const spend = new SpendTracker(config);
    const paid = createPayingFetch(config, wallet, spend);
    const before = gw.payments.length;
    await assert.rejects(
      paid(`${gw.url}/s/scrape-markdown`, { method: "POST", body: "{}" }),
      /above the per-call cap/,
    );
    assert.equal(gw.payments.length, before);
    assert.equal(spend.spentToday(), 0n);
  });
});

describe("MCP server", () => {
  let gw: FakeGateway;
  before(async () => {
    gw = await startFakeGateway("5000");
  });
  after(() => gw.close());

  async function connect(withWallet: boolean) {
    const home = tmpHome();
    const config = configFor(gw, home);
    const wallet = withWallet ? createWallet(config) : null;
    const spend = new SpendTracker(config);
    const paidFetch = wallet ? createPayingFetch(config, wallet, spend) : null;
    const server = await buildServer({ config, wallet, spend, paidFetch, version: "test" });
    const [clientT, serverT] = InMemoryTransport.createLinkedPair();
    await server.connect(serverT);
    const client = new Client({ name: "test", version: "0" });
    await client.connect(clientT);
    return { client, wallet };
  }

  it("lists the free tools plus one paid tool per live service", async () => {
    const { client } = await connect(true);
    const { tools } = await client.listTools();
    assert.deepEqual(
      tools.map((t) => t.name).sort(),
      ["bottrunk_catalog", "bottrunk_scrape_markdown", "bottrunk_wallet"],
    );
    const paidTool = tools.find((t) => t.name === "bottrunk_scrape_markdown")!;
    assert.match(paidTool.description ?? "", /0\.005 USDC/);
    assert.deepEqual((paidTool.inputSchema as { required: string[] }).required, ["url"]);
  });

  it("catalog and wallet tools work and mention coming-soon services", async () => {
    const { client, wallet } = await connect(true);
    const cat = await client.callTool({ name: "bottrunk_catalog", arguments: {} });
    const catText = (cat.content as { text: string }[])[0].text;
    assert.match(catText, /bottrunk_scrape_markdown/);
    assert.match(catText, /coming_soon \(not callable yet\)/);

    const w = await client.callTool({ name: "bottrunk_wallet", arguments: {} });
    const wText = (w.content as { text: string }[])[0].text;
    assert.match(wText, new RegExp(wallet!.address));
    assert.match(wText, /1\.500000 USDC/);
    assert.match(wText, /10000 USDC per call/);
  });

  it("pays and returns the service output with a receipt line", async () => {
    const { client } = await connect(true);
    const r = await client.callTool({ name: "bottrunk_scrape_markdown", arguments: { url: "https://example.com" } });
    assert.equal(r.isError ?? false, false);
    const text = (r.content as { text: string }[])[0].text;
    assert.match(text, /"markdown": "# https:\/\/example.com"/);
    assert.match(text, /paid 0\.005 USDC · txn FAKETXN/);
  });

  // The wallet tool exists to answer "can I buy yet, and if not what do I do".
  // A funded wallet that gets handed funding instructions is noise; an empty
  // one that gets handed only a balance is a dead end.
  it("tells a funded wallet it is ready, and does not lecture it about funding", async () => {
    const { client } = await connect(true);
    const text = ((await client.callTool({ name: "bottrunk_wallet", arguments: {} })).content as { text: string }[])[0].text;
    assert.match(text, /Ready to buy: 1\.500000 USDC/);
    assert.doesNotMatch(text, /Not ready to buy/);
    assert.doesNotMatch(text, /0\.1 to exist/);
  });

  it("an empty wallet is told the ALGO comes first, and why", async () => {
    gw.account = { amount: 0 };
    const { client, wallet } = await connect(true);
    const text = ((await client.callTool({ name: "bottrunk_wallet", arguments: {} })).content as { text: string }[])[0].text;
    gw.account = { amount: 2_000_000, assets: [{ "asset-id": 10458941, amount: 1_500_000 }] };

    assert.match(text, /Not ready to buy/);
    assert.match(text, new RegExp(wallet!.address));
    assert.match(text, /0\.3 ALGO/);
    assert.match(text, /rejected rather than held/);       // why the order matters
    assert.match(text, /wallet fund --from/);               // the one-approval way out
  });

  it("a wallet that already holds ALGO is only asked for USDC", async () => {
    gw.account = { amount: 2_000_000 };
    const { client } = await connect(true);
    const text = ((await client.callTool({ name: "bottrunk_wallet", arguments: {} })).content as { text: string }[])[0].text;
    gw.account = { amount: 2_000_000, assets: [{ "asset-id": 10458941, amount: 1_500_000 }] };

    assert.match(text, /the ALGO is already there/);
    assert.doesNotMatch(text, /0\.1 to exist/);
  });

  it("explains how to create a wallet instead of failing silently", async () => {
    const { client } = await connect(false);
    const r = await client.callTool({ name: "bottrunk_scrape_markdown", arguments: { url: "https://example.com" } });
    assert.equal(r.isError, true);
    assert.match((r.content as { text: string }[])[0].text, /npx bottrunk-mcp wallet/);
  });
});

describe("spending caps that can be turned off", () => {
  it('accepts "none" and stops enforcing that cap', () => {
    const off = loadConfig({ BOTTRUNK_HOME: tmpHome(), BOTTRUNK_MAX_PER_CALL: "none", BOTTRUNK_MAX_PER_DAY: "none" });

    assert.equal(off.maxPerCallAtomic, null);
    assert.equal(off.maxPerDayAtomic, null);
    assert.doesNotThrow(() => new SpendTracker(off).assertAllowed(usdcToAtomic("999999")));
  });

  it("turning one off leaves the other enforcing", () => {
    const config = loadConfig({ BOTTRUNK_HOME: tmpHome(), BOTTRUNK_MAX_PER_CALL: "none", BOTTRUNK_MAX_PER_DAY: "5" });
    const spend = new SpendTracker(config);

    assert.doesNotThrow(() => spend.assertAllowed(usdcToAtomic("4")), "no per-call cap to break");
    assert.throws(() => spend.assertAllowed(usdcToAtomic("6")), SpendCapError, "the daily cap still holds");
  });

  it("refuses 0 rather than guessing which of the two things it means", () => {
    assert.throws(() => loadConfig({ BOTTRUNK_HOME: tmpHome(), BOTTRUNK_MAX_PER_CALL: "0" }), /refuse every call/);
  });

  it("still defaults to a cap, because the catalog goes to hundreds of dollars a call", () => {
    const config = loadConfig({ BOTTRUNK_HOME: tmpHome() });

    assert.equal(config.maxPerCallAtomic, usdcToAtomic("10000"));
  });
});

describe("readiness", () => {
  const wallet = walletFromMnemonic(algosdk.secretKeyToMnemonic(algosdk.generateAccount().sk), "env");

  function configFor(home: string): Config {
    return loadConfig({ BOTTRUNK_HOME: home, BOTTRUNK_MNEMONIC: "unused" });
  }

  function algodReturning(body: unknown, status = 200): typeof fetch {
    return (async () => new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } })) as unknown as typeof fetch;
  }

  it("tells a person what to send when the wallet is empty, instead of signing into a wall", async () => {
    const home = tmpHome();
    const ready = await ensureReady(configFor(home), wallet, TESTNET, 90_000n, algodReturning({}, 404));

    assert.ok(ready.problem);
    assert.match(ready.problem, /0\.3 ALGO/);
    assert.match(ready.problem, new RegExp(wallet.address));
    assert.equal(ready.optedIn, false);
    fs.rmSync(home, { recursive: true, force: true });
  });

  it("asks for USDC once the wallet is opted in but short", async () => {
    const home = tmpHome();
    const ready = await ensureReady(
      configFor(home),
      wallet,
      TESTNET,
      90_000n,
      algodReturning({ amount: 400_000, assets: [{ "asset-id": 10458941, amount: 1_000 }] }),
    );

    assert.ok(ready.problem);
    assert.match(ready.problem, /0\.001000 USDC and this call costs 0\.090000/);
    assert.equal(ready.optedIn, true);
    fs.rmSync(home, { recursive: true, force: true });
  });

  it("is satisfied when the wallet can cover the call", async () => {
    const home = tmpHome();
    const ready = await ensureReady(
      configFor(home),
      wallet,
      TESTNET,
      90_000n,
      algodReturning({ amount: 400_000, assets: [{ "asset-id": 10458941, amount: 1_500_000 }] }),
    );

    assert.equal(ready.problem, null);
    assert.equal(ready.optedIn, true);
    assert.equal(ready.usdc, 1.5);
    fs.rmSync(home, { recursive: true, force: true });
  });
});

describe("one-approval funding group", () => {
  let gw: FakeGateway;
  const MNEMONIC = algosdk.secretKeyToMnemonic(algosdk.generateAccount().sk);
  const wallet = walletFromMnemonic(MNEMONIC, "env");
  const OPERATOR = "UTWS33TM7IT7NINJSFWS5KVGL73G4ERJMYDKHF7KE4WDXHYO4L7V2PNMRE";

  before(async () => {
    gw = await startFakeGateway();
  });
  after(async () => {
    await gw.close();
  });

  function config(): Config {
    return loadConfig({ BOTTRUNK_HOME: tmpHome(), BOTTRUNK_MNEMONIC: "unused", BOTTRUNK_ALGOD_TESTNET: gw.url });
  }

  async function build(overrides: Partial<Parameters<typeof buildFundGroup>[0]> = {}) {
    return buildFundGroup({
      config: config(),
      wallet,
      mnemonic: MNEMONIC,
      network: TESTNET,
      operator: OPERATOR,
      usdcAtomic: 500_000n,
      ...overrides,
    });
  }

  it("puts the opt-in between the two operator transfers, so USDC can never arrive first", async () => {
    const group = await build();

    assert.equal(group.txns.length, 3);
    assert.equal(group.txns[0].type, "pay");
    assert.equal(group.txns[1].type, "axfer");
    assert.equal(group.txns[2].type, "axfer");
    assert.equal(group.txns[1].sender.toString(), wallet.address, "only the key holder can sign an opt-in");
    assert.equal(group.txns[2].sender.toString(), OPERATOR);
    assert.equal(group.agentIndex, 1);
  });

  it("pools every fee onto the operator, so the agent needs no ALGO of its own", async () => {
    const group = await build();

    assert.equal(group.txns[1].fee, 0n);
    assert.equal(group.txns[2].fee, 0n);
    assert.ok(group.txns[0].fee >= 3000n, "transaction 0 covers the whole group");
  });

  it("assigns one group id across all three, which is why it must be built before anyone signs", async () => {
    const group = await build();
    const ids = group.txns.map((t) => Buffer.from(t.group ?? new Uint8Array()).toString("base64"));

    assert.equal(new Set(ids).size, 1);
    assert.equal(ids[0], group.groupId);
    assert.ok(group.agentSigned.length > 0);
  });

  it("asks the chain whether the group works, and reports the node's own verdict when it does not", async () => {
    const good = await simulateFundGroup(config(), await build());
    assert.equal(good.ok, true);
    assert.equal(good.round, 64948542);

    gw.simulateFails = true;
    const bad = await simulateFundGroup(config(), await build());
    gw.simulateFails = false;
    assert.equal(bad.ok, false);
    assert.match(String(bad.failure), /must optin/);
  });

  it("refuses the shapes that cannot mean anything", async () => {
    await assert.rejects(build({ operator: "not-an-address" }), /not an Algorand address/);
    await assert.rejects(build({ operator: wallet.address }), /cannot be the same account/);
    await assert.rejects(build({ usdcAtomic: 0n }), /funds no USDC/);
  });
});
