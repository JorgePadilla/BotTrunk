# Funding an agent to buy on BotTrunk

Your agent pays for each call with its own USDC on Algorand. Before it can do
that, someone has to give it a wallet and put money in it — **an agent cannot
fund itself**, and there is no on-ramp inside the loop.

This takes about five minutes. The whole of it is: create a wallet, send it
ALGO, send it USDC.

---

## Before you start

You need ALGO and USDC **on the Algorand network**, in an exchange account or
a wallet of your own (see *Where to get them* below for the ones that can
send it), holding:

| | Amount | What it is for |
|---|---|---|
| ALGO | **0.3** (about $0.10) | Algorand charges rent, not per-call fees. See *Why ALGO* below. |
| USDC | whatever you want the agent to spend | Most data services cost $0.02–$0.09 per call. |

Two things worth checking before you send anything:

- **USDC on Algorand, not on Ethereum or Solana.** The same name, different
  chains, and a transfer to the wrong one does not arrive. On Algorand, USDC
  is asset ID **31566704**.
- **MainNet.** BotTrunk serves MainNet only. There is no public TestNet
  endpoint to rehearse against.

### Where to get them

Checked Oct 2, 2026 against each venue's own withdrawal tables. Most exchanges
list ALGO, but few send **USDC on Algorand**; a USDC withdrawal on any other
network does not arrive.

| Where | ALGO out | USDC on Algorand out | Minimum / fee | Notes |
|---|---|---|---|---|
| Kraken | yes | yes | 1 ALGO, fee 0.1 · 1 USDC, fee 0.1 | Not New York. The cheapest published path in the US. |
| Coinbase | yes | yes | 0.1 ALGO · 1 USDC; fee shown at send time | Buying USDC with local money: US, BR, CL, EC, PE, UY. |
| Binance | yes | yes | 10 ALGO, fee 0.008 · 5 USDC, fee 1 | Not for US residents. Binance.US has paused Algorand. |
| Pera Fund (in the Pera wallet) | yes | yes | set by the card provider | Buy USDC on Algorand directly by card (ACH in the US), no exchange account. |
| OKX, Bitso, KuCoin, Gate, HTX | yes | **no** | — | Only the ALGO half. Swap ALGO for USDC in Pera (about 1.3% in fees) or Tinyman/Folks Router (0.1–0.3%). |

For small amounts outside the US, withdrawing ALGO from Binance and swapping
part of it to USDC in Pera costs less than Binance's flat 1 USDC withdrawal fee.

---

## 1. Create the agent's wallet

```sh
npx bottrunk-mcp wallet
```

This generates a brand-new Algorand account and writes it to
`~/.bottrunk/wallet.json` with mode 0600. It prints the address and exactly
what to send.

**That file is the only copy of the key.** Treat `~/.bottrunk` like `~/.ssh`:
back it up, don't commit it, don't paste it anywhere. BotTrunk never sees it —
the key signs a transfer on your machine and only the signed transaction
travels to the gateway.

*Already run an Algorand account?* Skip this whole document: put its 25-word
mnemonic in `BOTTRUNK_MNEMONIC` and the agent uses that account directly, with
no file, no ALGO to send and no opt-in to do.

## 2. Send 0.3 ALGO

Send **0.3 ALGO** to the address it printed. Wait a few seconds for it to
land — Algorand blocks are under four seconds.

`npx bottrunk-mcp wallet` also prints this as a payment link,
`algorand://<address>?amount=300000` (ARC-90). Opened on a phone with Pera, or
scanned as a QR code, it is the transfer already filled in.

## 3. Opt in to USDC

An Algorand account has to opt in to an asset before it can hold it. This
happens **by itself** the first time your agent calls a paid tool, so you can
usually skip this step.

Do it explicitly if you want to send USDC from a wallet app right away, because
Defly and Pera will refuse to compose the transfer until the opt-in exists:

```sh
npx bottrunk-mcp wallet optin
```

## 4. Send the USDC

Send the USDC to the same address. Done.

The wallet command prints a link for 5 USDC,
`algorand://<address>?amount=5000000&asset=31566704`; change the amount in the
wallet before you approve it. It works only after the opt-in in step 3.

## 5. Check it

```sh
npx bottrunk-mcp wallet
```

You want a line like:

```
mainnet  0.299000 ALGO · 5.000000 USDC
```

`USDC not opted in` means step 3 has not happened yet. **`USDC 0.000000` is
different and is fine** — it means the account can receive USDC and none has
arrived.

---

## One approval instead of three steps

If you would rather do it in a single signature:

```sh
npx bottrunk-mcp wallet fund --from <your address> --usdc 5
```

This builds one **atomic group** of three transactions — you fund the agent,
the agent opts itself in, you deliver the USDC — and checks the whole thing
against real chain state with Algorand's `simulate` before anyone is asked to
sign. Nothing is submitted by that check and nothing is spent.

All three land or none do, so there is no window in which the wallet has ALGO
but cannot yet receive USDC. You sign transactions 0 and 2 with your own
wallet; the agent's opt-in is signed already and must be submitted unchanged,
or the group id no longer matches. The group expires in about 45 minutes —
if you take longer, run it again, it costs nothing.

You need a signer that accepts a transaction group for this. If yours does
not, the three steps above work exactly as well.

---

## Why ALGO at all, when the calls are priced in USDC?

Three rules of the chain, none of them BotTrunk's choice:

1. **An account must hold at least 0.1 ALGO to exist.** Algorand charges a
   refundable minimum balance rather than a fee per call.
2. **Every asset it holds reserves another 0.1 ALGO.** Holding USDC costs 0.1
   ALGO of that minimum balance for as long as you hold it.
3. **Only the key holder can sign an opt-in.** Nobody can do it for your agent
   — not us, not the facilitator, not whoever sends the USDC.

Which is why USDC sent to an account that has not opted in is **rejected, not
held**. It does not arrive later; the transfer fails.

We ask for 0.3 rather than the 0.2 those rules require because an account
sitting exactly on its minimum balance cannot pay a transaction fee, and some
x402 clients pay their own. The spare covers it.

The per-call fee itself is usually free to you: BotTrunk advertises a fee
payer, so a client that builds the payment as an atomic group has the
facilitator cover the network fee and spends only USDC. A client that signs a
plain transfer pays about 0.001 ALGO of its own.

---

## Errors you might see, and what they mean

| What you see | What happened |
|---|---|
| `asset missing in destination account` (in Defly/Pera) | The agent has not opted in to USDC. Do step 3, then send. |
| `must optin, asset 31566704 missing from …` | The same thing, reported by the chain. |
| `receiver error` when sending USDC | Almost always the opt-in again. |
| `balance … below min` | The account is at its minimum balance. Send it a little more ALGO. |
| `This wallet holds 0.000000 ALGO and needs at least 0.3…` | The agent refused to sign a payment it cannot make. Do step 2. |
| `No wallet configured` | Step 1 has not been run, or `BOTTRUNK_HOME` points somewhere else. |

---

## Spending limits

The agent will not spend more than its caps, checked before anything is
signed:

| | Default | Set with |
|---|---|---|
| Per call | 100000000000 USDC | `BOTTRUNK_MAX_PER_CALL` |
| Per day (UTC) | 100000000000 USDC | `BOTTRUNK_MAX_PER_DAY` |

Those defaults sit above anything the catalog can list, because a cap that
refuses a purchase the buyer already decided on is not a safety feature. The
real ceiling is the wallet balance — an agent can only spend what you already
sent it. **If your agent should never spend
that much, lower them before you fund the wallet** — they are the only thing
standing between an agent and its whole balance.

Fund the agent with what you are willing to lose, the way you would give a
contractor a prepaid card rather than your bank login. The wallet is
disposable: if you want to retire it, move the USDC out and delete the file.

---

## What happens on a call

The agent asks for a service, gets HTTP 402 with the price, signs a USDC
transfer for exactly that amount, and retries. The service runs, the payment
settles on Algorand, and the response comes back with the transaction id.

If the request is rejected or the service fails, **nothing is settled and you
are not charged** — a 4xx or a 502 never takes money.

---

Full setup for twelve agent clients: <https://bottrunk.com/connect>
Protocol, error contract and limits: <https://bottrunk.com/docs>
Package: <https://www.npmjs.com/package/bottrunk-mcp>
