#!/usr/bin/env node
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { createRequire } from "node:module";
import { atomicToUsdc, loadConfig, MAINNET, TESTNET, usdcToAtomic } from "./config.js";
import { createPayingFetch } from "./pay.js";
import { buildServer } from "./server.js";
import { SpendTracker } from "./spend.js";
import { balances, createWallet, FUND_ALGO_MICRO, loadWallet, optInToUsdc, readMnemonic } from "./wallet.js";
import { buildFundGroup, simulateFundGroup } from "./fund.js";
import fs from "node:fs";
import path from "node:path";

const { version } = createRequire(import.meta.url)("../package.json") as { version: string };

// stdio is the MCP wire; anything a dependency prints to stdout would corrupt
// it (the AVM scheme logs with console.log). Route all console output to stderr.
console.log = console.info = console.debug = (...args: unknown[]) => console.error(...args);

const USAGE = `bottrunk-mcp ${version} — pay-per-call BotTrunk services from Claude, Cursor or any MCP agent

Usage:
  bottrunk-mcp                 start the MCP server on stdio (what your MCP config runs)
  bottrunk-mcp wallet          create the wallet if missing, then show address + balances
  bottrunk-mcp wallet optin    opt the wallet in to USDC by itself (mainnet by default)
  bottrunk-mcp wallet fund     build ONE atomic group that funds, opts in and tops up the agent
                               --from <operator address>  (required: who pays)
                               --usdc <amount>            (required: what the agent may spend)
                               --algo <amount>            (default 0.3)
  bottrunk-mcp catalog         print the services the server would expose

Environment:
  BOTTRUNK_MNEMONIC        use an existing 25-word Algorand mnemonic instead of the wallet file
  BOTTRUNK_WALLET_FILE     where the generated wallet lives (default ~/.bottrunk/wallet.json)
  BOTTRUNK_MAX_PER_CALL    per-call cap in USDC (default 1000)
  BOTTRUNK_MAX_PER_DAY     per-day cap in USDC (default 10000)
  BOTTRUNK_API             gateway base URL (default https://api.bottrunk.com)
  ALGORAND_NETWORK         mainnet | testnet, for \`wallet optin\` and \`wallet fund\` (default mainnet)
  BOTTRUNK_OPERATOR        default --from address for \`wallet fund\`
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
    if (sub === "fund") {
      const network = (process.env.ALGORAND_NETWORK ?? "mainnet") === "testnet" ? TESTNET : MAINNET;
      const operator = flag(argv, "--from") ?? process.env.BOTTRUNK_OPERATOR;
      const usdc = flag(argv, "--usdc");
      if (!operator || !usdc) {
        process.stderr.write("Usage: bottrunk-mcp wallet fund --from <operator address> --usdc <amount> [--algo 0.3]\n");
        process.exitCode = 2;
        return;
      }
      const group = await buildFundGroup({
        config,
        wallet,
        mnemonic: readMnemonic(config),
        network,
        operator,
        algoMicro: flag(argv, "--algo") ? Math.round(Number(flag(argv, "--algo")) * 1e6) : undefined,
        usdcAtomic: usdcToAtomic(usdc),
      });

      // Free, against real chain state, submitting nothing: a group that
      // cannot work is refused here rather than in someone's wallet.
      const sim = await simulateFundGroup(config, group);
      process.stdout.write(
        `One approval funds this agent on ${group.networkName}:\n\n` +
          `  0  ${(group.algoMicro / 1e6).toFixed(6)} ALGO   ${short(group.operator)} → ${short(group.agent)}   you sign\n` +
          `  1  opt in to USDC ${group.assetId}              ${short(group.agent)}            signed already\n` +
          `  2  ${atomicToUsdc(group.usdcAtomic)} USDC   ${short(group.operator)} → ${short(group.agent)}   you sign\n\n` +
          `  group ${group.groupId}\n` +
          `  fees pooled onto transaction 0, so the agent needs no ALGO of its own\n` +
          `  valid for rounds ${group.validRounds.first}–${group.validRounds.last} (roughly 45 minutes — after that, run this again)\n\n` +
          (sim.ok
            ? `Simulated against ${group.networkName} at round ${sim.round}: the group succeeds. Nothing was submitted.\n\n`
            : `Simulation says this group would FAIL: ${sim.failure}\nNothing was written. Fix the above and run it again.\n`),
      );
      if (!sim.ok) {
        process.exitCode = 1;
        return;
      }

      const out = path.join(path.dirname(config.walletFile), "fund-group.json");
      fs.writeFileSync(
        out,
        JSON.stringify(
          {
            network: group.network,
            groupId: group.groupId,
            operator: group.operator,
            agent: group.agent,
            validRounds: group.validRounds,
            // ARC-0001 shape: the operator's wallet signs the entries without
            // a signature and leaves the agent's opt-in alone.
            txns: group.unsigned.map((txn, i) =>
              i === group.agentIndex ? { txn, stxn: group.agentSigned, signers: [] } : { txn, signers: [group.operator] },
            ),
          },
          null,
          2,
        ) + "\n",
        { mode: 0o600 },
      );
      process.stdout.write(
        `Group written to ${out} (ARC-0001 \`signTxns\` shape).\n` +
          `Sign transactions 0 and 2 with the operator wallet and submit all three together.\n` +
          `The opt-in is already signed and must be submitted unchanged, or the group id no longer matches.\n\n` +
          `No signer that takes a group? The two-send path still works and needs nothing extra:\n` +
          `  1. ${(group.algoMicro / 1e6).toFixed(1)} ALGO to ${group.agent}\n` +
          `  2. ${atomicToUsdc(group.usdcAtomic)} USDC to the same address — the opt-in happens by itself in between.\n`,
      );
      return;
    }

    if (sub === "optin") {
      const network = (process.env.ALGORAND_NETWORK ?? "mainnet") === "testnet" ? TESTNET : MAINNET;
      const txid = await optInToUsdc(config, wallet, network, readMnemonic(config));
      process.stdout.write(`Opted in to USDC on ${process.env.ALGORAND_NETWORK ?? "mainnet"} · txn ${txid}\n`);
    }
    process.stdout.write(`Address: ${wallet.address}\n`);
    try {
      for (const b of await balances(config, wallet.address)) {
        process.stdout.write(`${b.network.padEnd(8)} ${b.algo} ALGO · ${b.usdc === null ? "USDC not opted in" : `${b.usdc} USDC`}\n`);
      }
    } catch (e) {
      // The address above is the useful part; balances are a nicety, and a
      // network problem should not hide the thing you came here to copy.
      process.stdout.write(`Balances unavailable: ${(e as Error).message}\n`);
    }
    process.stdout.write(
      `\nCaps: ${atomicToUsdc(config.maxPerCallAtomic)} USDC/call · ${atomicToUsdc(config.maxPerDayAtomic)} USDC/day\n\n` +
        `Fund it — two sends, in this order. An agent cannot fund itself, and USDC sent\n` +
        `before the opt-in does not arrive, it fails.\n\n` +
        `  1. ${(FUND_ALGO_MICRO / 1e6).toFixed(1)} ALGO to ${wallet.address}\n` +
        `     (0.1 for the account to exist, 0.1 to hold USDC, the rest for fees)\n` +
        `  2. the USDC you want this agent to be able to spend, to the same address\n\n` +
        `The USDC opt-in in between happens by itself the next time a tool runs —\n` +
        `\`npx bottrunk-mcp wallet optin\` still works if you would rather do it now.\n\n` +
        `Already have a funded Algorand account? Skip all of this: put its 25 words in\n` +
        `BOTTRUNK_MNEMONIC and the agent uses that account directly.\n`,
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

function flag(argv: string[], name: string): string | undefined {
  const i = argv.indexOf(name);
  return i >= 0 ? argv[i + 1] : undefined;
}

function short(address: string): string {
  return `${address.slice(0, 6)}…${address.slice(-4)}`;
}

main(process.argv.slice(2)).catch((e: Error) => {
  console.error(`bottrunk-mcp: ${e.message}`);
  process.exit(1);
});
