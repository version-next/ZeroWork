/** The user turn's actions (time, copy, rewind, edit) show only while the pointer is over the turn
 *  or focus is inside it (Pencil Kaf7E ⑦, ai_user_message_view.zig). Scripts that click them hover
 *  the turn first. `index` picks the row (default: the last one shown). */
export async function hoverUserRow(h: any, index = -1): Promise<void> {
  const shown = (n: any) => n && n.visible !== false && !n.hidden && n.rect?.w > 0 && n.rect?.h > 0;
  const rows = (await h.query('ai.message.user.row')).filter(shown);
  const row = rows.at(index);
  if (!row) throw new Error('no user turn to hover');
  const bubble = (await h.query('ai.message.user.bubble')).filter(shown).find((b: any) => b.rect.y >= row.rect.y - 0.5 && b.rect.y < row.rect.y + row.rect.h) ?? row;
  // Hover is the native hover of the row: a notification toast lying over the bubble takes the
  // pointer (the row is not hovered under it), so aim at a point of the turn no toast covers.
  const toasts = (await h.query('notifications.viewport')).flatMap((v: any) => v.children || []).filter(shown).map((n: any) => n.rect);
  const covered = (x: number, y: number) => toasts.some((r: any) => x >= r.x && x < r.x + r.w && y >= r.y && y < r.y + r.h);
  const y = bubble.rect.y + bubble.rect.h / 2;
  const points = [bubble.rect.x + bubble.rect.w / 2, bubble.rect.x + 8, row.rect.x + row.rect.w / 2, row.rect.x + 24];
  const x = points.find(px => !covered(px, y)) ?? points[0];
  await h.mouseMove(x, y);
  await h.waitFor(async () => (await h.query('ai.message.timestamp')).some((n: any) => shown(n) && (n.effective_opacity ?? 1) > 0) || null, 5000);
}
