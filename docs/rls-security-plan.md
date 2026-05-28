# RLS セキュリティ設計方針

作成日：2026-05-28
対象：Supabase RLS ポリシーの現状分析と段階的改善計画
状態：設計文書（SQL未実行・ポリシー未変更）

---

## 1. 現在の3アプリ構成

| アプリ | ファイル | 利用者 | 認証方式 |
|---|---|---|---|
| 現場日報 | `index.html` | 現場作業員・管理者 | 従業員PIN（4桁） |
| 原価管理 | `genka-app.html` | 管理者 | genka_admins PIN（4桁） |
| 管理コンソール | `admin-app.html` | 管理者 | genka_admins PIN（4桁） |

すべてのアプリが同一の Supabase プロジェクトを参照し、`anon` キーを使って直接テーブル操作を行っている。

---

## 2. テーブル別操作マトリクス

### index.html（現場日報）

| テーブル | SELECT | INSERT | UPDATE | DELETE/UPSERT |
|---|---|---|---|---|
| `employees` | ○（ログイン一覧・全件） | — | — | — |
| `sites` | ○ | ○ | ○（工期・場所・is_active） | — |
| `site_assignments` | ○ | UPSERT | — | DELETE |
| `materials` | ○ | ○ | ○（is_active） | — |
| `machines` | ○ | ○ | ○（リース情報・is_active） | — |
| `machine_locations` | ○ | ○ | — | — |
| `subcontractors` | ○ | — | — | — |
| `notices` | ○ | — | — | — |
| `reports` | ○（自分分・管理者は全員分） | ○ | ○（未確認分のみ・フロント制御） | — |
| `report_summary` | ○ | — | — | — |
| `paid_leave_requests` | ○（自分分・管理者は全件） | ○ | ○（管理者がstatus更新） | — |
| `paid_leave_grants` | ○ | UPSERT | — | — |
| Storage `photos` | ○（公開URL） | ○（UPLOAD） | — | — |

### genka-app.html（原価管理）

| テーブル | SELECT | INSERT | UPDATE | DELETE/UPSERT |
|---|---|---|---|---|
| `genka_admins` | ○（ログイン一覧） | — | — | — |
| `sites` | ○ | — | — | — |
| `employees` | ○ | — | — | — |
| `employee_rates` | ○ | UPSERT | — | — |
| `unit_rates` | ○ | UPSERT | — | — |
| `machines` | ○ | — | — | — |
| `subcontractors` | ○ | — | — | — |
| `invoices` | ○（status=confirmed/posted のみ） | ○ | ○ | DELETE |
| `site_budgets` | ○ | UPSERT | — | — |
| `report_summary` | ○ | — | — | — |

### admin-app.html（管理コンソール）

| テーブル | SELECT | INSERT | UPDATE | DELETE/UPSERT |
|---|---|---|---|---|
| `genka_admins` | ○ | ○ | ○ | — |
| `employees` | ○ | ○ | ○ | — |
| `companies` | ○ | — | — | — |
| `sites` | ○ | ○ | ○（is_active含む） | — |
| `site_assignments` | ○ | UPSERT | ○（is_active） | — |
| `machines` | ○ | ○ | ○ | — |
| `invoices` | ○（全件） | ○ | ○ | DELETE |
| `employee_rates` | ○ | UPSERT | — | — |
| `unit_rates` | ○ | UPSERT | — | — |
| `site_budgets` | ○ | UPSERT | ○ | DELETE |
| `subcontractors` | ○ | — | — | — |

---

## 3. 現在のRLS上の根本問題

### 3-1. PINログインはフロントエンド認証である

3アプリすべてのログイン処理は JavaScript 上のみで完結している。

```
ブラウザ → Supabase（SELECT employees WHERE id=X AND pin=Y）→ 一致すれば認証成功
```

- この「認証成功」の情報は Supabase 側には伝わらない
- 以降のすべての DB 操作は「未認証ユーザー（anon）」として扱われる
- セッションは `sessionStorage` に JSON を保存しているだけであり、改ざんも可能

### 3-2. Supabase RLS は `auth.uid()` を使えない

Supabase の RLS は `auth.uid()` を基準にアクセス制御を行う設計だが、現在の構成では：

- Supabase Auth を使っていない
- 全リクエストで `auth.uid()` は `NULL`
- 「ログイン済みユーザーのみ」「自分のデータのみ」などのポリシーは機能しない

### 3-3. public（anon）許可が必要になっている

アプリが動作するために、RLS で `anon` ロールへの操作を許可せざるを得ない状況になっている。

これは **「ブラウザから直接テーブルを操作している」** という設計上の制約から来ている。

| 本来あるべき設計 | 現在の設計 |
|---|---|
| ログイン済みユーザーのみ操作可 | anon が全操作 |
| RLS でユーザーを識別 | auth.uid() が常に NULL |
| サーバー側でビジネスロジック検証 | フロントJSのみで制御 |

---

## 4. 危険な仮ポリシー

### 🔴 最危険：`employees_update_public`

- 内容：`anon` ロールに `employees` テーブルへの UPDATE を全行許可
- リスク：ブラウザの DevTools や curl から、任意の従業員の `name` / `pin` / `role` を自由に書き換えられる
- 悪用例：管理者のPINをリセット → 不正ログイン / 一般作業員を管理者に昇格

```sql
-- 悪意ある操作の例（現状これが通ってしまう）
UPDATE employees SET pin = '0000', role = 'admin' WHERE id = '<target_id>';
```

### 🔴 高危険：`employees` / `genka_admins` の PIN 露出

- `employees` テーブルの `pin` カラムが SELECT 可能な状態
- `genka_admins` テーブルの `pin` カラムも同様
- ログイン画面の id 一覧取得（`SELECT id, name FROM employees`）と組み合わせれば、全 PIN の一括取得が可能
- PIN は平文保存されているため、取得=即ログイン可能

### 🟠 高危険：`reports` のなりすまし登録

- 日報の INSERT 時、`employee_id` は JavaScript から渡している
- RLS がないため、任意の `employee_id` で日報を登録できる
- 他人名義の日報を偽造 → 勤怠改ざんに悪用可能

```js
// 現在のコード（index.html）
const payload = {
  employee_id: state.currentUser.id,  // ← JS変数を書き換えれば別人になる
  ...
};
await sb.from('reports').insert(payload);
```

### 🟠 高危険：`paid_leave_requests` のなりすまし申請

- 有給申請の INSERT も `employee_id` を JS から渡している
- 同様に他人名義での有給申請が可能

### 🟡 中危険：`invoices` の INSERT / UPDATE / DELETE

- 財務データへの書き込み・削除が `anon` で可能
- 金額改ざん、業者名偽造、請求書削除が外部から実行できる

### 🟡 中危険：`site_budgets` の DELETE

- admin-app.html では予算の DELETE を直接実行している
- 外部から任意の予算を削除できる

---

## 5. 削除すると壊れる機能（現状の依存関係）

現在の `anon` 許可ポリシーを削除した場合、以下の機能が即時停止する。

| 機能 | 影響アプリ | 依存ポリシー |
|---|---|---|
| 従業員の追加・編集（名前・PIN・会社・役割） | admin-app | employees INSERT/UPDATE |
| 現場の追加・編集・削除フラグ | admin-app, index | sites INSERT/UPDATE |
| 現場配属の変更 | admin-app, index | site_assignments UPSERT/UPDATE/DELETE |
| 重機の追加・設定変更 | admin-app, index | machines INSERT/UPDATE |
| 請求書の登録・編集・削除 | admin-app, genka-app | invoices INSERT/UPDATE/DELETE |
| 日報の提出・修正 | index | reports INSERT/UPDATE |
| 単価設定の保存 | admin-app, genka-app | unit_rates/employee_rates UPSERT |
| 実行予算の設定 | admin-app, genka-app | site_budgets UPSERT/UPDATE |
| 有給申請・承認 | index | paid_leave_requests INSERT/UPDATE |
| 管理者の追加・編集 | admin-app | genka_admins INSERT/UPDATE |

**→ 現時点ではポリシー削除は行わない。段階的に移行する。**

---

## 6. 短期対応案

> 目標：現在の開発環境を壊さずに、リスクを「見える化」する

### 6-1. 現状の仮ポリシーを開発用として明示する

- Supabase のポリシー名に `_dev` / `_temp` サフィックスを追加する
- ポリシーのコメントに「本番前に削除」と明記する
- 例：`employees_update_public` → `employees_update_public_DEV_REMOVE_BEFORE_PROD`

### 6-2. 実データ・本番公開では危険と明記する

- 現状のまま本番公開することは**セキュリティ上許容できない**
- 管理コンソール URL を知られると、財務データの閲覧・改ざんが可能
- 少なくとも Vercel の Password Protection（Pro機能）で URL 保護を検討する

### 6-3. 不要な DELETE から優先的に制限する

削除はデータ消失に直結するため、最も先に制限すべき。

優先候補：
- `invoices` DELETE → `is_deleted` フラグへの UPDATE に変更
- `site_budgets` DELETE → 同様にフラグ化
- `site_assignments` DELETE → `is_active=false` への UPDATE（すでに一部実装済み）

### 6-4. PIN 列を SELECT から除外する（view 作成）

```sql
-- 将来実装する設計（現時点では未実行）
CREATE VIEW employees_safe AS
  SELECT id, name, role, is_active, company_id FROM employees;
```

ログイン一覧表示はこの view を使い、PIN の照合は RPC 経由にする。

---

## 7. 中期対応案

> 目標：管理者系アプリに正規の認証を導入し、RLS を実効化する

### 7-1. Supabase Auth の導入（管理者系アプリ）

- `admin-app.html` と `genka-app.html` のログインを Supabase Auth（email + password または Magic Link）に移行
- 移行後は `auth.uid()` が使えるようになり、RLS が本来の機能を発揮できる

```sql
-- 将来の RLS ポリシー例
CREATE POLICY "admins_only"
  ON invoices FOR ALL
  USING (auth.uid() IN (SELECT auth_id FROM genka_admins));
```

### 7-2. genka_admins / employees の PIN 認証を見直す

- 現在：`SELECT * FROM employees WHERE pin = '1234'`（平文比較・クライアント側）
- 移行案：`CREATE FUNCTION verify_pin(emp_id, pin_hash)` で DB 側で検証
- PIN をハッシュ化（例：`crypt(pin, gen_salt('bf'))` using pgcrypto）して保存

### 7-3. 管理者のみ UPDATE できる RLS への移行

Supabase Auth 導入後：

```sql
-- 将来の設計例
CREATE POLICY "employees_update_admin_only"
  ON employees FOR UPDATE
  USING (
    auth.uid() IN (SELECT auth_id FROM genka_admins WHERE is_active = true)
  );
```

現在の `employees_update_public` はこの時点で削除する。

### 7-4. `reports` への employee_id 強制をサーバー側に寄せる

- INSERT 時に `employee_id` を JS から渡す設計をやめる
- RLS + `auth.uid()` でサーバー側が `employee_id` を決定する

---

## 8. 将来対応案

> 目標：本番グレードのセキュリティ

### 8-1. Edge Functions で重要処理を保護

以下の処理は Edge Function（サーバー側）に移行する：

- 請求書の `status` 変更（uploaded → confirmed → posted）
- 原価計算・集計処理
- 請求書 DELETE（論理削除の強制）
- 有給申請の承認・却下

### 8-2. company_id 単位のアクセス制御

将来的に複数社対応する場合：

```sql
-- company_id ベースの RLS 例
CREATE POLICY "company_isolation"
  ON invoices FOR ALL
  USING (company_id = (SELECT company_id FROM genka_admins WHERE auth_id = auth.uid()));
```

### 8-3. Supabase Vault による機密情報管理

- PIN や API キーなどの機密情報を Vault に移す
- `anon` キーをブラウザに持たせず、Edge Function 経由に限定する

---

## 9. 優先順位とロードマップ

| フェーズ | 内容 | 実施時期 | 現状への影響 |
|---|---|---|---|
| Phase 0 | 設計文書化（本ドキュメント） | 完了 | なし |
| Phase 1 | DELETE系の論理削除化 | 短期 | 最小限のコード変更 |
| Phase 2 | PIN 列の SELECT 分離（view化） | 短期 | ログイン処理の修正が必要 |
| Phase 3 | Supabase Auth 導入（管理者系） | 中期 | 管理系アプリの大規模改修 |
| Phase 4 | 管理者のみの RLS 適用 | 中期 | Phase 3 完了後 |
| Phase 5 | 作業員系 index.html の Auth 対応 | 長期 | UX への影響が大きい |
| Phase 6 | Edge Functions への処理移行 | 長期 | バックエンド設計が必要 |
| Phase 7 | company_id 単位の完全 RLS | 将来 | 多社対応が前提 |

### 実施しない（現時点）
- SQL の変更
- RLS ポリシーの変更・削除
- コードの変更

---

## 補足：現在の Vercel デプロイとセキュリティ境界

- 3アプリはすべて Vercel で静的ファイルとして公開されている
- URL を知っている人間であれば誰でも管理コンソールにアクセスできる状態
- anon キーもソースコードに含まれており、DevTools で取得可能

**→ 本番運用前に、最低でも以下のいずれかを実施すること：**
1. Vercel の Password Protection（Pro プラン）
2. IP アドレス制限（会社 IP のみ許可）
3. Supabase Auth 導入による認証強制

---

*このドキュメントは現状の問題を設計文書として記録するものです。SQL・ポリシー変更は別途タスクとして管理してください。*
