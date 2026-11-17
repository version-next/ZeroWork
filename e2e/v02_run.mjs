/** Execute existing native acceptance runners against the checked-in public
 * Harness client, without installing into or overwriting the user's zig-out.
 * Secrets are only supplied through an externally created mode-600 JSON file.
 */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {mkdtemp,readFile,writeFile,rm,stat} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join,resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
const [suite,...args]=process.argv.slice(2);
const sources={local:'local_terminal.ts',local_edges:'local_session_edges.ts',vm:'v02_live_native.ts'};
assert(suite in sources,'Use local, local_edges or vm with a private explicit configuration');
if(process.env.ZEROWORK_ACCEPTANCE_CONFIG) assert.equal((await stat(process.env.ZEROWORK_ACCEPTANCE_CONFIG)).mode&0o077,0,'Secret fixture must be private');
const scratch=await mkdtemp(join(tmpdir(),'zw-v02-runner-'));
try {
 const client=pathToFileURL(resolve('vendor/zenit/e2e/client.ts')).href;
 // title-click: local_terminal.ts picks themes through ./theme_settings_entry.ts (设置 › 外观与主题); the copied runner lives in scratch, so point that import at the repo file.
 let contents=(await readFile(resolve('e2e',sources[suite]),'utf8')).replaceAll('../zig-out/share/zenit/harness/client.ts',client).replaceAll('./theme_settings_entry.ts',pathToFileURL(resolve('e2e/theme_settings_entry.ts')).href);
 if(suite==='local') {
  const start=contents.indexOf('  await clickTestId(\"local.status.grid\");',contents.indexOf('  await capture(\"local-compact\");'));
  // title-click: the title bar theme button (status.connection.theme) is gone; the theme step now starts at chooseTheme(…, "nord", …).
  const end=contents.indexOf('  await chooseTheme(harness, \"nord\"',start);
  assert(start>0&&end>start);
  contents=contents.slice(0,start)+'  await resizeWindow(1440,900);\n  await waitFor(async()=>text(await visible(\"local.status.grid\")).includes(originalGrid)||null);\n'+contents.slice(end);
 }
 const script=join(scratch,'runner.ts');await writeFile(script,contents,{mode:0o600});
 const child=spawn(process.execPath,[script,...args],{stdio:'inherit',env:process.env});
 process.exitCode=await new Promise((done,reject)=>{child.once('error',reject);child.once('close',code=>done(code??1));});
} finally {await rm(scratch,{recursive:true,force:true});}
