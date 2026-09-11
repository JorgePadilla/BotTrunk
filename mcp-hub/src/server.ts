import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { CallToolRequestSchema, ListToolsRequestSchema, type Tool } from "@modelcontextprotocol/sdk/types.js";
import { atomicToUsdc, MAINNET, type Config } from "./config.js";
import { fetchCatalog, inputSchema, liveServices, priceLabel, toolDescription, toolName, type CatalogService } from "./catalog.js";
import type { PaidFetch } from "./pay.js";
import { SpendCapError, type SpendTracker } from "./spend.js";
import { balances, ensureReady, FUND_ALGO_MICRO, type Wallet } from "./wallet.js";

export interface HubDeps {
  config: Config;
  wallet: Wallet | null;
  spend: SpendTracker;
  paidFetch: PaidFetch | null;
  fetchImpl?: typeof fetch;
  version: string;
}

const CATALOG_TOOL = "bottrunk_catalog";
const WALLET_TOOL = "bottrunk_wallet";

/**
 * Builds the MCP server: two free tools (catalog, wallet) plus one paid tool
 * per live catalog service. The catalog is fetched once at startup; restart
 * the server to pick up new services.
 */
export async function buildServer(deps: HubDeps): Promise<Server> {
  const fetchImpl = deps.fetchImpl ?? fetch;

  // A blip at the gateway used to kill the process on startup, which silently
  // removed all eleven tools from the MCP host with a bare "fetch failed".
  // Start degraded instead: the free tools still work and bottrunk_catalog
  // says what went wrong and how to get the paid tools back.
  let catalog: CatalogService[] = [];
  let catalogError: string | null = null;
  try {
    catalog = await fetchCatalog(deps.config.apiBase, fetchImpl);
  } catch (e) {
    catalogError = (e as Error).message;
    console.error(`bottrunk-mcp: ${catalogError} — starting without paid tools; restart once it is reachable.`);
  }
  const live = liveServices(catalog);
  const bySlug = new Map(live.map((s) => [toolName(s.slug), s] as const));

  const server = new Server({ name: "bottrunk", version: deps.version }, { capabilities: { tools: {} } });

  server.setRequestHandler(ListToolsRequestSchema, async () => {
    const tools: Tool[] = [
      {
        name: CATALOG_TOOL,
        description:
          "List BotTrunk services (name, price in USDC, inputs, status). Free. Use it to discover what can be bought before calling a paid tool.",
        inputSchema: {
          type: "object",
          properties: {
            query: { type: "string", description: "Optional substring filter on name, summary or category." },
            category: { type: "string", description: "Optional exact category filter: Payments, Data, Verification or Translation." },
          },
          additionalProperties: false,
        },
      },
      {
        name: WALLET_TOOL,
        description:
          "Show this agent's BotTrunk wallet: Algorand address, ALGO/USDC balances, spending caps and what was spent today. Free. Fund the address with USDC on Algorand to enable paid tools.",
        inputSchema: { type: "object", properties: {}, additionalProperties: false },
      },
      ...live.map<Tool>((s) => ({
        name: toolName(s.slug),
        description: toolDescription(s),
        inputSchema: inputSchema(s) as Tool["inputSchema"],
      })),
    ];
    return { tools };
  });

  server.setRequestHandler(CallToolRequestSchema, async (req) => {
    const name = req.params.name;
    const args = (req.params.arguments ?? {}) as Record<string, unknown>;

    if (name === CATALOG_TOOL) {
      if (catalogError) {
        return error(
          `The catalog could not be loaded, so no paid tools are available in this session.\n${catalogError}\n` +
            `Check https://bottrunk.com/ and restart this MCP server once the gateway answers.`,
        );
      }
      return text(
        renderCatalog(catalog, typeof args.query === "string" ? args.query : undefined, typeof args.category === "string" ? args.category : undefined),
      );
    }
    if (name === WALLET_TOOL) return text(await renderWallet(deps, fetchImpl));

    const service = bySlug.get(name);
    if (!service) return error(`Unknown tool ${name}`);
    if (!deps.wallet || !deps.paidFetch) {
      return error(
        `No wallet configured. Run \`npx bottrunk-mcp wallet\` once to create one (or set BOTTRUNK_MNEMONIC), fund it with USDC on Algorand, then restart this MCP server.`,
      );
    }

    // Preflight. Signing a payment the wallet cannot make fails on-chain with
    // a message nobody can act on; this fails here with one that says exactly
    // what is missing — and opts in to USDC on the way past if the ALGO has
    // landed, which is the step that used to have to happen by hand between
    // two transfers, in the right order.
    const ready = await ensureReady(
      deps.config,
      deps.wallet,
      service.network?.id ?? MAINNET,
      BigInt(service.price.amount),
      fetchImpl,
    );
    if (ready.problem) return error(ready.problem);

    const result = await callPaid(service, args, deps.paidFetch);
    if (ready.optedInNow) {
      result.content.push({ type: "text" as const, text: `\n(This wallet opted in to USDC on the way — txn ${ready.optedInNow}.)` });
    }
    return result;
  });

  return server;
}

async function callPaid(service: CatalogService, args: Record<string, unknown>, paidFetch: PaidFetch) {
  try {
    const result = await paidFetch(service.endpoint, {
      method: "POST",
      headers: { "Content-Type": "application/json", Accept: "application/json" },
      body: JSON.stringify(args),
    });
    const receipt = result.payment
      ? `\n\n— paid ${result.payment.amountUsdc} USDC${result.payment.transaction ? ` · txn ${result.payment.transaction}` : ""}`
      : "";
    if (result.status === 402) {
      return error(`Payment was not accepted by ${service.name}: ${summarize402(result.body)}`);
    }
    const body = prettyJson(result.body);
    if (result.status >= 400) return error(`${service.name} answered ${result.status}: ${body}${receipt}`);
    return text(`${body}${receipt}`);
  } catch (e) {
    const err = e as Error;
    if (err instanceof SpendCapError || /Payment creation aborted/.test(err.message)) {
      return error(err.message.replace(/^Payment creation aborted: /, ""));
    }
    return error(`Paid call failed: ${err.message}`);
  }
}

function renderCatalog(catalog: CatalogService[], query?: string, category?: string): string {
  const q = query?.toLowerCase();
  const c = category?.toLowerCase();
  const rows = catalog
    .filter((s) => !c || s.category.toLowerCase() === c)
    .filter((s) => !q || [s.name, s.summary, s.category, s.slug, s.description].some((t) => t.toLowerCase().includes(q)));
  if (!rows.length) return `No services match ${[query && `"${query}"`, category && `category ${category}`].filter(Boolean).join(" in ")}.`;
  return rows
    .map((s) => {
      const status = (s.status ?? "live") === "live" ? "live" : `${s.status} (not callable yet)`;
      const inputs = s.inputs.map((f) => `${f.name}: ${f.type}`).join(", ");
      return `${toolName(s.slug)} — ${s.name} [${s.category}] · ${priceLabel(s)} · ${status}\n  ${s.summary}\n  inputs: ${inputs}`;
    })
    .join("\n\n");
}

async function renderWallet(deps: HubDeps, fetchImpl: typeof fetch): Promise<string> {
  const { config, wallet, spend } = deps;
  const caps = `Caps: ${atomicToUsdc(config.maxPerCallAtomic)} USDC per call, ${atomicToUsdc(config.maxPerDayAtomic)} USDC per day. Spent today: ${atomicToUsdc(spend.spentToday())} USDC.`;
  if (!wallet) {
    return `No wallet configured. Run \`npx bottrunk-mcp wallet\` to create one, or set BOTTRUNK_MNEMONIC.\n${caps}`;
  }
  const lines = [`Address: ${wallet.address} (from ${wallet.source === "env" ? "BOTTRUNK_MNEMONIC" : config.walletFile})`];

  // Asking whether the wallet is ready is also what makes it ready: if the
  // ALGO has landed, this opts in to USDC before reporting.
  let optedInNow: string | undefined;
  try {
    const ready = await ensureReady(config, wallet, MAINNET, 0n, fetchImpl);
    optedInNow = ready.optedInNow;
  } catch {
    // Balances below will report whatever the network is willing to say.
  }

  try {
    for (const b of await balances(config, wallet.address, fetchImpl)) {
      lines.push(`${b.network}: ${b.algo} ALGO · ${b.usdc === null ? "USDC not opted in" : `${b.usdc} USDC`}`);
    }
  } catch (e) {
    lines.push(`Balances unavailable: ${(e as Error).message}`);
  }
  lines.push(caps);
  if (optedInNow) lines.push(`Just opted in to USDC — txn ${optedInNow}. USDC sent to this address will arrive from now on.`);
  lines.push(
    `To fund, two sends in this order — an agent cannot fund itself, and USDC sent before the opt-in does not arrive:\n` +
      `  1. ${(FUND_ALGO_MICRO / 1e6).toFixed(1)} ALGO to ${wallet.address} (0.1 to exist, 0.1 to hold USDC, the rest for fees)\n` +
      `  2. the USDC you want this agent to be able to spend, to the same address\n` +
      `The USDC opt-in in between happens by itself the next time a tool here is called.`,
  );
  return lines.join("\n");
}

function summarize402(body: string): string {
  try {
    const parsed = JSON.parse(body) as { error?: string };
    return parsed.error ?? body.slice(0, 200);
  } catch {
    return body.slice(0, 200);
  }
}

function prettyJson(body: string): string {
  try {
    return JSON.stringify(JSON.parse(body), null, 2);
  } catch {
    return body;
  }
}

function text(t: string) {
  return { content: [{ type: "text" as const, text: t }] };
}

function error(t: string) {
  return { content: [{ type: "text" as const, text: t }], isError: true };
}
