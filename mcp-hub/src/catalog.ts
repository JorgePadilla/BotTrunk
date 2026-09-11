import { atomicToUsdc } from "./config.js";

/** Shape of GET /api/v1/catalog on the gateway. */
export interface CatalogField {
  name: string;
  type: "string" | "boolean" | "integer" | "number" | "object" | "array";
  description: string;
  example?: unknown;
}

export interface CatalogService {
  slug: string;
  name: string;
  summary: string;
  description: string;
  category: string;
  provider: string;
  endpoint: string;
  method: "POST";
  /** "live" = callable now; anything else is listed but not exposed as a tool. */
  status?: string;
  price: { amount: string; asset: string; decimals: number };
  /** Added Sept 2026; absent on older gateways, in which case MAINNET is assumed. */
  network?: { id: string; asset: string; name: string };
  inputs: CatalogField[];
  outputs: CatalogField[];
}

export async function fetchCatalog(apiBase: string, fetchImpl: typeof fetch = fetch): Promise<CatalogService[]> {
  const url = `${apiBase}/api/v1/catalog`;
  let res: Response;
  try {
    res = await fetchImpl(url, { headers: { Accept: "application/json" } });
  } catch (e) {
    // A bare "fetch failed" told nobody which host was unreachable, which is
    // the only thing worth knowing when every tool has just disappeared.
    throw new Error(`could not reach the catalog at ${url}: ${(e as Error).message}`);
  }
  if (!res.ok) throw new Error(`catalog request to ${url} failed: ${res.status} ${res.statusText}`);
  const body = (await res.json()) as { services: CatalogService[] };
  return body.services;
}

/** Only services the gateway marks live become paid tools; the rest are catalog-only. */
export function liveServices(services: CatalogService[]): CatalogService[] {
  return services.filter((s) => (s.status ?? "live") === "live");
}

/** Tool names must be [a-z0-9_]: "scrape-markdown" → "bottrunk_scrape_markdown". */
export function toolName(slug: string): string {
  return `bottrunk_${slug.toLowerCase().replace(/[^a-z0-9]+/g, "_")}`;
}

/** JSON Schema for the tool's input, straight from the catalog fields. */
export function inputSchema(service: CatalogService): Record<string, unknown> {
  const properties: Record<string, unknown> = {};
  for (const f of service.inputs) {
    const prop: Record<string, unknown> = { type: f.type, description: f.description };
    if (f.example !== undefined && f.example !== null) prop.examples = [f.example];
    properties[f.name] = prop;
  }
  // The first input is the one every service needs (url, text, name…); the rest are optional.
  const required = service.inputs.length ? [service.inputs[0].name] : [];
  return { type: "object", properties, required, additionalProperties: false };
}

export function priceLabel(service: CatalogService): string {
  return `${atomicToUsdc(BigInt(service.price.amount))} ${service.price.asset}`;
}

/** One-paragraph tool description an LLM can pick the tool from. */
export function toolDescription(service: CatalogService): string {
  const outputs = service.outputs.map((o) => `${o.name} (${o.type})`).join(", ");
  return `${service.description} Costs ${priceLabel(service)} per call, paid automatically from your BotTrunk wallet. Returns: ${outputs}.`;
}
