# 請求書PDF管理・AI/OCR自動振り分け 設計文書

作成日：2026-05-28  
対象ファイル：admin-app.html（現行）、genka-app.html（現行）、index.html（変更なし）

---

## 1. 現在の実装との差分

### 1-1. 現在の invoices テーブル（コードから推定）

| カラム | 型 | 現状 |
|---|---|---|
| id | uuid | あり |
| invoice_date | date | あり |
| vendor_name | text | あり（自由入力、FK なし） |
| amount | integer | あり |
| site_id | uuid | あり（nullable） |
| category | text | あり（subcontract/material/machine_lease/other） |
| tax_included | boolean | あり |
| description | text | あり |
| memo | text | あり |
| company_id | uuid | あり（Step 6 で追加） |
| **status** | text | **なし** |
| **file_path** | text | **なし** |
| **original_file_name** | text | **なし** |
| **vendor_id** | uuid | **なし**（vendor_name が自由入力のまま） |
| **invoice_number** | text | **なし** |
| **tax_amount** | integer | **なし** |
| **due_date** | date | **なし** |
| **confirmed_at** | timestamptz | **なし** |
| **posted_at** | timestamptz | **なし** |

### 1-2. 現行の問題点

**A. genka-app.html が全請求書を無条件に原価へ反映している**
- `loadData()` 内で `sb.from('invoices').select('*').gte('invoice_date',from)` と取得し、
  status の確認なしに全件を原価集計に加算している
- AI/OCR 導入後、uploaded/suggested 状態の未確認データも原価に混入するリスクがある

**B. vendor_name が自由入力テキスト**
- 同一業者でも表記揺れが発生する（「岡井重機」「岡井重機㈱」など）
- vendors テーブルへの正規化が必要

**C. PDF 証憑管理機能がない**
- ファイルアップロード機能なし
- Supabase Storage バケットなし

**D. invoice_items（明細）がない**
- 請求書 1 件につき 1 レコードの構造
- 複数現場・複数費目にまたがる請求書を分割できない

**E. 費目（cost_categories）が hardcode**
- subcontract/material/machine_lease/other の 4 種が文字列のみで管理されている
- 将来的な費目追加・変更に対応できない

---

## 2. 必要なテーブル設計案

### 2-1. vendors（取引先マスタ）

```sql
create table vendors (
  id                      uuid primary key default gen_random_uuid(),
  vendor_name             text not null,
  vendor_name_kana        text,
  invoice_registration_number text,          -- インボイス登録番号（T+13桁）
  default_cost_category_id uuid references cost_categories(id),
  default_payment_terms   integer,           -- 支払サイト（日数）
  memo                    text,
  is_active               boolean not null default true,
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now()
);
```

### 2-2. cost_categories（費目マスタ）

```sql
create table cost_categories (
  id         uuid primary key default gen_random_uuid(),
  name       text not null,                  -- 例：外注費、材料費、重機リース
  sort_order integer not null default 0,
  is_active  boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
```

初期データ（既存 category 値との対応）:

| 旧 category 値 | 新 name |
|---|---|
| subcontract | 外注費 |
| material | 材料費 |
| machine_lease | 重機リース |
| other | その他 |

### 2-3. invoices（請求書本体）— 変更後

```sql
-- 既存カラムは維持、以下を追加
alter table invoices
  add column if not exists status            text not null default 'confirmed',
  add column if not exists file_path         text,
  add column if not exists original_file_name text,
  add column if not exists vendor_id         uuid references vendors(id),
  add column if not exists invoice_number    text,
  add column if not exists tax_amount        integer,
  add column if not exists due_date          date,
  add column if not exists confirmed_at      timestamptz,
  add column if not exists posted_at         timestamptz;
```

ステータス遷移:

```
uploaded → (AI処理後) extracted → suggested → confirmed → posted
                                                        ↘ rejected
```

| status | 意味 | genka-app.html への反映 |
|---|---|---|
| uploaded | PDF アップロード済み、未処理 | **しない** |
| extracted | AI がテキスト抽出済み | **しない** |
| suggested | AI が候補データを提案済み | **しない** |
| confirmed | 人間が内容を確認・確定済み | **する**（Phase 2 以降） |
| posted | 原価管理へ反映済み（二重反映禁止） | する（明示的 posted のみ） |
| rejected | 差し戻し・却下 | **しない** |

**重要：現在の既存データは status='confirmed' として扱う（移行時の初期値）**

### 2-4. invoice_items（請求書明細）

```sql
create table invoice_items (
  id                uuid primary key default gen_random_uuid(),
  invoice_id        uuid not null references invoices(id) on delete cascade,
  description       text,
  quantity          numeric,
  unit              text,
  unit_price        integer,
  amount            integer not null,
  tax_rate          numeric,                 -- 0.10 or 0.08
  tax_amount        integer,
  site_id           uuid references sites(id),
  cost_category_id  uuid references cost_categories(id),
  memo              text,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);
```

### 2-5. invoice_ai_extractions（AI/OCR 抽出結果）

```sql
create table invoice_ai_extractions (
  id             uuid primary key default gen_random_uuid(),
  invoice_id     uuid not null references invoices(id) on delete cascade,
  raw_text       text,                       -- OCR で抽出した生テキスト
  extracted_json jsonb,                      -- AI が解釈した構造化データ（候補）
  confidence     numeric,                    -- 信頼スコア 0.0〜1.0
  model_name     text,                       -- 使用した AI モデル名
  created_at     timestamptz not null default now()
);
```

`extracted_json` の想定スキーマ（あくまで候補、確定前）:

```json
{
  "vendor_name": "岡井重機",
  "invoice_date": "2026-05-15",
  "invoice_number": "岡-2026-0512",
  "total_amount": 330000,
  "tax_amount": 30000,
  "due_date": "2026-06-30",
  "items": [
    {
      "description": "バックホウ回送費",
      "quantity": 1,
      "unit": "式",
      "unit_price": 300000,
      "amount": 300000,
      "tax_rate": 0.10,
      "site_name_hint": "〇〇ビル3F"
    }
  ]
}
```

---

## 3. 既存 invoices テーブルの移行方針

### 方針の原則
- 既存データを削除しない
- 既存の admin-app.html / genka-app.html の動作を即座に壊さない
- カラム追加は ALTER TABLE で段階的に行う

### Phase 1 マイグレーション（SQL）

```sql
-- 1. cost_categories を先に作成
create table if not exists cost_categories (...);
insert into cost_categories (name, sort_order) values
  ('外注費', 1), ('材料費', 2), ('重機リース', 3), ('その他', 4);

-- 2. vendors テーブルを作成
create table if not exists vendors (...);

-- 3. invoices に status を追加（既存データは confirmed として扱う）
alter table invoices
  add column if not exists status text not null default 'confirmed';

-- 4. 以降のカラムは null 許容で追加（既存レコードに影響なし）
alter table invoices
  add column if not exists file_path          text,
  add column if not exists original_file_name text,
  add column if not exists vendor_id          uuid references vendors(id),
  add column if not exists invoice_number     text,
  add column if not exists tax_amount         integer,
  add column if not exists due_date           date,
  add column if not exists confirmed_at       timestamptz,
  add column if not exists posted_at          timestamptz;

-- 5. 既存の vendor_name から vendors マスタを生成（重複排除）
insert into vendors (vendor_name)
  select distinct vendor_name from invoices
  where vendor_name is not null
  on conflict do nothing;

-- ※ vendor_id の紐付けは画面上で順次行う（一括 UPDATE はしない）
```

### 移行後の過渡期の動作
- `vendor_id` は null 許容なので既存の `vendor_name` テキストはそのまま残る
- `status='confirmed'` のため genka-app.html は変更なしでも動作する
- Phase 2 以降で genka-app.html を `status IN ('confirmed','posted')` 限定にする

---

## 4. Supabase Storage 保存設計案

### バケット構成

```
bucket: invoice-pdfs  （非公開バケット、RLS で管理者のみアクセス可）
```

### ディレクトリ構造（実ファイル）

```
invoice-pdfs/
  uploads/
    invoices/
      2026/
        05/
          20260528_143022_a3f7b2c1-4d8e-4f9a-b1c2-d3e4f5a6b7c8.pdf
          20260528_151045_7e2a9d6c-3b1f-4a8e-9c0d-e1f2a3b4c5d6.pdf
        06/
          ...
```

### ファイル命名規則

```
{YYYYMMDD}_{HHmmss}_{uuid}.pdf
```

- `YYYYMMDD_HHmmss` は アップロード日時（JST）
- `uuid` は `gen_random_uuid()` で生成
- 元ファイル名は `invoices.original_file_name` にのみ保存
- ディレクトリに業者名・現場名・ステータスは含めない

### DB との対応

```
invoices.file_path = 'uploads/invoices/2026/05/20260528_143022_xxx.pdf'
invoices.original_file_name = '岡井重機_2026年5月請求書.pdf'
```

### 画面上での表示分類

- 実ファイルは年月別保存（フォルダ移動不要）
- 管理画面上では `vendor_id` / `vendors.vendor_name` でフィルタリングして「業者別」に見せる
- フォルダ出力が必要な場合は将来エクスポート機能で対応

---

## 5. 画面設計案

### 5-1. 請求書一覧（admin-app.html）

**追加予定の列:**

| 日付 | 業者名 | 会社 | 現場 | カテゴリ | 金額 | **ステータス** | **PDF** | 操作 |
|---|---|---|---|---|---|---|---|---|

**ステータスバッジ:**
- `uploaded` → グレー「未処理」
- `confirmed` → グリーン「確認済」
- `posted` → ブルー「反映済」
- `rejected` → レッド「却下」

**フィルタ追加（タブ or セレクト）:**
- 全件 / 未処理 / 確認済 / 反映済 / 却下

### 5-2. 請求書登録フロー（将来）

```
① PDF アップロード
    → file_path 生成・Storage 保存
    → invoices レコード作成（status='uploaded'）

② AI/OCR 処理（将来追加）
    → invoice_ai_extractions レコード作成
    → invoices.status を 'suggested' に更新

③ 人間が確認・修正
    → openInvoiceModal() で候補データを表示
    → 内容を編集して「確認する」ボタン押下
    → invoices.status を 'confirmed' に更新、confirmed_at を記録

④ 原価反映
    → 「原価に反映する」ボタン押下（confirmed のみ有効）
    → invoices.status を 'posted' に更新、posted_at を記録
    → genka-app.html はこの posted データを原価として参照
```

### 5-3. 確認モーダル（将来）

```
[ AI 読取結果（参考） ]    [ 確定値（編集可） ]
  業者名: 岡井重機           業者名: [select: vendors]
  日付:   2026-05-15         日付:   [input]
  金額:   ¥330,000           金額:   [input]
  -------                    -------
  明細1: バックホウ回送      現場: [select]
         ¥300,000             費目: [select]

[ 却下 ]  [ 確認済みにする → ]
```

---

## 6. 原価管理との連携設計案

### 現在の問題

`genka-app.html` の `loadData()` では:
```js
let invQ = sb.from('invoices').select('*').gte('invoice_date', from).lte('invoice_date', to);
```
status に関係なく全件取得し、原価に加算している。

### Phase 2 以降の変更方針

**変更箇所:** `genka-app.html` の `loadData()` 内の invoices クエリ

```js
// 変更前
let invQ = sb.from('invoices').select('*')
  .gte('invoice_date', from).lte('invoice_date', to);

// 変更後（status が confirmed または posted のもののみ）
let invQ = sb.from('invoices').select('*')
  .gte('invoice_date', from).lte('invoice_date', to)
  .in('status', ['confirmed', 'posted']);
```

**この変更を Phase 2 以降にする理由:**
- Phase 1 では既存データの status が全て 'confirmed' のため、変更しても動作は同じ
- ただし PDF アップロード機能（uploaded/suggested 状態）を追加する前に変更しておく必要がある
- 変更タイミング：PDF アップロード機能を実装する直前

### posted の二重反映防止

```js
// saveInvoice() または専用の postInvoice() で実施
// posted_at が既にセットされていれば上書き禁止
if (inv.posted_at) {
  alert('この請求書はすでに原価反映済みです');
  return;
}
// status='confirmed' の場合のみ posted に変更可
if (inv.status !== 'confirmed') {
  alert('確認済みの請求書のみ原価反映できます');
  return;
}
```

---

## 7. AI/OCR 拡張ポイント

### 拡張方法

AI/OCR は `invoice_ai_extractions` テーブルと `status='suggested'` を通じて既存コードに影響を与えずに追加できる。

```
invoices テーブル
  └ status: 'uploaded' → AI 処理 → 'suggested'
  └ invoice_ai_extractions: raw_text, extracted_json, confidence

人間の確認 UI（候補表示）
  └ extracted_json の値を openInvoiceModal() に初期値として渡す
  └ 人間が確認・修正して保存 → status='confirmed'
```

### AI 処理の実装候補

| 方法 | 特徴 |
|---|---|
| Supabase Edge Functions | PDF を受け取り OCR API を呼ぶ。ファイルアップロード直後に非同期実行 |
| Google Cloud Vision API | 日本語 OCR 精度が高い |
| Claude API（claude-haiku-4-5） | 構造化抽出（JSON レスポンス）に強い。OCR 結果のパース用途 |
| AWS Textract | 請求書レイアウト解析に特化したマネージドサービス |

### 拡張時の設計原則（変更してはいけないもの）

- AI の `extracted_json` は **候補** であり、`invoices` テーブルの確定フィールドに直接書かない
- `invoice_ai_extractions` レコードは削除せず、監査ログとして保持する
- status が `suggested` のデータは genka-app.html の原価に**含めない**

---

## 8. 段階的な実装ステップ

### Phase 1：テーブル拡張（現行機能を壊さない）

- [ ] `cost_categories` テーブルを作成し初期データを投入
- [ ] `vendors` テーブルを作成
- [ ] `invoices` に `status='confirmed'` デフォルトで追加
- [ ] `invoices` に `file_path`, `original_file_name`, `vendor_id`, `invoice_number`, `tax_amount`, `due_date`, `confirmed_at`, `posted_at` を null 許容で追加
- [ ] `invoice_items` テーブルを作成
- [ ] RLS ポリシーを追加

### Phase 2：admin-app.html の UI 拡張

- [ ] 請求書一覧に `status` バッジ列を追加
- [ ] 請求書一覧にフィルタ（全件/未処理/確認済/反映済）を追加
- [ ] 請求書フォームに `vendors` セレクトを追加（既存 `vendor_name` との共存）
- [ ] 「確認済みにする」ボタン追加（`status='confirmed'`）
- [ ] 「原価反映する」ボタン追加（`confirmed` → `posted`、二重防止）
- [ ] genka-app.html の invoices クエリを `status IN ('confirmed','posted')` に変更

### Phase 3：PDF アップロード機能

- [ ] Supabase Storage バケット `invoice-pdfs` を作成（非公開）
- [ ] admin-app.html に PDF アップロード UI を追加
- [ ] ファイル名生成ロジック（日時+uuid）を実装
- [ ] アップロード後に `invoices` レコード作成（`status='uploaded'`）
- [ ] PDF プレビュー（inline 表示 or 新タブ）

### Phase 4：AI/OCR 自動抽出（将来）

- [ ] Supabase Edge Functions を設定
- [ ] OCR API 連携（Google Vision API 等）
- [ ] `invoice_ai_extractions` レコード作成
- [ ] admin-app.html に候補確認 UI を追加（AI 結果と確定値の並列表示）
- [ ] 候補から確認済みへの変換フロー実装

---

## 補足：変更しないファイル・テーブル

- `index.html` — 変更なし（invoices テーブルを参照しない）
- `sites`, `employees`, `machines`, `companies` テーブル — 構造変更なし
- 既存の `invoice_date`, `vendor_name`, `amount`, `site_id`, `category`, `tax_included`, `description`, `memo`, `company_id` カラム — 削除・変更なし

---

*このドキュメントは設計文書です。実装前に各 Phase を個別に確認・承認してから進めてください。*
