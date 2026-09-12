import fs from "node:fs";
import path from "node:path";
import { atomicToUsdc, type Config } from "./config.js";

/**
 * Spending caps, enforced before a payment is signed.
 *
 * Per-call: refuse anything the 402 asks for above maxPerCall.
 * Per-day: a tiny JSON ledger of what this machine has paid today (UTC),
 * so a runaway agent loop stops at maxPerDay instead of at an empty wallet.
 */
interface SpendFile {
  day: string; // YYYY-MM-DD (UTC)
  spentAtomic: string;
  calls: number;
}

export class SpendCapError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "SpendCapError";
  }
}

export class SpendTracker {
  constructor(
    private readonly config: Config,
    private readonly now: () => Date = () => new Date(),
  ) {}

  private today(): string {
    return this.now().toISOString().slice(0, 10);
  }

  private read(): SpendFile {
    try {
      const parsed = JSON.parse(fs.readFileSync(this.config.spendFile, "utf8")) as SpendFile;
      if (parsed.day === this.today()) return parsed;
    } catch {
      /* first run or unreadable → fresh day */
    }
    return { day: this.today(), spentAtomic: "0", calls: 0 };
  }

  private write(file: SpendFile): void {
    fs.mkdirSync(path.dirname(this.config.spendFile), { recursive: true, mode: 0o700 });
    fs.writeFileSync(this.config.spendFile, JSON.stringify(file, null, 2) + "\n", { mode: 0o600 });
  }

  spentToday(): bigint {
    return BigInt(this.read().spentAtomic);
  }

  /** Throws SpendCapError when paying `amount` would break either cap. */
  assertAllowed(amount: bigint): void {
    const perCall = this.config.maxPerCallAtomic;
    const perDay = this.config.maxPerDayAtomic;
    if (perCall !== null && amount > perCall) {
      throw new SpendCapError(
        `This call costs ${atomicToUsdc(amount)} USDC, above the per-call cap of ${atomicToUsdc(perCall)} USDC. Raise BOTTRUNK_MAX_PER_CALL to allow it, or set it to "none" for no cap at all.`,
      );
    }
    if (perDay === null) return;

    const spent = this.spentToday();
    if (spent + amount > perDay) {
      throw new SpendCapError(
        `Paying ${atomicToUsdc(amount)} USDC would exceed today's cap of ${atomicToUsdc(perDay)} USDC (already spent ${atomicToUsdc(spent)}). Raise BOTTRUNK_MAX_PER_DAY or wait for tomorrow (UTC).`,
      );
    }
  }

  /** Records a settled payment. Call only after the gateway returned 200. */
  record(amount: bigint): void {
    const file = this.read();
    file.spentAtomic = (BigInt(file.spentAtomic) + amount).toString();
    file.calls += 1;
    this.write(file);
  }
}
