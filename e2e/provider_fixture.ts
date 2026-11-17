/** Shared pieces of the loopback provider / MCP fixtures that e2e scripts start inline (`createServer(async (req, res) => …)`).
 *
 *  Request body: `readRequestText(req)` / `readRequestJson(req)`.
 *  A request body arrives as Buffers cut wherever TCP cut them. Appending them to a string (`raw += part`) decodes every
 *  Buffer on its own, so a multi-byte UTF-8 character that straddles two chunks becomes U+FFFD on both sides — the fixture
 *  then sees text the application never sent (first seen in ai_group_handoff_retention_native: the “[历史环境，仅作记录]”
 *  marker stopped matching). The body is decoded once, as a whole, and strictly: bytes that are not UTF-8 are an error in
 *  the request, not something to replace quietly.
 *
 *  Waits that span several provider requests: `pollWithin(key, ms)`.
 *  A scripted provider waits for application state by asking the model side to call a tool again (`host.wait_execution`,
 *  `host.get_session`, …); every answer arrives as a new HTTP request that replays the handler from the top. Bounding
 *  such a wait by the number of polls ties it to how often the application answers early (a revision change that is not
 *  yet the awaited state used up one poll), not to how long the wait may take. It is bounded by time instead.
 *
 *  Not for waits inside one function: those use the harness `waitFor(cond, ms)`.
 */

/** The whole body of `stream` as text. Throws (TypeError) when the bytes are not valid UTF-8, and when the stream yields
 *  strings — a caller that ran `setEncoding` already picked its own decoder; this helper owns decoding. */
export async function readRequestText(stream: AsyncIterable<unknown>): Promise<string> {
  const parts: Uint8Array[] = [];
  for await (const part of stream) {
    if (!(part instanceof Uint8Array)) throw new TypeError('readRequestText expects a byte stream, got a ' + typeof part + ' chunk');
    parts.push(part);
  }
  // ignoreBOM: keep a leading U+FEFF, so the text is exactly what the bytes say.
  return new TextDecoder('utf-8', {fatal: true, ignoreBOM: true}).decode(Buffer.concat(parts));
}

/** The body of `stream` parsed as JSON. An empty or malformed body throws the SyntaxError of `JSON.parse`. */
export async function readRequestJson<T = any>(stream: AsyncIterable<unknown>): Promise<T> {
  return JSON.parse(await readRequestText(stream));
}

export type PollBudget = (key: string, ms: number) => boolean;

/** A set of named time budgets. `budget(key, ms)` starts `key`'s clock on its first call and answers whether fewer than
 *  `ms` milliseconds have passed since. */
export function createPollBudget(now: () => number = () => performance.now()): PollBudget {
  const started = new Map<string, number>();
  return (key, ms) => {
    const t = now();
    let t0 = started.get(key);
    if (t0 === undefined) started.set(key, t0 = t);
    return t - t0 < ms;
  };
}

/** The process-wide budget set of a script. Ask it only at the point where another poll is about to be issued, after the
 *  answers already received were consumed:
 *
 *      for (let i = 0; !done(observed); i++) {
 *        const next = results.get('wait-' + i);
 *        if (!next) { if (!pollWithin('wait', 60000)) break; return emit('wait-' + i, 'host.wait_execution', …); }
 *        observed = next;
 *      }
 *      assert(done(observed), …);
 *
 *  A handler replays the whole exchange on every request, so a check in the loop header would stop reading answers that
 *  did arrive once the budget has run out later in the same turn. `key` names one wait; give each stage / scenario that
 *  repeats the same code its own key. */
export const pollWithin: PollBudget = createPollBudget();
