import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { CallToolRequestSchema, ListToolsRequestSchema, type Tool } from "@modelcontextprotocol/sdk/types.js";
import { atomicToUsdc, capLabel, MAINNET, type Config } from "./config.js";
import { fetchCatalog, inputSchema, liveServices, priceLabel, toolDescription, toolName, type CatalogService } from "./catalog.js";
import type { PaidFetch } from "./pay.js";
import { SpendCapError, type SpendTracker } from "./spend.js";
import { balances, ensureReady, FUND_ALGO_MICRO, type Balances, type Wallet } from "./wallet.js";

export interface HubDeps {
  config: Config;
  wallet: Wallet | null;
  spend: SpendTracker;
  paidFetch: PaidFetch | null;
  fetchImpl?: typeof fetch;
  version: string;
  /** How long a fetched catalog is trusted. Tests pass 0 to refetch every time. */
  catalogTtlMs?: number;
  /** How long to wait for the gateway before giving up on a refresh. */
  catalogTimeoutMs?: number;
}

const CATALOG_TOOL = "bottrunk_catalog";
const WALLET_TOOL = "bottrunk_wallet";

/** New services appear this long after they are listed, without a restart. */
const CATALOG_TTL_MS = 5 * 60_000;
/** After a failed refresh, wait this long before trying the gateway again. */
const CATALOG_RETRY_MS = 30_000;
/** A refresh runs inside a tools/list, so it gives up rather than hang the host. */
const CATALOG_TIMEOUT_MS = 8_000;

/**
 * Builds the MCP server: two free tools (catalog, wallet) plus one paid tool
 * per live catalog service.
 *
 * The catalog is fetched at startup and refreshed when it goes stale, because
 * an MCP server started in the morning was still offering the morning's tools
 * at night. Hosts that honour `notifications/tools/list_changed` pick up new
 * services in place; the rest see them on their next `tools/list`.
 */
export async function buildServer(deps: HubDeps): Promise<Server> {
  const fetchImpl = deps.fetchImpl ?? fetch;
  const ttl = deps.catalogTtlMs ?? CATALOG_TTL_MS;
  const timeoutMs = deps.catalogTimeoutMs ?? CATALOG_TIMEOUT_MS;

  let catalog: CatalogService[] = [];
  let catalogError: string | null = null;
  let live: CatalogService[] = [];
  let bySlug = new Map<string, CatalogService>();
  let nextFetchAt = 0;
  let started = false;

  const server = new Server({ name: "bottrunk", version: deps.version }, { capabilities: { tools: { listChanged: true } } });

  // A blip at the gateway used to kill the process on startup, which silently
  // removed all eleven tools from the MCP host with a bare "fetch failed".
  // Start degraded instead: the free tools still work and bottrunk_catalog
  // says what went wrong. The same rule applies to every later refresh — a
  // failed one keeps the tools we already have rather than deleting them.
  const refresh = async (force = false): Promise<void> => {
    if (!force && Date.now() < nextFetchAt) return;
    try {
      const fresh = await fetchCatalog(deps.config.apiBase, fetchImpl, timeoutMs);
      const before = [...bySlug.keys()].sort().join(",");
      catalog = fresh;
      live = liveServices(fresh);
      bySlug = new Map(live.map((s) => [toolName(s.slug), s] as const));
      catalogError = null;
      nextFetchAt = Date.now() + ttl;
      // Only when the set of tools changed: deposit prices move with the
      // exchange rate every minute, and that is not news to the host.
      if (started && [...bySlug.keys()].sort().join(",") !== before) {
        await server.sendToolListChanged().catch(() => {});
      }
    } catch (e) {
      const message = (e as Error).message;
      nextFetchAt = Date.now() + CATALOG_RETRY_MS;
      if (catalog.length === 0) {
        catalogError = message;
        console.error(`bottrunk-mcp: ${message} — starting without paid tools; it retries by itself.`);
      } else {
        console.error(`bottrunk-mcp: catalog refresh failed (${message}) — keeping the ${live.length} tools from the last good fetch.`);
      }
    }
  };

  await refresh(true);
  started = true;

  server.setRequestHandler(ListToolsRequestSchema, async () => {
    await refresh();
    const categories = [...new Set(catalog.map((s) => s.category))].sort();
    const tools: Tool[] = [
      {
        name: CATALOG_TOOL,
        description:
          "List BotTrunk services (name, price in USDC, inputs, status). Free. Use it to discover what can be bought before calling a paid tool.",
        inputSchema: {
          type: "object",
          properties: {
            query: { type: "string", description: "Optional substring filter on name, summary or category." },
            category: {
              type: "string",
              description: `Optional exact category filter${categories.length ? `: ${categories.join(", ")}` : ""}.`,
            },
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
      await refresh();
      if (catalogError) {
        return error(
          `The catalog could not be loaded, so no paid tools are available in this session.\n${catalogError}\n` +
            `Check https://bottrunk.com/ — this server retries by itself, so call bottrunk_catalog again in a minute.`,
        );
      }
      return text(
        renderCatalog(catalog, typeof args.query === "string" ? args.query : undefined, typeof args.category === "string" ? args.category : undefined),
      );
    }
    if (name === WALLET_TOOL) return text(await renderWallet(deps, fetchImpl));

    // An agent that read a fresh catalog can ask for a tool this session has
    // not heard of yet. Check with the gateway before telling it no.
    if (!bySlug.has(name) && name.startsWith("bottrunk_")) await refresh(true);
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
  const caps = `Caps: ${capLabel(config.maxPerCallAtomic)} per call, ${capLabel(config.maxPerDayAtomic)} per day. Spent today: ${atomicToUsdc(spend.spentToday())} USDC.`;
  if (!wallet) {
    return (
      `No wallet. This server normally creates one at startup; it could not, so the paid tools are off.\n` +
      `Run \`npx bottrunk-mcp wallet\` from a shell that can write to ${config.walletFile}, or set BOTTRUNK_MNEMONIC.\n${caps}`
    );
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

  let funding: Balances[] = [];
  try {
    funding = await balances(config, wallet.address, fetchImpl);
    for (const b of funding) {
      lines.push(`${b.network}: ${b.algo} ALGO · ${b.usdc === null ? "USDC not opted in" : `${b.usdc} USDC`}`);
    }
  } catch (e) {
    lines.push(`Balances unavailable: ${(e as Error).message}`);
  }
  lines.push(caps);
  if (optedInNow) lines.push(`Just opted in to USDC — txn ${optedInNow}. USDC sent to this address will arrive from now on.`);

  // The point of this tool is not the balance, it is what to do next. A wallet
  // that can already pay should not be handed a wall of funding instructions;
  // one that cannot should be handed something its human can act on without
  // reading any documentation.
  lines.push("", nextStep(wallet.address, funding));
  return lines.join("\n");
}

/** What the human behind this agent has to do, if anything. */
function nextStep(address: string, funding: Balances[]): string {
  const fundCommand =
    `One approval instead of two sends:\n` +
    `  npx bottrunk-mcp wallet fund --from <your Algorand address> --usdc <amount>\n` +
    `builds a single atomic group — fund, opt in, deliver USDC — and checks it against the live chain before anyone signs.`;

  if (funding.length === 0) {
    return `Could not read any balance, so this cannot say whether the wallet is ready.\n${fundCommand}`;
  }

  // Ready anywhere counts as ready: a wallet funded on TestNet is mid-test, not
  // broken, and telling it to go find ALGO would be wrong twice over.
  const ready = funding.find((b) => b.optedIn && Number(b.usdc ?? "0") > 0);
  if (ready) {
    return `Ready to buy: ${ready.usdc} USDC on ${ready.network}. Call a paid tool and it settles from this wallet.`;
  }

  // Otherwise advise on the network the money is meant to be on.
  const target = funding.find((b) => b.network.toLowerCase() === "mainnet") ?? funding[0];
  const needsAlgo = Number(target.algo) * 1e6 < FUND_ALGO_MICRO;
  const steps: string[] = [`Not ready to buy yet. Send to ${address} on Algorand ${target.network}:`];
  if (needsAlgo) {
    steps.push(`  1. ${(FUND_ALGO_MICRO / 1e6).toFixed(1)} ALGO — 0.1 to exist, 0.1 to hold USDC, the rest for fees`);
    steps.push(`  2. the USDC you want this agent to be able to spend`);
    steps.push(`In that order. Only the key holder can opt in to USDC, so an agent cannot fund itself, and USDC that arrives before the opt-in is rejected rather than held.`);
  } else {
    steps.push(`  the USDC you want this agent to be able to spend (the ALGO is already there)`);
  }
  return [ ...steps, "", fundCommand ].join("\n");
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
