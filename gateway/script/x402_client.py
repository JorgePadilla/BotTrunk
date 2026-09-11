#!/usr/bin/env python3
"""Phase 0 payer: call a BotTrunk endpoint, pay the 402 with USDC on Algorand TestNet, print the result.

    pip3 install py-algorand-sdk requests
    export AGENT_WALLET_MNEMONIC="word1 word2 … word25"     # the *payer* wallet, never the gateway's
    python3 script/x402_client.py http://localhost:5000/s/scrape-markdown '{"url":"https://example.com"}'

Header/payload shapes follow docs/x402-algorand.md. Whatever the facilitator
actually accepts goes back into that file — this script is where we find out.
"""
import base64, json, os, sys

import requests
from algosdk import mnemonic, account, encoding, transaction
from algosdk.v2client import algod

ALGOD = {
    "algorand:SGO1GKSzyE7IEPItTxCByw9x8FmnrCDexi9/cOUJOiI=": "https://testnet-api.algonode.cloud",
    "algorand:wGHE2Pwdvd7S12BL5FaOP20EGYesN73ktiC1qzkkit8=": "https://mainnet-api.algonode.cloud",
}


def main(url: str, body: str) -> int:
    words = os.environ.get("AGENT_WALLET_MNEMONIC")
    if not words:
        sys.exit("AGENT_WALLET_MNEMONIC is not set")
    sk = mnemonic.to_private_key(words)
    payer = account.address_from_private_key(sk)
    headers = {"Content-Type": "application/json"}

    # 1. Ask without paying → expect 402 with requirements.
    first = requests.post(url, data=body, headers=headers, timeout=30)
    print(f"[1] {first.status_code} {first.reason}")
    if first.status_code != 402:
        print(first.text)
        return 1
    offer = first.json()
    req = offer["accepts"][0]
    print(f"    pay {req['amount']} atomic of asset {req['asset']} to {req['payTo']} on {req['network']}")

    # 2. Build and sign the USDC transfer.
    client = algod.AlgodClient("", ALGOD[req["network"]])
    sp = client.suggested_params()
    txn = transaction.AssetTransferTxn(
        sender=payer, sp=sp, receiver=req["payTo"], amt=int(req["amount"]), index=int(req["asset"]),
        note=f"x402 {req.get('resource', '')}".encode(),
    )
    signed = txn.sign(sk)
    payment = {
        "x402Version": 2,
        "scheme": req["scheme"],
        "network": req["network"],
        "resource": offer.get("resource") or {"url": req.get("resource")},
        "accepted": req,   # the requirement we chose (carries extra.tag for the challenge)
        "payload": {"paymentGroup": [encoding.msgpack_encode(signed)], "paymentIndex": 0},
    }
    if "extensions" in offer:  # discovery: the facilitator catalogs the resource on settle
        payment["extensions"] = offer["extensions"]
    x_payment = base64.b64encode(json.dumps(payment).encode()).decode()
    print(f"[2] signed txn {signed.get_txid()} from {payer}")

    # 3. Retry with X-PAYMENT.
    second = requests.post(url, data=body, headers={**headers, "X-PAYMENT": x_payment}, timeout=90)
    print(f"[3] {second.status_code} {second.reason}")
    receipt = second.headers.get("X-PAYMENT-RESPONSE")
    if receipt:
        print("    receipt:", json.dumps(json.loads(base64.b64decode(receipt)), indent=2))
    print(second.text[:800])
    return 0 if second.ok else 1


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    sys.exit(main(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else "{}"))
