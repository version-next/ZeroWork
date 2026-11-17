/** Public native tab affordances shared by workspace E2E flows. */
import assert from 'node:assert/strict';
import type * as Harness from '../vendor/zenit/e2e/client.ts';

type TabHarness = Pick<typeof Harness, 'query' | 'waitFor' | 'mouseMove' | 'clickAt' | 'clickTestId'>;
const shown = (node: Harness.QueryNode & {hidden?: boolean; effective_opacity?: number}) =>
  node.hidden !== true && node.visible !== false && (node.effective_opacity ?? 1) > 0 &&
  node.rect.w > 0 && node.rect.h > 0;

export async function closeWorkspaceTab(h: Omit<TabHarness, 'clickTestId'>, tabId: string, closeId = tabId.replace('tabs.tab.', 'tabs.close.')) {
  const {rect} = await h.waitFor(async () => (await h.query(tabId)).find(shown) ?? null);
  // The native close action is revealed near the trailing edge on hover.
  await h.mouseMove(rect.x + rect.w - 15, rect.y + rect.h / 2);
  const close = await h.waitFor(async () => (await h.query(closeId)).find(shown) ?? null);
  assert((await h.clickAt(close.rect.x + close.rect.w / 2, close.rect.y + close.rect.h / 2)).ok, closeId);
}

export async function openSessionDetails(h: Pick<TabHarness, 'query' | 'waitFor' | 'clickAt' | 'clickTestId'>, tabId: string) {
  const {rect} = await h.waitFor(async () => (await h.query(tabId)).find(shown) ?? null);
  assert((await h.clickAt(rect.x + rect.w / 2, rect.y + rect.h / 2, 1, 'right')).ok);
  await h.waitFor(async () => (await h.query('context.menu.session_identity')).find(shown) ?? null);
  assert((await h.clickTestId('context.menu.session_identity')).ok);
  return h.waitFor(async () => (await h.query('status.detail')).find(shown) ?? null);
}
