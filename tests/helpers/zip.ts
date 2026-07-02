import { createRequire } from 'node:module';
import { readFile, readdir } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

// アプリ本体と同じ vendored JSZip を Node 側で再利用してZIPを生成する。
// → 生成物が csv-viewer の JSZip.loadAsync と確実に互換。追加依存も不要。
const require = createRequire(import.meta.url);
const JSZip = require('../../vendor/jszip/jszip.min.js');

const __dirname = dirname(fileURLToPath(import.meta.url));
const PKG_DIR = join(__dirname, '..', 'fixtures', 'paid-leave-package');

// 合成6CSV + manifest.json（すべて架空データ）から、管理コンソール出力ZIP相当を生成する。
// バイナリZIPはコミットせず、テスト実行時に毎回このヘルパーで組み立てる。
export async function buildPaidLeaveZip(): Promise<Buffer> {
  const zip = new JSZip();
  const names = (await readdir(PKG_DIR)).sort();
  for (const name of names) {
    const buf = await readFile(join(PKG_DIR, name));
    zip.file(name, buf);
  }
  return zip.generateAsync({ type: 'nodebuffer' }) as Promise<Buffer>;
}
