/** Self-test of e2e/provider_fixture.ts (run through run.ts, or `node e2e/provider_fixture_selftest.ts <out>`).
 *  Starts no app. Proves that
 *  - a request body whose multi-byte UTF-8 characters are cut by chunk boundaries is decoded to exactly the bytes sent,
 *    for every possible cut position, as a plain stream and over a real loopback HTTP request;
 *  - the per-chunk string append the fixtures used before (`raw += part`) corrupts the same input (the control: without
 *    it this test could not tell the two apart);
 *  - bytes that are not UTF-8, and a stream that was already put into string mode, are errors;
 *  - a poll budget is bounded by time, not by the number of polls.
 */
import assert from 'node:assert/strict';
import {createServer, request} from 'node:http';
import type {AddressInfo} from 'node:net';
import {mkdir, writeFile} from 'node:fs/promises';
import {join, resolve} from 'node:path';
import {Readable} from 'node:stream';
import {readRequestText, readRequestJson, createPollBudget} from './provider_fixture.ts';

const out = resolve(process.argv[2] ?? '.');
await mkdir(out, {recursive: true});
const report: any = {status: 'running', checks: []};

/** What the fixtures did before: every Buffer decoded on its own. */
async function legacyAppend(stream: AsyncIterable<unknown>): Promise<string> {
  let raw = ''; for await (const part of stream) raw += part; return raw;
}
const chunked = (bytes: Buffer, cuts: number[]) => {
  const parts: Buffer[] = []; let from = 0;
  for (const cut of [...cuts, bytes.length]) { parts.push(bytes.subarray(from, cut)); from = cut; }
  return parts.filter(part => part.length > 0);
};
// objectMode keeps the chunk boundaries exactly as given (a byte-mode Readable may merge buffered chunks).
const streamOf = (parts: Buffer[]) => Readable.from(parts, {objectMode: true});
const rejects = async (run: () => Promise<unknown>, type: any) => { try { await run(); } catch (e) { return e instanceof type; } return false; };

try {
  // 2-byte (é), 3-byte (CJK, full-width punctuation), 4-byte (emoji, surrogate pair in UTF-16) and a ZWJ sequence.
  const payload = {marker: '[历史环境，仅作记录]\n', note: 'café 终端 🙂 👩‍💻 ok', list: ['境', '𠮷', '€']};
  const text = JSON.stringify(payload), bytes = Buffer.from(text, 'utf8');
  assert(bytes.length > text.length, 'the sample must contain multi-byte characters');

  // Cut positions that fall inside a character: a continuation byte (10xxxxxx) follows the cut.
  const inside: number[] = [];
  for (let at = 1; at < bytes.length; at++) if ((bytes[at] & 0xc0) === 0x80) inside.push(at);
  assert(inside.length >= 40, 'expected many in-character cut positions, got ' + inside.length);

  // 1. One cut, at every byte offset.
  let legacyBroken = 0;
  for (let at = 1; at < bytes.length; at++) {
    const parts = chunked(bytes, [at]);
    const decoded = await readRequestText(streamOf(parts));
    assert.equal(decoded, text, 'cut at byte ' + at);
    assert(Buffer.from(decoded, 'utf8').equals(bytes), 'bytes differ for cut at ' + at);
    const legacy = await legacyAppend(streamOf(parts));
    if (inside.includes(at)) {
      assert(legacy.includes('�'), 'control: per-chunk append must corrupt a cut at byte ' + at);
      assert.notEqual(legacy, text);
      legacyBroken++;
    } else assert.equal(legacy, text, 'control: a cut between characters (byte ' + at + ') is harmless either way');
  }
  assert.equal(legacyBroken, inside.length);
  report.checks.push(`single cut at each of ${bytes.length - 1} byte offsets decodes byte-identically; per-chunk append corrupts all ${legacyBroken} in-character cuts`);

  // 2. One byte per chunk: every multi-byte character is split at every one of its boundaries.
  const single = chunked(bytes, Array.from({length: bytes.length - 1}, (_, i) => i + 1));
  assert.equal(single.length, bytes.length);
  assert.equal(await readRequestText(streamOf(single)), text);
  assert.deepEqual(await readRequestJson(streamOf(single)), payload);
  const legacySingle = await legacyAppend(streamOf(single));
  assert(legacySingle.includes('�') && !legacySingle.includes('历史环境'), 'control: one byte per chunk destroys the marker');
  let legacyJson: any = null; try { legacyJson = JSON.parse(legacySingle); } catch {}
  assert.notDeepEqual(legacyJson, payload, 'control: the corrupted text does not parse back to the payload');
  report.checks.push('one byte per chunk: text and JSON are exact; per-chunk append loses the “历史环境” marker');

  // 3. The exact case from the field: the marker cut in the middle of “境”.
  const cutInJing = bytes.indexOf(Buffer.from('境', 'utf8')) + 1;
  assert((await legacyAppend(streamOf(chunked(bytes, [cutInJing])))).includes('历史环��'), 'control: “境” becomes U+FFFD');
  assert((await readRequestText(streamOf(chunked(bytes, [cutInJing])))).includes('[历史环境，仅作记录]\\n'));
  report.checks.push('the “[历史环境，仅作记录]” marker survives a cut inside “境”');

  // 4. Strictness.
  assert.equal(await readRequestText(streamOf([])), '', 'an empty body is an empty string');
  assert(await rejects(() => readRequestJson(streamOf([])), SyntaxError), 'an empty body is not JSON');
  assert(await rejects(() => readRequestText(streamOf([Buffer.from([0x7b, 0xe5, 0x8e])])), TypeError), 'a truncated character is an error');
  assert(await rejects(() => readRequestText(streamOf([Buffer.from([0x22, 0xff, 0x22])])), TypeError), 'an invalid byte is an error');
  assert(await rejects(() => readRequestText(streamOf([Buffer.from([0xed, 0xa0, 0x80])])), TypeError), 'an encoded lone surrogate is an error');
  assert.equal((await legacyAppend(streamOf([Buffer.from([0x22, 0xff, 0x22])]))), '"�"', 'control: per-chunk append replaces quietly');
  const stringMode = streamOf(chunked(bytes, [cutInJing])); stringMode.setEncoding('utf8');
  assert(await rejects(() => readRequestText(stringMode), TypeError), 'a stream in string mode is refused');
  assert.equal(await readRequestText(streamOf([Buffer.from('﻿{}', 'utf8')])), '﻿{}', 'a BOM is kept, not dropped');
  report.checks.push('invalid / truncated UTF-8 and string-mode streams throw; empty body is \'\'; BOM is preserved');

  // 5. A real loopback request (IncomingMessage), body written in separately flushed pieces cut inside characters.
  //    TCP may merge pieces, so the control here is only observed, not asserted; the decoding must be exact regardless.
  const seen: {text: string, chunks: number, legacyWouldBreak: boolean}[] = [];
  const server = createServer(async (req, res) => {
    try {
      const parts: Buffer[] = []; for await (const part of req) parts.push(part as Buffer);
      const decoded = await readRequestText(streamOf(parts));
      seen.push({text: decoded, chunks: parts.length, legacyWouldBreak: (await legacyAppend(streamOf(parts))) !== decoded});
      res.end('ok');
    } catch (e) { res.statusCode = 500; res.end(String(e)); }
  });
  const direct = createServer(async (req, res) => {
    try { res.end(JSON.stringify(await readRequestJson(req))); } catch (e) { res.statusCode = 500; res.end(String(e)); }
  });
  await new Promise<void>(done => server.listen(0, '127.0.0.1', done));
  await new Promise<void>(done => direct.listen(0, '127.0.0.1', done));
  const post = (port: number, parts: Buffer[]) => new Promise<{status: number, body: string}>((done, fail) => {
    const req = request({host: '127.0.0.1', port, method: 'POST', path: '/v1/chat/completions', headers: {'content-type': 'application/json', 'content-length': bytes.length}}, res => {
      const got: Buffer[] = []; res.on('data', part => got.push(part)); res.on('end', () => done({status: res.statusCode!, body: Buffer.concat(got).toString('utf8')}));
    });
    req.on('error', fail); req.setNoDelay(true); req.flushHeaders();
    (async () => { for (const part of parts) { await new Promise<void>(next => req.write(part, () => next())); await new Promise(next => setTimeout(next, 15)); } req.end(); })().catch(fail);
  });
  try {
    const wireParts = chunked(bytes, inside.filter((_, i) => i % 7 === 0));
    assert.equal((await post((server.address() as AddressInfo).port, wireParts)).status, 200);
    assert.equal(seen.length, 1); assert.equal(seen[0].text, text);
    const echoed = await post((direct.address() as AddressInfo).port, wireParts);
    assert.equal(echoed.status, 200, echoed.body); assert.deepEqual(JSON.parse(echoed.body), payload);
    report.http = {pieces_written: wireParts.length, chunks_received: seen[0].chunks, per_chunk_append_would_corrupt: seen[0].legacyWouldBreak};
    report.checks.push('loopback HTTP request written in in-character pieces is read exactly by readRequestText / readRequestJson');
  } finally { server.close(); direct.close(); }

  // 6. Poll budget: time decides, the number of polls does not.
  let clock = 1000; const within = createPollBudget(() => clock);
  for (let poll = 0; poll < 500; poll++) assert(within('a', 30000), 'many early answers must not use the budget up');
  clock += 29999; assert(within('a', 30000));
  clock += 1; assert(!within('a', 30000), 'the budget ends at its time limit');
  assert(within('b', 30000), 'another key has its own clock, started by its first call');
  clock += 60000; assert(!within('a', 30000) && !within('b', 30000));
  report.checks.push('poll budget: 500 polls inside the limit stay open, closes exactly at the limit, keys are independent');

  report.status = 'passed';
} catch (e) {
  report.status = 'failed';
  report.error = String((e as any)?.stack ?? e);
  process.exitCode = 1;
} finally {
  await writeFile(join(out, 'report.json'), JSON.stringify(report, null, 2));
  console.log(JSON.stringify(report));
}
