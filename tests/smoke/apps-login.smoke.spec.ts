import { test, expect, type Page } from '@playwright/test';
import { watchConsole } from '../helpers/console';

// 3アプリ（現場日報 / 管理コンソール / 原価管理）のログイン画面が壊れずに開くことだけを確認する。
// 本番DB(*.supabase.co) への通信は route abort で機械的に遮断する（読み取りすら行わない）。
// ログイン後の画面・本番データには一切触れない。

async function blockSupabase(page: Page): Promise<() => number> {
  let blocked = 0;
  await page.route(/.*supabase\.co.*/i, (route) => {
    blocked += 1;
    return route.abort();
  });
  return () => blocked;
}

type AppCase = { name: string; path: string; title: string; loginSel: string };

const APPS: AppCase[] = [
  { name: '現場日報 (index.html)', path: '/index.html', title: '現場日報', loginSel: '#loginScreen' },
  { name: '管理コンソール (admin-app.html)', path: '/admin-app.html', title: '管理コンソール', loginSel: '#loginWrap' },
  { name: '原価管理 (genka-app.html)', path: '/genka-app.html', title: '原価管理ダッシュボード', loginSel: '#loginScreen' },
];

for (const app of APPS) {
  test(`${app.name}: ログイン画面が壊れず開く（本番DB遮断）`, async ({ page }) => {
    const blockedCount = await blockSupabase(page);
    const watcher = watchConsole(page);

    await page.goto(app.path);
    await expect(page).toHaveTitle(app.title);

    // ローディングからログイン画面へ遷移し、表示される（＝画面が崩れていない）
    await expect(page.locator(app.loginSel)).toBeVisible({ timeout: 15_000 });
    // ログインUIの主要要素：PINパッドが表示される
    await expect(page.locator('.pin-key').first()).toBeVisible();

    // 本番DBへの通信は実際に abort された（1件以上）
    expect(blockedCount(), 'Supabaseへの通信がabortされていること').toBeGreaterThan(0);

    // ページ破損を示す重大なConsoleエラー/未捕捉例外がない
    const severe = watcher.severe();
    expect(severe, severe.join('\n')).toEqual([]);
  });
}
