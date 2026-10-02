# frozen_string_literal: true

module DocsHelper
  # Renders `backticks` in plain prose as monospace, so the client notes on
  # /connect read like the docs they were copied from. Everything stays
  # escaped — the text is ours, but there is no reason to build HTML from it.
  def inline_code(text)
    parts = text.to_s.split("`")
    safe_join(parts.each_with_index.map { |part, i| i.odd? ? tag.span(part, class: "font-mono text-base-content") : part })
  end

  # A Python client that pays a BotTrunk 402 on Algorand MainNet, shared by
  # /docs and every service page. The old one imported `x402.clients`, which
  # does not exist, from `pip install x402`, which has no Algorand support.
  # This one was run against x402-avm 2.0.2 and paid our own 402 up to the
  # facilitator's checks. The package ships no signer, hence MnemonicSigner.
  def python_client_snippet(url, body)
    <<~PY.strip
      # pip install "x402-avm[avm,requests]==2.0.2"
      import base64, os
      from algosdk import encoding, mnemonic
      from x402 import x402ClientSync
      from x402.http import x402HTTPClientSync
      from x402.http.clients.requests import x402_requests
      from x402.mechanisms.avm import ALGORAND_MAINNET_CAIP2
      from x402.mechanisms.avm.exact import ExactAvmScheme

      class MnemonicSigner:  # signs the payment with your agent's 25-word mnemonic
          def __init__(self, words):
              self._sk = mnemonic.to_private_key(words)
              self.address = encoding.encode_address(base64.b64decode(self._sk)[32:])

          def sign_transactions(self, unsigned_txns, indexes_to_sign):
              return [base64.b64decode(encoding.msgpack_encode(
                          encoding.msgpack_decode(base64.b64encode(t).decode()).sign(self._sk)))
                      if i in indexes_to_sign else None
                      for i, t in enumerate(unsigned_txns)]

      # A wallet holding 0.3 ALGO, opted in to USDC, funded with the USDC it may spend.
      signer = MnemonicSigner(os.environ["ALGORAND_MNEMONIC"])
      client = x402ClientSync().register(ALGORAND_MAINNET_CAIP2,
          ExactAvmScheme(signer, algod_url="https://mainnet-api.algonode.cloud"))

      with x402_requests(client) as session:   # answers the 402, pays, retries
          r = session.post("#{url}", json=#{python_literal(body)})
          print(r.json())
          receipt = x402HTTPClientSync(client).get_payment_settle_response(r.headers.get)
          print(receipt.transaction)            # the settlement on-chain
    PY
  end

  # The TypeScript twin, the same calls bottrunk-mcp makes. The signer takes a
  # base64 64-byte key, not a mnemonic, and the scheme defaults to TestNet, so
  # both are spelled out.
  def typescript_client_snippet(url, body)
    <<~TS.strip
      // npm install @x402-avm/fetch @x402-avm/avm @x402-avm/core algosdk
      import algosdk from "algosdk";
      import { x402Client } from "@x402-avm/core/client";
      import { ExactAvmScheme } from "@x402-avm/avm/exact/client";
      import { toClientAvmSigner } from "@x402-avm/avm";
      import { wrapFetchWithPayment } from "@x402-avm/fetch";

      // A wallet holding 0.3 ALGO, opted in to USDC, funded with the USDC it may spend.
      const { sk } = algosdk.mnemonicToSecretKey(process.env.ALGORAND_MNEMONIC!);
      const signer = toClientAvmSigner(Buffer.from(sk).toString("base64"));
      const client = new x402Client().register("#{Payments::Networks.algorand(:mainnet)[:caip2]}",
        new ExactAvmScheme(signer, { algodUrl: "https://mainnet-api.algonode.cloud" })); // default is TestNet
      const fetchWithPay = wrapFetchWithPayment(fetch, client);

      const r = await fetchWithPay("#{url}", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(#{body.to_json}),
      });
      console.log(await r.json());
    TS
  end

  private

  # A request body as a Python literal: JSON's true/false/null are not Python.
  def python_literal(value)
    case value
    when Hash then "{" + value.map { |k, v| "#{k.to_s.to_json}: #{python_literal(v)}" }.join(", ") + "}"
    when Array then "[" + value.map { |v| python_literal(v) }.join(", ") + "]"
    when true then "True"
    when false then "False"
    when nil then "None"
    else value.to_json
    end
  end
end
