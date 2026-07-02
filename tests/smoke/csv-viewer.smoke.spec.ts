import { test, expect } from '@playwright/test';
import { watchConsole } from '../helpers/console';
import { buildPaidLeaveZip } from '../helpers/zip';

// CSVビューア（local-viewers/csv-viewer.html）は完全ローカル・Supabase非依存。
// 合成6CSV ZIP を読み込ませ、月次帳票と有休表示が崩れず描画されることを確認する。
// 保存・削除・登録などの書き込み操作は一切行わない（読み取り表示のみ）。

test.describe('CSVビューア（完全ローカル・バックエンド非依存）', () => {
  test('6CSV ZIPを読み込み、月次帳票と有休表示が崩れず描画される', async ({ page }) => {
    const watcher = watchConsole(page);
    // csv-viewer は元々 Supabase を使わないが、念のため通信ゼロを保証する
    let external = 0;
    await page.route(/.*supabase\.co.*/i, (route) => {
      external += 1;
      return route.abort();
    });

    await page.goto('/local-viewers/csv-viewer.html');
    await expect(page).toHaveTitle('帳票確認');

    // 合成6CSVからZIPを生成して読み込ませる（バイナリZIPはコミットしない）
    const zip = await buildPaidLeaveZip();
    await page.locator('#multiZipInput').setInputFiles({
      name: 'test-package-2099-01.zip',
      mimeType: 'application/zip',
      buffer: zip,
    });

    // 読込成功
    await expect(page.locator('#multiZipStatus')).toContainText('読み込みました', { timeout: 15_000 });

    // 帳票選択メニュー →「日報・労務費」カードの「開く」
    const attendanceCard = page.locator('.menu-card', { hasText: '日報・労務費' });
    await expect(attendanceCard).toBeVisible();
    await attendanceCard.getByRole('button', { name: '開く' }).click();

    // 「社内確認用 月次稼働・日報詳細」ページへ
    await page.locator('.nav-btn[data-page="monthlyReport"]').click();
    const mrpt = page.locator('#mrptArea');
    await expect(mrpt.locator('.mrpt-title')).toHaveText('社内確認用 月次稼働・日報詳細');
    // 全員選択時は有休・残有給を出さない
    await expect(mrpt).not.toContainText('残有給');

    // 従業員（テスト太郎）を選択 → 残有給が表示される（balances あり：15 日）
    await page.locator('#mrptEmpButtons').getByRole('button', { name: 'テスト太郎' }).click();
    await expect(mrpt).toContainText('残有給：15 日');
    // 月間稼働カレンダーが描画される
    await expect(mrpt).toContainText('1. 月間稼働カレンダー');
    // 有休（full/am/pm）が当月カレンダーに表示される
    await expect(mrpt.locator('.mrpt-cal-leave').first()).toBeVisible();

    // balances に無い従業員（テスト次郎）は「—（データなし）」表示
    await page.locator('#mrptEmpButtons').getByRole('button', { name: 'テスト次郎' }).click();
    await expect(mrpt).toContainText('残有給：—（データなし）');

    // csv-viewer は外部/本番DBへ一切通信しない
    expect(external, 'csv-viewer は Supabase へ通信しない').toBe(0);

    // ページ破損を示す重大なConsoleエラーがない
    const severe = watcher.severe();
    expect(severe, severe.join('\n')).toEqual([]);
  });
});
