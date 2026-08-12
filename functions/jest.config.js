module.exports = {
  preset: "ts-jest",
  testEnvironment: "node",
  testMatch: ["**/__tests__/**/*.test.ts"],
  // rules.test.ts needs the Firestore emulator, which needs a JRE. Running it
  // here would turn `npm test` red on any machine without Java — a failure
  // that reads like a broken security rule. It runs under
  // `npm run test:rules` with jest.rules.config.js instead.
  testPathIgnorePatterns: ["/node_modules/", "/__tests__/rules\\.test\\.ts$"],
  collectCoverageFrom: ["src/**/*.ts", "!src/**/__tests__/**"],
  testTimeout: 10000,
  globals: {
    "ts-jest": {
      tsconfig: "tsconfig.test.json"
    }
  }
};
