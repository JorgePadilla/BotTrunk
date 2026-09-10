#!/usr/bin/env python3
"""Payer wallet for the spike, generated on this machine (same key on both networks).

    bin/agent-wallet            # create (once) and show address + balances
    bin/agent-wallet optin      # opt in to USDC on the selected network (needs ~0.3 ALGO first)

ALGORAND_NETWORK=testnet (default) or mainnet selects node and USDC asset.
The mnemonic is written to gateway/.env.local (git-ignored) and never printed.
Keep only small amounts here: it is a hot key on a laptop.
"""
import os, sys

from algosdk import account, mnemonic, transaction
from algosdk.v2client import algod

ENV = os.path.join(os.path.dirname(__file__), "..", ".env.local")
NETWORKS = {
    "testnet": ("https://testnet-api.algonode.cloud", 10458941),
    "mainnet": ("https://mainnet-api.algonode.cloud", 31566704),
}
NETWORK = os.environ.get("ALGORAND_NETWORK", "testnet").lower()
if NETWORK not in NETWORKS:
    sys.exit(f"ALGORAND_NETWORK must be one of {list(NETWORKS)}")
ALGOD = algod.AlgodClient("", NETWORKS[NETWORK][0])
USDC = NETWORKS[NETWORK][1]


def load_or_create():
    if os.path.exists(ENV):
        for line in open(ENV):
            if line.startswith("AGENT_WALLET_MNEMONIC="):
                words = line.split("=", 1)[1].strip().strip('"')
                return mnemonic.to_private_key(words), "existing"
    sk, addr = account.generate_account()
    with open(ENV, "a") as f:
        f.write(f'AGENT_WALLET_MNEMONIC="{mnemonic.from_private_key(sk)}"\n')
    os.chmod(ENV, 0o600)
    return sk, "created"


def show(addr):
    info = ALGOD.account_info(addr)
    algo = info["amount"] / 1e6
    usdc = next((a["amount"] / 1e6 for a in info.get("assets", []) if a["asset-id"] == USDC), None)
    print(f"address : {addr}")
    print(f"ALGO    : {algo}")
    print(f"USDC    : {'not opted in' if usdc is None else usdc}")
    return algo, usdc


def optin(sk, addr):
    sp = ALGOD.suggested_params()
    txn = transaction.AssetTransferTxn(sender=addr, sp=sp, receiver=addr, amt=0, index=USDC)
    txid = ALGOD.send_transaction(txn.sign(sk))
    transaction.wait_for_confirmation(ALGOD, txid, 8)
    print(f"opted in to USDC ({USDC}), txn {txid}")


if __name__ == "__main__":
    sk, state = load_or_create()
    addr = account.address_from_private_key(sk)
    print(f"agent wallet ({state}) on {NETWORK}")
    algo, usdc = show(addr)
    if len(sys.argv) > 1 and sys.argv[1] == "optin":
        if algo < 0.21:
            sys.exit("send at least 0.3 ALGO to this address first (min balance + fee)")
        if usdc is None:
            optin(sk, addr)
            show(addr)
        else:
            print("already opted in")
