#!/usr/bin/env node
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { createRequire } from "node:module";
import { atomicToUsdc, loadConfig, MAINNET, TESTNET } from "./config.js";
import { createPayingFetch } from "./pay.js";
import { buildServer } from "./server.js";
import { SpendTracker } from "./spend.js";
import { balances, createWallet, loadWallet, optInToUsdc, readMnemonic } from "./wallet.js";

const { version } = createRequire(import.meta.url)("../package.json") as { version: string };

// stdio is the MCP wire; anything a dependency prints to stdout would corrupt
// it (the AVM scheme logs with console.log). Route all console output to stderr.
console.log = console.info = console.debug = (...args: unknown[]) => console.error(...args);

const USAGE = `bottrunk-mcp ${version} — pay-per-call BotTrunk services from Claude, Cursor or any MCP agent

Usage:
  bottrunk-mcp                 start the MCP server on stdio (what your MCP config runs)
  bottrunk-mcp wallet          create the wallet if missing, then show address + balances
  bottrunk-mcp wallet optin    opt the wallet in to USDC (needs ~0.2 ALGO; mainnet by default)
  bottrunk-mcp catalog         print the services the server would expose

Environment:
  BOTTRUNK_MNEMONIC        use an existing 25-word Algorand mnemonic instead of the wallet file
  BOTTRUNK_WALLET_FILE     where the generated wallet lives (default ~/.bottrunk/wallet.json)
  BOTTRUNK_MAX_PER_CALL    per-call cap in USDC (default 1000)
  BOTTRUNK_MAX_PER_DAY     per-day cap in USDC (default 10000)
  BOTTRUNK_API             gateway base URL (default https://api.bottrunk.com)
  ALGORAND_NETWORK         mainnet | testnet, for \`wallet optin\` (default mainnet)
`;

async function main(argv: string[]): Promise<void> {
  const [cmd, sub] = argv;
  const config = loadConfig();

  if (cmd === "-h" || cmd === "--help" || cmd === "help") {
    process.stdout.write(USAGE);
    return;
  }
  if (cmd === "-v" || cmd === "--version") {
    process.stdout.write(version + "\n");
    return;
  }

  if (cmd === "wallet") {
    let wallet = loadWallet(config);
    if (!wallet) {
      wallet = createWallet(config);
      process.stdout.write(`Created a new wallet at ${config.walletFile} (mode 0600). Back that file up: it is the only copy of the key.\n\n`);
    }
    if (sub === "optin") {
      const network = (process.env.ALGORAND_NETWORK ?? "mainnet") === "testnet" ? TESTNET : MAINNET;
      const txid = await optInToUsdc(config, wallet, network, readMnemonic(config));
      process.stdout.write(`Opted in to USDC on ${process.env.ALGORAND_NETWORK ?? "mainnet"} · txn ${txid}\n`);
    }
    process.stdout.write(`Address: ${wallet.address}\n`);
    for (const b of await balances(config, wallet.address)) {
      process.stdout.write(`${b.network.padEnd(8)} ${b.algo} ALGO · ${b.usdc === null ? "USDC not opted in" : `${b.usdc} USDC`}\n`);
    }
    process.stdout.write(
      `\nCaps: ${atomicToUsdc(config.maxPerCallAtomic)} USDC/call · ${atomicToUsdc(config.maxPerDayAtomic)} USDC/day\n` +
        `Fund it: send USDC on the Algorand network to the address above (and ~0.2 ALGO once, for the USDC opt-in).\n`,
    );
    return;
  }

  if (cmd === "catalog") {
    const { fetchCatalog, liveServices, priceLabel, toolName } = await import("./catalog.js");
    const catalog = await fetchCatalog(config.apiBase);
    const live = new Set(liveServices(catalog).map((s) => s.slug));
    for (const s of catalog) {
      process.stdout.write(`${live.has(s.slug) ? "live " : "soon "} ${toolName(s.slug).padEnd(32)} ${priceLabel(s).padEnd(12)} ${s.summary}\n`);
    }
    return;
  }

  if (cmd && cmd !== "serve") {
    process.stderr.write(`Unknown command "${cmd}"\n\n${USAGE}`);
    process.exitCode = 2;
    return;
  }

  const wallet = loadWallet(config);
  const spend = new SpendTracker(config);
  const paidFetch = wallet ? createPayingFetch(config, wallet, spend) : null;
  if (!wallet) console.error("bottrunk-mcp: no wallet yet — paid tools will explain how to create one. Run `npx bottrunk-mcp wallet`.");
  const server = await buildServer({ config, wallet, spend, paidFetch, version });
  await server.connect(new StdioServerTransport());
  console.error(`bottrunk-mcp ${version} ready · wallet ${wallet?.address ?? "none"} · api ${config.apiBase}`);
}

main(process.argv.slice(2)).catch((e: Error) => {
  console.error(`bottrunk-mcp: ${e.message}`);
  process.exit(1);
});
