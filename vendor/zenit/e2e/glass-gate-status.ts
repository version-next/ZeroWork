import { readFileSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";
const root = resolve(process.argv[2] ?? "reports/glass-native-fidelity");
const contract = JSON.parse(readFileSync("e2e/glass-fidelity.contract.json", "utf8"));
const read = (file: string) => { try { return JSON.parse(readFileSync(`${root}/${file}`, "utf8")); } catch { return null; } };
const motion = read("native-motion/comparison.json");
const motionValid = !!process.env.ZENIT_GLASS_GATE_RUN_ID && motion?.run_id === process.env.ZENIT_GLASS_GATE_RUN_ID && motion.status === "PASS" &&
  contract.required_native_motion_actions.every((action: string) => motion.results?.some((r: any) => r.action === action && r.status === "PASS"));
const checks = [
  { name: "production_window_capture", status: read("probe-run/manifest.json")?.status ?? "MISSING" },
  ...contract.required_native_motion_actions.map((action: string) => ({ name: `production_motion_capture_${action}`, status: read(`native-motion/probe-run/${action}/manifest.json`)?.status ?? "MISSING" })),
  { name: "regional_native_fidelity", status: read("comparison.json")?.status ?? "MISSING" },
  { name: "playwright_pixelmatch", status: read("pixelmatch.json")?.status ?? "MISSING" },
  { name: "storybook_interactions", status: read("storybook-regressions/manifest.json")?.status ?? "MISSING" },
  { name: "storybook_scroll_flicker", status: read("storybook-flicker/manifest.json")?.status ?? "MISSING" },
  { name: "timestamped_native_motion", status: motionValid ? "PASS" : motion ? "FAIL" : "MISSING" },
];
const report = { schema_version: 1, status: checks.every(c => c.status === "PASS") ? "PASS" : "FAIL", run_id: process.env.ZENIT_GLASS_GATE_RUN_ID ?? null,
  claim: contract.claim, checks, incomplete_native_motion_actions: contract.required_native_motion_actions.filter((action:string)=>
    motion?.run_id!==process.env.ZENIT_GLASS_GATE_RUN_ID||!motion?.results?.some((r:any)=>r.action===action&&r.status==="PASS")) };
writeFileSync(`${root}/gate-status.json`, JSON.stringify(report, null, 2));
for (const c of checks) console.log(`${c.status}: ${c.name}`);
process.exit(report.status === "PASS" ? 0 : 1);
