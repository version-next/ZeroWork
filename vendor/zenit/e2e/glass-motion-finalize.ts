import { readFileSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";
const root=resolve(process.argv[2]??"reports/glass-native-fidelity");
const file=`${root}/native-motion/comparison.json`,report=JSON.parse(readFileSync(file,"utf8"));
let pixelmatch:any=null;try{pixelmatch=JSON.parse(readFileSync(`${root}/native-motion/pixelmatch.json`,"utf8"));}catch{}
report.regional_and_trajectory_status=report.status;
report.pixelmatch_status=pixelmatch?.status??"MISSING";
report.status=report.regional_and_trajectory_status==="PASS"&&report.pixelmatch_status==="PASS"?"PASS":"FAIL";
for(const result of report.results) {
  result.regional_and_trajectory_status=result.status;
  const snapshots=report.snapshots.filter((s:any)=>s.action===result.action);
  const failures=snapshots.filter((s:any)=>pixelmatch?.results?.find((p:any)=>p.id===s.id)?.status!=="PASS");
  result.pixelmatch_status=snapshots.length&&failures.length===0?"PASS":"FAIL";
  if(result.pixelmatch_status!=="PASS") {
    result.status="FAIL";result.failures.push(`Playwright missing or failed: ${failures.map((s:any)=>s.id).join(", ")||"no snapshots"}`);
  }
}
writeFileSync(file,JSON.stringify(report,null,2));
const html=`${root}/native-motion/report.html`;
writeFileSync(html,readFileSync(html,"utf8").replace(/Timestamped native motion: (PASS|FAIL)/,`Timestamped native motion: ${report.status}`));
console.log(`Native motion: ${report.status} (geometry/regional=${report.regional_and_trajectory_status}, Playwright=${report.pixelmatch_status})`);
process.exit(report.status==="PASS"?0:1);
