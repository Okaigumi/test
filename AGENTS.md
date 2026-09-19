# Codexの作業入口

運用の正本は [docs/workflow-rules.md](docs/workflow-rules.md)。作業開始時に全文を読む。第12節の移行条件・役割・承認・レビューと、第14節のType 1・公開条件に従う。移行中は旧レビュー条件を維持し、文書の配置だけで新体制を有効と扱わない。

## 開始・再開時

1. [現在の本流](docs/roadmap.md)、対応する `docs/tasks/` の作業記録、合格条件、承認の出所を読む。
2. 実物の作業先・branch・HEAD・stage・未追跡を含む差分・競合作業を照合する。
3. 過去の決定・固定した合格条件・前作業IDからの累積試行回数・結果不明の操作を引き継ぐ。承認の出所を確認し、次の許可された行動を定める。
4. [反復・再開手順](docs/loop-workflow.md) と [作業記録テンプレート](docs/tasks/TEMPLATE.md) を必要箇所で使う。

岡井さんの窓口は移行成立後のCodexとする。Codexは要望整理・実装・検証・記録・必要な別担当レビューの調整と承認済み操作を担当する。編集担当は原則1人。自分の自己点検を別担当レビューと呼ばない。非関与の条件と証跡は正本第12節で確認し、履歴を継承した子担当を別担当レビューと数えない。区分Hは非関与Claudeの追加レビューを必要とする。Claudeへの依頼は [CLAUDE.md](CLAUDE.md) を入口とする。

承認済み範囲の工程切替では同じ承認を取り直さない。Git変更・公開・DB・保護設定の境界は正本に従う。実効の権限を確認せず、自動実行・read-only・停止保証を宣言しない。文書案は実行器ではない。

## 対象に応じて読む情報

- DB：[docs/db-migrations.md](docs/db-migrations.md)
- セキュリティ：[docs/rls-security-plan.md](docs/rls-security-plan.md)
- バックアップ：[docs/backup-policy.md](docs/backup-policy.md)
- 機密資産：[docs/private-assets-local-usage.md](docs/private-assets-local-usage.md)

本リポジトリは岡井組の社内業務システム。他プロジェクトの承認・設定を転用しない。端末固有の実パスや秘密情報はGit管理外の承認済み記録で確認する。既存の未コミット差分を保全する。
