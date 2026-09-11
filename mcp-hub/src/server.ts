import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { CallToolRequestSchema, ListToolsRequestSchema, type Tool } from "@modelcontextprotocol/sdk/types.js";
import { atomicToUsdc, type Config } from "./config.js";
import { fetchCatalog, inputSchema, liveServices, priceLabel, toolDescription, toolName, type CatalogService } from "./catalog.js";
import type { PaidFetch } from "./pay.js";
import { SpendCapError, type SpendTracker } from "./spend.js";
import { balances, type Wallet } from "./wallet.js";

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
  const catalog = await fetchCatalog(deps.config.apiBase, fetchImpl);
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
          properties: { query: { type: "string", description: "Optional substring filter on name, summary or category." } },
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

    if (name === CATALOG_TOOL) return text(renderCatalog(catalog, typeof args.query === "string" ? args.query : undefined));
    if (name === WALLET_TOOL) return text(await renderWallet(deps, fetchImpl));

    const service = bySlug.get(name);
    if (!service) return error(`Unknown tool ${name}`);
    if (!deps.wallet || !deps.paidFetch) {
      return error(
        `No wallet configured. Run \`npx bottrunk-mcp wallet\` once to create one (or set BOTTRUNK_MNEMONIC), fund it with USDC on Algorand, then restart this MCP server.`,
      );
    }
    return callPaid(service, args, deps.paidFetch);
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

function renderCatalog(catalog: CatalogService[], query?: string): string {
  const q = query?.toLowerCase();
  const rows = catalog.filter((s) => !q || [s.name, s.summary, s.category, s.slug, s.description].some((t) => t.toLowerCase().includes(q)));
  if (!rows.length) return `No services match "${query}".`;
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
  try {
    for (const b of await balances(config, wallet.address, fetchImpl)) {
      lines.push(`${b.network}: ${b.algo} ALGO · ${b.usdc === null ? "USDC not opted in" : `${b.usdc} USDC`}`);
    }
  } catch (e) {
    lines.push(`Balances unavailable: ${(e as Error).message}`);
  }
  lines.push(caps);
  lines.push(
    "To fund: send USDC (Algorand network) to the address above. The wallet must hold ~0.2 ALGO and be opted in to USDC (`npx bottrunk-mcp wallet optin`) before the first payment.",
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
