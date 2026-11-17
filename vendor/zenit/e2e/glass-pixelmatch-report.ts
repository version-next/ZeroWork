// Summarize the public Playwright matcher output; never reimplement its verdict.
import { readFileSync, writeFileSync, copyFileSync, mkdirSync } from "node:fs";
import { resolve } from "node:path";
import { decodePng } from "./png";

export function reportPixelmatch(root: string) {
  const result = JSON.parse(readFileSync(`${root}/playwright/results.json`, "utf8"));
  const provenance = JSON.parse(readFileSync(`${root}/playwright/provenance.json`, "utf8"));
  const contract = JSON.parse(readFileSync(process.env.ZENIT_GLASS_COMPARISON_CONTRACT ?? "e2e/glass-fidelity.contract.json", "utf8"));
  const specs: any[] = [];
  const visit = (suite: any) => { specs.push(...(suite.specs ?? [])); for (const child of suite.suites ?? []) visit(child); };
  for (const suite of result.suites) visit(suite);
  mkdirSync(`${root}/playwright/diff`, { recursive: true });
  const rows = contract.required_cases.map((id: string) => {
    const matches = specs.filter(s => s.title === `native glass ${id}`);
    if (matches.length !== 1) throw new Error(`Missing or duplicate Playwright result ${id}`);
    const runs = matches[0].tests;
    if (runs.length !== 1 || runs[0].results.length !== 1) throw new Error(`Unexpected retries/projects for ${id}`);
    const run = runs[0].results[0], c = provenance.cases.find((c: any) => c.id === id);
    if (!c) throw new Error(`Missing ROI provenance ${id}`);
    const error = String(run.error?.message ?? "").replace(/\u001b\[[0-9;]*m/g, "");
    const count = run.status === "passed" ? 0 : Number(error.match(/(\d+) pixels \(ratio [\d.]+ of all image pixels\) are different/)?.[1]);
    const diff = run.attachments?.find((a: any) => a.name === `${id}-diff.png`);
    if (Number.isFinite(count) && count > 0) {
      if (!diff?.path) throw new Error(`Playwright omitted the diff for ${id}`);
      const p = decodePng(diff.path);
      if (p.width !== c.roi.w || p.height !== c.roi.h) throw new Error(`Invalid diff dimensions ${id}`);
      let red = 0;
      for (let i = 0; i < p.pixels.length; i += p.channels)
        if (p.pixels[i] === 255 && p.pixels[i+1] === 0 && p.pixels[i+2] === 0) red++;
      if (red !== count) throw new Error(`Diff pixel count disagrees with Playwright for ${id}: ${red} != ${count}`);
      copyFileSync(diff.path, `${root}/playwright/diff/${id}.png`);
    }
    return { id, status: run.status === "passed" ? "PASS" : Number.isFinite(count) ? "FAIL" : "ERROR", diff_pixels: Number.isFinite(count) ? count : null,
      diff_pixel_ratio: Number.isFinite(count) ? count / (c.roi.w * c.roi.h) : null, roi: c.roi, error: error || null };
  });
  const report = { schema_version: 1, status: rows.every((r: any) => r.status === "PASS") && !(result.errors?.length) ? "PASS" : "FAIL",
    scope: contract.comparison_scope ?? "Static native material comparison using Playwright's public pixelmatch matcher; this does not establish timestamped native motion equivalence or exact 1:1 reproduction",
    options: contract.playwright, provenance, results: rows };
  writeFileSync(`${root}/pixelmatch.json`, JSON.stringify(report, null, 2));
  const esc = (s: string) => s.replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll("\"", "&quot;");
  const percent = (r: any) => r.diff_pixel_ratio === null ? "—" : `${(r.diff_pixel_ratio * 100).toFixed(4)}%`;
  const table = rows.map((r: any) => `<tr><td><a href="#${r.id}">${r.id}</a></td><td class="${r.status}">${r.status}</td><td>${r.diff_pixels ?? "—"}</td><td>${percent(r)}</td></tr>`).join("");
  const figures = rows.map((r: any) => `<section id="${r.id}"><h2>${r.id}: <span class="${r.status}">${r.status}</span></h2><p>${r.diff_pixels ?? "Unknown"} differing pixels · ${percent(r)} of the material ROI</p><div class="comparison">${[["SwiftUI native", "reference"], ["Zenit production", "actual"], ...(r.status === "FAIL" ? [["Playwright pixelmatch diff", "diff"]] : [])].map(([label, folder]) => `<figure><figcaption>${label}</figcaption><img src="playwright/${folder}/${r.id}.png"></figure>`).join("")}</div><p><a href="native/${r.id}.png">Full SwiftUI window</a> · <a href="zenit/${r.id}.png">Full Zenit window</a></p>${r.status === "ERROR" ? `<pre>${esc(r.error ?? "Capture/test failed")}</pre>` : ""}</section>`).join("");
  writeFileSync(`${root}/pixelmatch.html`, `<!doctype html><meta charset="utf-8"><title>SwiftUI vs Zenit — Playwright pixelmatch</title><style>body{font:14px system-ui;background:#181818;color:#ddd;padding:24px;max-width:1600px;margin:auto}a{color:#9bc6ff}table{border-collapse:collapse}th,td{padding:8px 18px;text-align:left;border-bottom:1px solid #444}.PASS{color:#8ee0a2}.FAIL,.ERROR{color:#ff8d8d}.comparison{display:flex;gap:12px;align-items:start}figure{margin:0;flex:1;min-width:0}img{width:100%;image-rendering:auto}figcaption{margin-bottom:8px}section{margin:40px 0}pre{white-space:pre-wrap}</style><h1>SwiftUI / Zenit: Playwright visual comparison — ${report.status}</h1><p>${rows.filter((r: any) => r.status === "PASS").length}/${rows.length} cases pass. Playwright ${contract.playwright.version}, actual <code>expect(Buffer).toMatchSnapshot()</code>, threshold=${contract.playwright.threshold}, maxDiffPixels=${contract.playwright.maxDiffPixels}.</p><p>Identical geometry-defined material crops include 16 logical pixels of shadow. No resizing or registration repair. Red = differing pixels; yellow = antialiasing excluded by pixelmatch. The percentages below use exact pixel counts; Playwright's error message rounds its ratio upwards.</p><p>A PASS permits the comparator's perceptual color tolerance. It does not mean exact pixel equality or native motion equivalence. <a href="report.html">Regional RMSE / SSIM report</a> · <a href="playwright/report/index.html">Original Playwright report</a> · <a href="pixelmatch.json">Machine-readable results</a></p><table><thead><tr><th>Case</th><th>Result</th><th>Differing pixels</th><th>ROI ratio</th></tr></thead><tbody>${table}</tbody></table>${figures}`);
  console.log(`Playwright pixelmatch: ${rows.filter((r: any) => r.status === "PASS").length}/${rows.length} PASS; overall ${report.status}`);
  return report;
}
if (import.meta.main) { try { const r = reportPixelmatch(resolve(process.argv[2] ?? "reports/glass-native-fidelity")); process.exit(r.status === "PASS" ? 0 : 1); } catch (e) { console.error(e); process.exit(1); } }
