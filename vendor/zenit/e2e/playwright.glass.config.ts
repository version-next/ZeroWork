import { defineConfig } from "@playwright/test";
import { resolve } from "node:path";
import { readFileSync } from "node:fs";

const root = resolve(process.env.ZENIT_GLASS_EVIDENCE_DIR ?? resolve(__dirname, "../reports/glass-native-fidelity"));
const options = JSON.parse(readFileSync(process.env.ZENIT_GLASS_COMPARISON_CONTRACT ?? resolve(__dirname, "glass-fidelity.contract.json"), "utf8")).playwright;
export default defineConfig({
  testDir: __dirname,
  testMatch: "glass-pixelmatch.spec.ts",
  workers: 1,
  fullyParallel: false,
  forbidOnly: true,
  retries: 0,
  timeout: 15_000,
  updateSnapshots: "none",
  snapshotPathTemplate: `${root}/playwright/reference/{arg}{ext}`,
  outputDir: `${root}/playwright/artifacts`,
  expect: { toMatchSnapshot: { threshold: options.threshold, maxDiffPixels: options.maxDiffPixels } },
  reporter: [
    ["line"],
    ["json", { outputFile: `${root}/playwright/results.json` }],
    ["html", { outputFolder: `${root}/playwright/report`, open: "never" }],
  ],
});
