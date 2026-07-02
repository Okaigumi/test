import { defineConfig, devices } from '@playwright/test';

// 読み取り専用・バックエンド非依存のスモーク設定。
// - 本番URLは見ない。リポジトリルートをローカル静的サーバで配信して確認する。
// - *.supabase.co への通信は各テスト側で route abort する（本番DBに一切触れない）。
const PORT = Number(process.env.PORT || 4173);
const BASE_URL = `http://127.0.0.1:${PORT}`;

export default defineConfig({
  testDir: './tests/smoke',
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: 0,
  reporter: 'list',
  use: {
    baseURL: BASE_URL,
    trace: 'on-first-retry',
  },
  projects: [
    { name: 'chromium', use: { ...devices['Desktop Chrome'] } },
  ],
  webServer: {
    command: 'node tests/static-server.mjs',
    url: `${BASE_URL}/index.html`,
    reuseExistingServer: !process.env.CI,
    timeout: 30_000,
    env: { PORT: String(PORT) },
  },
});
