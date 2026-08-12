/**
 * One-shot: copy `companies/{uid}.credits` into the write-denied balance
 * document (`companies/{uid}/engBalance/current`) that engStartRun and
 * engWebhook now use. See `src/engineering/engBalance.ts` for why the number
 * moved.
 *
 *   cd functions
 *   GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json \
 *     npx ts-node --compilerOptions '{"module":"commonjs"}' scripts/migrate-eng-balance.ts
 *
 * Add `--apply` to write. Without it this is a dry run that reports exactly
 * what it would do and touches nothing — the default, because the failure
 * mode of getting this wrong is a founder's balance, and a dry run costs
 * nothing.
 *
 * RUN THIS BEFORE DEPLOYING the new engStartRun. Nothing reads engBalance
 * until that deploy lands, so migrating early is safe; migrating late means
 * every run 402s ("no credits") in the gap.
 *
 * IDEMPOTENT BY SKIPPING, NOT BY OVERWRITING. A company that already has a
 * balance document is left exactly as it is. Re-running after a founder has
 * spent credits must not restore them to the pre-migration figure — that is
 * the one mistake here that silently hands out money.
 */
import * as admin from "firebase-admin";
import { BALANCE_PATH } from "../src/engineering/engBalance";

interface Tally {
  migrated: number;
  skippedExisting: number;
  skippedNoCredits: number;
}

/**
 * What to do with one company. Pure, so the decision is testable and readable
 * without a Firestore in the loop.
 */
export function decide(
  credits: unknown,
  balanceExists: boolean
): "migrate" | "skip-existing" | "skip-no-credits" {
  // Existing balance wins, always, and is checked FIRST — a company that has
  // already been migrated and has since spent credits would otherwise be
  // topped back up to its original figure.
  if (balanceExists) return "skip-existing";
  // `Number.isFinite`, not `typeof === "number"`: NaN and Infinity are both
  // numbers, and copying either produces a balance `readBalance` then reports
  // as 0 — a founder locked out with no trace of why.
  if (!Number.isFinite(credits)) return "skip-no-credits";
  return "migrate";
}

async function main(): Promise<void> {
  const apply = process.argv.includes("--apply");
  admin.initializeApp();
  const db = admin.firestore();

  const companies = await db.collection("companies").get();
  const tally: Tally = { migrated: 0, skippedExisting: 0, skippedNoCredits: 0 };

  for (const company of companies.docs) {
    const credits = company.data().credits;
    const ref = db.doc(BALANCE_PATH(company.id));
    const verdict = decide(credits, (await ref.get()).exists);

    if (verdict === "skip-existing") {
      tally.skippedExisting++;
      continue;
    }
    if (verdict === "skip-no-credits") {
      tally.skippedNoCredits++;
      continue;
    }
    // The uid is a Firestore document id, not a secret, and the credit figure
    // is the founder's own balance — both are safe to print, and printing
    // them is the point of the dry run.
    console.log(`${apply ? "migrating" : "would migrate"} ${company.id}: credits=${credits}`);
    if (apply) await ref.set({ credits });
    tally.migrated++;
  }

  console.log(
    `${apply ? "migrated" : "would migrate"} ${tally.migrated}; ` +
      `skipped ${tally.skippedExisting} already-migrated, ` +
      `${tally.skippedNoCredits} with no usable credits figure`
  );
  if (!apply) console.log("\nDry run — nothing was written. Re-run with --apply.");
}

if (require.main === module) {
  main().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}
