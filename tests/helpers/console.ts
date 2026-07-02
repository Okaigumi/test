import type { Page } from '@playwright/test';

// 読み取り専用スモークでは、意図的に遮断した Supabase(本番DB) 由来のネットワーク失敗など
// 「想定内のノイズ」は無視し、ページ自体の破損を示す重大エラーだけを拾う。
const IGNORE: RegExp[] = [
  /supabase\.co/i,
  /net::ERR_/i,
  /ERR_ABORTED/i,
  /Failed to load resource/i,
  /Failed to fetch/i,
  /the server responded with a status/i,
  /favicon/i,
];

function isIgnorable(text: string): boolean {
  return IGNORE.some((re) => re.test(text));
}

export type ConsoleWatcher = {
  /** これまでに観測した重大エラー（Console error / 未捕捉例外）の一覧 */
  severe: () => string[];
};

export function watchConsole(page: Page): ConsoleWatcher {
  const severe: string[] = [];
  page.on('console', (msg) => {
    if (msg.type() !== 'error') return;
    const text = msg.text();
    if (!isIgnorable(text)) severe.push(`[console.error] ${text}`);
  });
  page.on('pageerror', (err) => {
    const text = String((err && err.message) || err);
    if (!isIgnorable(text)) severe.push(`[pageerror] ${text}`);
  });
  return { severe: () => severe.slice() };
}
