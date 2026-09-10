# Codexの作業入口

運用の正本は [docs/workflow-rules.md](docs/workflow-rules.md)。作業開始時に全文を確認する。役割・承認・作業手順は同文書第12節、Type 1とmergeの境界は第14節に従う。

## 最初に読む情報

- 本流・進捗・フェーズ：[docs/roadmap.md](docs/roadmap.md)
- DB変更記録：[docs/db-migrations.md](docs/db-migrations.md)
- セキュリティ設計：[docs/rls-security-plan.md](docs/rls-security-plan.md)
- バックアップ方針：[docs/backup-policy.md](docs/backup-policy.md)
- 外部パス付きの現在の利用例：[docs/private-assets-local-usage.md](docs/private-assets-local-usage.md)

このプロジェクトは岡井組の社内業務システム。他プロジェクトの仕様・承認・自動化設定を転用しない。作業先は現在選択された本リポジトリとし、端末別の実パスはGit管理外の運用記録で確認する。

開始時は承認範囲、HEAD・差分・他作業を確認する。Codexは正本に沿って調査から自己点検・記録まで担当し、既存の未コミット変更を保全する。機密保管先を通常作業フォルダへ含めない。Claudeへ限定レビューを依頼するときは [CLAUDE.md](CLAUDE.md) を入口とする。
