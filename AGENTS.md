# Codexの作業入口

運用の正本は [docs/workflow-rules.md](docs/workflow-rules.md)。作業開始時に全文を確認する。役割・承認・作業手順は同文書第12節、Type 1とmergeの境界は第14節に従う。

## 最初に読む情報

- 本流・進捗・フェーズ：[docs/roadmap.md](docs/roadmap.md)
- DB変更記録：[docs/db-migrations.md](docs/db-migrations.md)
- セキュリティ設計：[docs/rls-security-plan.md](docs/rls-security-plan.md)
- バックアップ方針：[docs/backup-policy.md](docs/backup-policy.md)
- 外部パス付きの現在の利用例：[docs/private-assets-local-usage.md](docs/private-assets-local-usage.md)

このプロジェクトは岡井組の社内業務システム。他プロジェクトの仕様・承認・自動化設定を転用しない。作業先は現在選択された本リポジトリとし、端末別の実パスはGit管理外の運用記録で確認する。

開始時は承認範囲、HEAD・差分・他作業を確認する。岡井はClaudeを唯一の窓口として要望を伝え、仕様・変更範囲・採用・公開を判断して最終承認する。Claudeは要望整理、Codexへの作業依頼、結果の取りまとめ、進捗管理、独立レビュー、岡井への報告・承認依頼を担当する。Codexは承認範囲内の調査・実装・テスト・自己点検・証拠作成・指摘修正と、承認されたGit／PR／公開操作を実行し、結果をClaude窓口へ返す。Claudeが自ら修正した部分は別のClaudeセッションまたは編集しないClaudeレビュー担当が確認する。Codexの自己点検やsubagentレビュー、Claudeの窓口業務や状態所見で独立レビューを代替しない。独立レビュー未実施、必要な修正・再確認が未完了、レビュー済み内容とpush対象を照合できない、またはPR作成後にレビュー対象とPR対象HEADを照合できない場合は、Previewを生むpush・merge・公開へ進まない。Previewは本番公開ではないが外部へのデプロイとして扱い、push承認には自動Preview作成を明記する。対象限定の有効な明示承認は工程ごとに再要求しないが、独立レビューや検証は省略しない。既存の未コミット変更を保全し、機密保管先を通常作業フォルダへ含めない。Claudeへのレビュー依頼は [CLAUDE.md](CLAUDE.md) を入口とする。
