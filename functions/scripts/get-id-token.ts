/**
 * Mints a Firebase ID token for hitting the deployed HTTP functions by hand.
 * The token is the ONLY thing on stdout, so it composes:
 *
 *   cd functions
 *   ID_TOKEN=$(npm run -s token)
 *   curl -N -X POST $URL -H "Authorization: Bearer $ID_TOKEN" ...
 *
 * Everything else — which mode ran, the uid, when it expires — goes to stderr so
 * it stays readable without polluting the capture.
 *
 * Modes:
 *   npm run -s token                                   anonymous sign-in (default)
 *   npm run -s token -- --email a@b.c --password pw     existing email/password user
 *   npm run -s token -- --email a@b.c --password pw --signup   create that user first
 *
 * The Web API key is read from GoogleService-Info.plist at the repo root, so
 * normally there is nothing to configure. Override with --api-key or
 * FIREBASE_WEB_API_KEY when pointing at another Firebase project.
 *
 * This calls the real Identity Toolkit REST API — it does not work against the
 * auth emulator, and the tokens it returns are real credentials for the project.
 * They expire in 1 hour. Do not paste them into tickets or commits.
 */
import * as fs from "fs";
import * as path from "path";

const IDENTITY_BASE = "https://identitytoolkit.googleapis.com/v1/accounts";
const PLIST_PATH = path.resolve(__dirname, "../../GoogleService-Info.plist");

interface Args {
  apiKey: string | null;
  email: string | null;
  password: string | null;
  signup: boolean;
  json: boolean;
}

function die(message: string): never {
  console.error(message);
  process.exit(1);
}

function parseArgs(argv: string[]): Args {
  const args: Args = { apiKey: null, email: null, password: null, signup: false, json: false };
  for (let i = 0; i < argv.length; i++) {
    const flag = argv[i];
    if (flag === "--api-key") args.apiKey = argv[++i] ?? null;
    else if (flag === "--email") args.email = argv[++i] ?? null;
    else if (flag === "--password") args.password = argv[++i] ?? null;
    else if (flag === "--signup") args.signup = true;
    else if (flag === "--json") args.json = true;
    else if (flag === "--help" || flag === "-h") {
      console.error(
        "usage: npm run -s token [-- --email a@b.c --password pw [--signup]] " +
          "[--api-key KEY] [--json]"
      );
      process.exit(0);
    } else die(`unknown argument: ${flag}`);
  }
  if (args.email && !args.password) die("--email needs --password");
  if (args.password && !args.email) die("--password needs --email");
  return args;
}

/**
 * Pulls API_KEY out of GoogleService-Info.plist. A regex rather than a plist
 * parser: the file is a fixed, committed, machine-generated shape, and one
 * dependency for one string is not worth it.
 */
function apiKeyFromPlist(): string | null {
  if (!fs.existsSync(PLIST_PATH)) return null;
  const plist = fs.readFileSync(PLIST_PATH, "utf8");
  const match = /<key>API_KEY<\/key>\s*<string>([^<]+)<\/string>/.exec(plist);
  return match ? match[1].trim() : null;
}

function resolveApiKey(args: Args): string {
  const key = args.apiKey ?? process.env.FIREBASE_WEB_API_KEY ?? apiKeyFromPlist();
  if (!key) {
    die(
      `could not find a Firebase Web API key.\n` +
        `  looked at: --api-key, $FIREBASE_WEB_API_KEY, ${PLIST_PATH}\n` +
        `  find it in Firebase console → Project settings → Web API Key.`
    );
  }
  return key;
}

interface TokenResponse {
  idToken: string;
  localId: string;
  expiresIn: string;
  email?: string;
}

/** Maps Identity Toolkit's terse error codes onto the fix for each one. */
function explain(code: string): string {
  switch (code) {
    case "ADMIN_ONLY_OPERATION":
      return "anonymous sign-in is disabled for this project — enable it in Firebase console → Authentication → Sign-in method, or pass --email/--password instead";
    case "EMAIL_NOT_FOUND":
    case "INVALID_LOGIN_CREDENTIALS":
    case "INVALID_PASSWORD":
      return "wrong email or password, or that user does not exist — add --signup to create it";
    case "EMAIL_EXISTS":
      return "that user already exists — drop --signup and just sign in";
    case "WEAK_PASSWORD : Password should be at least 6 characters":
      return "password must be at least 6 characters";
    case "API_KEY_INVALID":
    case "INVALID_API_KEY":
      return "the Web API key is wrong for this project";
    case "OPERATION_NOT_ALLOWED":
      return "email/password sign-in is disabled in Firebase console → Authentication → Sign-in method";
    default:
      return "see https://firebase.google.com/docs/reference/rest/auth for this code";
  }
}

async function post(endpoint: string, apiKey: string, body: unknown): Promise<TokenResponse> {
  const response = await fetch(`${IDENTITY_BASE}:${endpoint}?key=${apiKey}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body)
  });
  const payload = (await response.json()) as Record<string, any>;
  if (!response.ok) {
    const code = String(payload?.error?.message ?? `HTTP ${response.status}`);
    die(`Firebase rejected the request: ${code}\n  → ${explain(code)}`);
  }
  if (!payload.idToken) die(`no idToken in the response: ${JSON.stringify(payload)}`);
  return payload as TokenResponse;
}

async function main(): Promise<void> {
  const args = parseArgs(process.argv.slice(2));
  const apiKey = resolveApiKey(args);

  let result: TokenResponse;
  if (args.email && args.password) {
    const endpoint = args.signup ? "signUp" : "signInWithPassword";
    console.error(`${args.signup ? "creating" : "signing in"} ${args.email}`);
    result = await post(endpoint, apiKey, {
      email: args.email,
      password: args.password,
      returnSecureToken: true
    });
  } else {
    console.error("signing in anonymously");
    result = await post("signUp", apiKey, { returnSecureToken: true });
  }

  const minutes = Math.round(Number(result.expiresIn ?? 3600) / 60);
  console.error(`uid ${result.localId} · expires in ~${minutes} min`);

  if (args.json) {
    // stdout stays machine-readable in both modes: bare token, or one JSON object.
    process.stdout.write(
      `${JSON.stringify(
        { idToken: result.idToken, uid: result.localId, expiresIn: result.expiresIn },
        null,
        2
      )}\n`
    );
  } else {
    process.stdout.write(`${result.idToken}\n`);
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
