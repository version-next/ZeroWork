/** Conversation-title requests in AI e2e provider fixtures.
 *  The first question of every conversation also sends one bounded, tool-free title request
 *  (src/ai/conversation_title.zig). Fixtures that script conversation rounds answer it with an
 *  empty stream (the conversation keeps its first-question fallback title) and do not count it
 *  as a round. ai_titles_native exercises the title request itself. */
import type {ServerResponse} from 'node:http';

export const titleInstruction = '将用户的问题概括为简短的会话标题';

export function isTitleRequest(body: any): boolean {
  const system = Array.isArray(body?.messages) ? body.messages.find((m: any) => m?.role === 'system')?.content : body?.system;
  const text = typeof system === 'string' ? system : Array.isArray(system) ? system.map((b: any) => b?.text ?? '').join('') : '';
  return text.startsWith(titleInstruction);
}

/** Empty SSE answer: the title job fails quietly and the fallback title stays. */
export function skipTitle(res: ServerResponse): void {
  res.writeHead(200, {'content-type': 'text/event-stream'});
  res.end('data: [DONE]\n\n');
}

/** `isTitleRequest` on a raw request body (non-JSON bodies are not title requests). */
export function isTitleBody(raw: string): boolean {
  try { return isTitleRequest(JSON.parse(raw)); } catch { return false; }
}
