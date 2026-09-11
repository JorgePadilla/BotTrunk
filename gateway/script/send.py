#!/usr/bin/env python3
"""Send ALGO or USDC from the machine-local payer wallet (the key in .env.local).

    bin/send <to-address> --usd 10            # $10 worth of ALGO at the current price
    bin/send <to-address> --algo 2.5          # exact ALGO
    bin/send <to-address> --usdc 1            # USDC (receiver must be opted in)

ALGORAND_NETWORK=testnet (default) or mainnet. Asks for confirmation before
broadcasting. The gateway wallet's key lives only in Defly, so this cannot
move funds *out* of the gateway wallet — that is a Defly send on the phone.
"""
import argparse, os, sys

import requests
from algosdk import account, encoding, mnemonic, transaction
from algosdk.v2client import algod

ENV = os.path.join(os.path.dirname(__file__), "..", ".env.local")
NETWORKS = {
    "testnet": ("https://testnet-api.algonode.cloud", 10458941),
    "mainnet": ("https://mainnet-api.algonode.cloud", 31566704),
}
MIN_BALANCE_RESERVE = 0.2  # ALGO kept back: 0.1 base + 0.1 for the USDC opt-in


def load_key():
    for line in open(ENV):
        if line.startswith("AGENT_WALLET_MNEMONIC="):
            return mnemonic.to_private_key(line.split("=", 1)[1].strip().strip('"'))
    sys.exit("no AGENT_WALLET_MNEMONIC in .env.local — run bin/agent-wallet first")


def algo_price_usd():
    r = requests.get("https://api.coingecko.com/api/v3/simple/price", params={"ids": "algorand", "vs_currencies": "usd"}, timeout=15)
    r.raise_for_status()
    return float(r.json()["algorand"]["usd"])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("to")
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--usd", type=float, help="send this many US dollars worth of ALGO")
    g.add_argument("--algo", type=float)
    g.add_argument("--usdc", type=float)
    ap.add_argument("--yes", action="store_true", help="skip the confirmation prompt")
    a = ap.parse_args()

    network = os.environ.get("ALGORAND_NETWORK", "testnet").lower()
    node, usdc_id = NETWORKS[network]
    client = algod.AlgodClient("", node)
    sk = load_key()
    sender = account.address_from_private_key(sk)
    if not encoding.is_valid_address(a.to):
        sys.exit("invalid destination address")

    info = client.account_info(sender)
    algo_bal = info["amount"] / 1e6
    usdc_bal = next((h["amount"] / 1e6 for h in info.get("assets", []) if h["asset-id"] == usdc_id), None)

    if a.usdc is not None:
        if usdc_bal is None or usdc_bal < a.usdc:
            sys.exit(f"payer has {usdc_bal} USDC on {network}; cannot send {a.usdc}")
        amount = int(round(a.usdc * 1e6))
        desc = f"{a.usdc} USDC"
    else:
        algos = a.algo
        if a.usd is not None:
            price = algo_price_usd()
            algos = round(a.usd / price, 6)
            print(f"ALGO price: ${price:.4f} → ${a.usd} = {algos} ALGO")
        spendable = algo_bal - MIN_BALANCE_RESERVE - 0.001
        if algos > spendable:
            sys.exit(f"payer has {algo_bal} ALGO on {network}; spendable {spendable:.6f} after the minimum balance — cannot send {algos}")
        amount = int(round(algos * 1e6))
        desc = f"{algos} ALGO"

    print(f"network : {network}\nfrom    : {sender}\nto      : {a.to}\namount  : {desc}")
    if not a.yes and input("send? [y/N] ").strip().lower() != "y":
        sys.exit("cancelled")

    sp = client.suggested_params()
    if a.usdc is not None:
        txn = transaction.AssetTransferTxn(sender=sender, sp=sp, receiver=a.to, amt=amount, index=usdc_id)
    else:
        txn = transaction.PaymentTxn(sender=sender, sp=sp, receiver=a.to, amt=amount)
    txid = client.send_transaction(txn.sign(sk))
    transaction.wait_for_confirmation(client, txid, 8)
    print(f"sent · txn {txid}")


if __name__ == "__main__":
    main()
