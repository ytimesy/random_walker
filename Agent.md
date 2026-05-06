# Agent.md

このドキュメントは、Random Walker を自律的に開発するエージェント向けの作業指針です。
エージェントは、ここに書かれた方針を優先し、既存の設計・テスト・README と矛盾しない範囲で実装を進めてください。

## プロダクトの目的

Random Walker は、Web 上のリンクをランダムまたは半自動でたどり、発見したページをブラウザ内に保存・整理・エクスポートできる Rails アプリです。

重要な性質:

- Rails 7.2 系の小規模アプリケーション。
- サーバーサイド DB を前提にしない local-first 設計。
- 訪問履歴、保存済み trail、research topic はブラウザの localStorage に保存する。
- サーバー側は URL 遷移候補の抽出、安全判定、プレビュー HTML の取得を担当する。
- Render Blueprint でのデプロイを想定する。

## 開発の基本方針

- 既存の構成を尊重し、Rails 標準・現行のサービスクラス・vanilla JavaScript・Sprockets CSS の範囲で実装する。
- 新しい gem、DB、ビルドツール、フロントエンドフレームワークは、明確な必要性がある場合だけ追加する。
- ユーザー体験は「かわいさ」と「研究用途の実用性」の両方を保つ。ただし装飾よりも、実際に歩ける・保存できる・再開できる・書き出せることを優先する。
- local-first を維持する。アカウント、課金、サーバー同期、個人データ保存は追加しない。
- 外部 URL を扱う変更では、安全性・タイムアウト・リダイレクト・CSP・sandbox の影響を必ず確認する。

## 主要ファイル

- `app/controllers/walks_controller.rb`: `/walk` JSON API と `/walk/preview` HTML プレビュー。
- `app/services/random_walker/link_picker.rb`: リンク抽出、候補順位付け、遷移先プレビュー情報の取得。
- `app/services/random_walker/page_frame.rb`: 埋め込み用 HTML の取得と安全な整形。
- `app/services/random_walker/url_safety_checker.rb`: URL の安全判定。
- `app/views/pages/home.html.erb`: メイン UI。
- `app/javascript/application.js`: trail、research report、localStorage、UI 状態管理。
- `app/assets/stylesheets/application.css`: アプリ全体の見た目。
- `config/initializers/random_walker.rb`: 初期 URL、許可ホスト、問い合わせ先、レート制限。
- `test/services/random_walker/*_test.rb`: サービス層の重要な振る舞い。
- `test/controllers/walks_controller_test.rb`: API とプレビューの統合テスト。

## 実装判断

自律的に作業するときは、次の順で判断してください。

1. README とこのファイルに書かれた product boundary を確認する。
2. 既存のテストで守られている振る舞いを確認する。
3. 変更対象に一番近い既存コードの書き方に合わせる。
4. 小さく実装し、必要なテストを追加する。
5. `bin/rails test` を実行し、必要なら対象テストも個別に実行する。
6. UI を触る変更では、HTML/CSS/JS の連携とモバイル幅での破綻を確認する。

不明点があっても、既存方針から安全に推測できる場合は作業を進めてください。
ただし、次の変更はユーザー確認なしに進めないでください。

- DB 導入、ユーザーアカウント導入、サーバー保存への転換。
- 課金、広告、トラッキング、分析 SDK の追加。
- 外部 API キーや秘密情報を必要とする機能。
- Render 以外を前提にしたデプロイ構成の大幅変更。
- localStorage の既存データ形式を破壊する変更。

## セキュリティと外部 URL

このアプリは任意の外部ページへアクセスするため、安全面の退行を特に避けてください。

- HTTP/HTTPS 以外の URL scheme は受け付けない。
- IP アドレス host、疑わしい TLD、allowlist 違反は `UrlSafetyChecker` の方針に従ってブロックする。
- リダイレクト先も安全判定する。
- 外部取得は短い timeout を維持する。
- プレビュー iframe は sandbox と CSP を維持する。
- 取得した HTML をそのまま信頼しない。必要な整形・無効化・リンク外部化を `PageFrame` で行う。
- allowlist は `RANDOM_WALKER_ALLOWED_HOSTS` で任意に制限できる状態を保つ。

## フロントエンド方針

- UI は現在の単一ページ体験を基本にする。
- 状態はできるだけ `app/javascript/application.js` 内の既存構造に沿って管理する。
- localStorage key は既存 key を壊さない。
- JSON import/export は後方互換を意識し、欠損値に強くする。
- 操作ボタンは disabled、aria 属性、status message を適切に更新する。
- URL や長いタイトルは折り返し、レイアウトを押し広げない。
- 大きな見た目の変更では `application.css` のカラートーン、8px radius、コンパクトな3カラム構成を尊重する。

## テスト方針

変更に応じて、次の粒度でテストを追加または更新してください。

- リンク選択、順位付け、安全判定、メタデータ抽出: `test/services/random_walker/link_picker_test.rb`
- URL 安全性: `test/services/random_walker/url_safety_checker_test.rb`
- プレビュー HTML 生成: `test/services/random_walker/page_frame_test.rb`
- controller の JSON・エラー・rate limit・preview response: `test/controllers/walks_controller_test.rb`

標準確認コマンド:

```bash
bin/rails test
```

静的解析を行う場合:

```bash
bin/rubocop
bin/brakeman
```

## 環境変数

- `RANDOM_WALKER_INITIAL_URL`: 初期表示・初回 walk の URL。未指定時は `https://qiita.com/`。
- `RANDOM_WALKER_ALLOWED_HOSTS`: カンマ区切りの許可 host。空なら allowlist 制限なし。
- `RANDOM_WALKER_CONTACT_EMAIL`: 公開問い合わせ先。
- `RANDOM_WALKER_RATE_LIMIT_WINDOW`: rate limit window 秒数。
- `RANDOM_WALKER_RATE_LIMIT_REQUESTS`: window 内の許可 request 数。
- `RAILS_SERVE_STATIC_FILES`: production で静的ファイルを配信する場合に使用。
- `SECRET_KEY_BASE`: production で必要。Render Blueprint では生成される。

## デプロイ方針

- Render Blueprint は `render.yaml` を使う。
- build は `bin/render-build`、start は `bin/render-start` を使う。
- `/up` は Rails health endpoint として維持する。
- production でもサーバーサイド DB を必須にしない。

## 完了条件

自律開発の各タスクは、原則として次を満たしたら完了とします。

- 要求された振る舞いが実装されている。
- 既存の product boundary を破っていない。
- 関連テストが追加または更新されている。
- `bin/rails test` が通る、または実行できなかった理由が明確に記録されている。
- README、Agent.md、環境変数説明など、利用者や将来のエージェントに影響するドキュメントが必要に応じて更新されている。

## 作業ログの残し方

作業完了時は、次を簡潔に報告してください。

- 変更した主なファイル。
- 追加・変更した振る舞い。
- 実行したテストと結果。
- 未解決の制約や次に見るべき点。
