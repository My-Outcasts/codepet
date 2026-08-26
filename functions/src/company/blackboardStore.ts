/**
 * The Firestore half of the blackboard: reading and writing a run.
 *
 * Split from `blackboard.ts` so the pure half — build, record a position, record usage —
 * carries no `firebase-admin` import. `local/vcSidecar` is esbuild-bundled into the app and
 * inlines whatever it reaches, and the orchestration it runs needs those pure functions;
 * reaching them through this file would ship the whole Admin SDK (measured elsewhere in this
 * work: 7.5 MB). Persistence is injected into the orchestrator instead, which is also what
 * lets a local run have none — there is no `companies/{uid}` to write to from the founder's
 * own machine.
 */

import * as admin from "firebase-admin";
import { Blackboard } from "./types";

export const COMPANY_RUNS_COLLECTION = "company_runs";

export async function saveBlackboard(bb: Blackboard): Promise<void> {
  await admin
    .firestore()
    .collection(COMPANY_RUNS_COLLECTION)
    .doc(bb.run_id)
    .set(bb, { merge: true });
}

export async function loadBlackboard(runId: string): Promise<Blackboard | null> {
  const snap = await admin
    .firestore()
    .collection(COMPANY_RUNS_COLLECTION)
    .doc(runId)
    .get();
  return snap.exists ? (snap.data() as Blackboard) : null;
}
