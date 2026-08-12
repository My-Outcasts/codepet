// Rules tests only. Separate from jest.config.js because these need the
// Firestore emulator (and therefore a JRE) — `npm run test:rules` starts one
// via `firebase emulators:exec`, while the default suite must stay runnable
// on a machine without Java.
module.exports = {
  preset: "ts-jest",
  testEnvironment: "node",
  testMatch: ["**/__tests__/rules.test.ts"],
  // Emulator startup plus a handful of round trips is well past the 10s the
  // unit suite uses.
  testTimeout: 30000,
  globals: {
    "ts-jest": {
      tsconfig: "tsconfig.test.json"
    }
  }
};
