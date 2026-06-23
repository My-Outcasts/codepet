import * as admin from "firebase-admin";

export function extractBearerToken(header: string | undefined): string | null {
  if (!header) return null;
  const match = /^Bearer\s+(.+)$/.exec(header);
  if (!match) return null;
  const token = match[1].trim();
  return token.length > 0 ? token : null;
}

export interface AuthResult {
  uid: string;
}

/**
 * Verifies the Authorization header on a request.
 * Returns { uid } on success, or null on failure (caller must respond 401).
 */
export async function verifyAuth(
  authHeader: string | undefined
): Promise<AuthResult | null> {
  const token = extractBearerToken(authHeader);
  if (!token) return null;
  try {
    const decoded = await admin.auth().verifyIdToken(token);
    return { uid: decoded.uid };
  } catch {
    return null;
  }
}
