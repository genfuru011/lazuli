# Lazuli TODO List

## 直近（2025-12-17）

- [x] **Turbo Streams: Ruby API をさらに短く（体験改善・最優先）**
  - [x] `target:`/`targets:` の省略記法を最終整理（id/selector判定 + Symbol/Array対応）
  - [x] 最短パターン（`stream { ... }` / `stream_or(...) { ... }`）を example / generator に固定
  - [x] 受け入れ基準（READMEの最小例）がそのままコピペで動くことを確認
- [x] **Islands: hydration 自動化（MVP）**
  - [x] Islandマーカー検出 → hydration runtime をHEADへ自動注入（1ページ1回）
- [x] **DB: 最小Migration + Repository base**
  - [x] マイグレーション実行（`lazuli db create` / `lazuli db rollback`）
  - [x] `Lazuli::Repository` ベース（SQLite open の最小セット）

## 優先度: 高 (Core Features)

- [x] **CLIツールの実装 (`lazuli` コマンド)**
    - [x] `lazuli new <project_name>`: 新規プロジェクトの作成
    - [x] `lazuli dev`: RubyサーバーとDenoサーバーを同時に起動するコマンド（簡易ホットリロード付き）
    - [x] `lazuli generate resource <name>`: Resource, Struct, Pageの雛形生成
- [x] **ホットリロード (Hot Reload) の実装**
    - [x] Ruby/TSXファイルの変更検知とサーバー再起動（簡易ウォッチャ）
    - [x] TSXファイルの変更検知とブラウザリロード (Live Reload) ※ポーリングによる簡易版
- [x] **TypeScript型定義の自動生成**
    - [x] `Lazuli::Struct` から `client.d.ts` を生成する機能（`lazuli types`）
    - [x] Struct変更検知→自動生成（`lazuli dev --reload` の再起動時に追従）
- [x] **Live Reload の高度化**
    - [x] EventSource (SSE) での通知（ポーリング廃止）
    - [x] ファイル変更をサーバープロセス再起動なしでpushする（Deno/Rubyのwatch統合）
- [x] **TypeGenerator の精緻化**
    - [x] Array/Optional/Struct参照の型推論強化
    - [x] Union型（非配列含む）の正確化（`Lazuli::Types.any_of` 等）
    - [x] 型の重複出力回避とテスト追加
    - [x] 名前衝突ガード（例: `Admin::User` と `User`）
- [x] **次の実装順（提案）**
    - [x] 1) ルーティング/params（path params + 404/405）
    - [x] 2) Resource RPC メタデータ保持（`Resource.rpc`）
    - [x] 3) Turbo Streams MVP（最小API + example）

- [x] **ルーティング/params の改善**
    - [x] `/users/123` の `123` を `params[:id]` に渡す（path params）
    - [x] 405時にAllowヘッダを返す
- [x] **Resource RPC メタデータの整備**
    - [x] `Resource.rpc` で定義を保持（name/returns/params など）
    - [x] `lazuli types` で `RpcRequests`/`RpcResponses` と typed RPC client (`client.rpc.ts`) を生成
    - [x] `POST /__lazuli/rpc` を追加（allowlist: `Resource.rpc` 定義済みのみ）
    - [x] RPC key の安定化（デフォルト: path-like key `users#method`。旧 `UsersResource#method` もサーバ側で受理）
    - [x] `rpc :name, params:` の入力スキーマ検証（最小）
    - [x] CSRF/Origin 対策（最小: Origin一致チェック）

- [x] **Deno adapter テスト整備**
    - [x] `/render_turbo_stream` の最小Denoテスト（invalid fragment / targets remove）
    - [x] `/render` の最小SSRテスト
    - [x] CIで `deno test` を回す（setup-deno）

- [x] **ServerRunner 改善**
    - [x] ウォッチ対象に config/deno.json を含める
    - [x] 終了時にDeno/Rackを停止しソケットをクリーンアップ（基本）
    - [x] プロセスグループ/子プロセス含む完全停止（pgid kill + at_exit cleanup）
    - [x] ログ簡素化・リトライ制御（LAZULI_QUIET/LAZULI_DEBUG、socket-ready待ち + retry）
- [x] **プロセスモデルの整理（App/ServerRunner）**
    - [x] 方針: Deno管理は `Lazuli::ServerRunner`（CLI）に集約し、`Lazuli::App` はRackアプリとして純粋に保つ
    - [x] 決定: `bundle exec rackup` / `lazuli server` は **Rackのみ**（Deno spawn はしない）。Deno renderer は別プロセスで運用する
    - [x] `lazuli dev` の位置づけ: 開発用の統合起動（Rack+Deno）。`--reload` で簡易ホットリロード

- [x] **Turbo Drive の統合**
    - [x] Turbo Drive をJSで自動注入（esm.sh）
    - [x] **Turbo Frames/Streams の統合（hooks最小方針）**
        - [x] Turbo Frames: フレームワーク側は特別な仕組みを増やさず、ユーザーが `<turbo-frame id="...">` を書けば動く前提を明文化
        - [x] Turbo Streams: Ruby側に最小APIを追加（Content-Type: `text/vnd.turbo-stream.html`）
            - [x] `Lazuli::TurboStream` ビルダー（`append/prepend/replace/update/remove/before/after` 等）
            - [x] `Lazuli::Resource#turbo_stream` で複数操作をまとめて返す
            - [x] Content negotiation: `Accept: text/vnd.turbo-stream.html`（+ `?format=turbo_stream`）
            - [x] Turboが期待するリダイレクト/ステータス（302/303）と互換になるよう整理
            - [x] Turbo Streamエラー表示の整備（500は通常サニタイズ、debug時のみ詳細）
        - [x] `<template>` 内HTMLは Deno JSX fragment で生成（Rubyはoperationのみ）
        - [x] exampleアプリでStreams実例（create/deleteでprepend/replace/remove等）
        - [x] テスト: Content-Type/operations/Acceptなど検証

## 優先度: 中 (Enhancements)

- [x] **Turbo Streams: Ruby API の簡素化（Resource側のコード量を減らす）**
    - [x] `Lazuli::Resource#turbo_stream` の責務を整理
        - [x] `Resource#turbo_stream` は operations (`Lazuli::TurboStream`) を返すだけに寄せる
        - [x] Rackレスポンス生成（status/headers/body）+ escape_html + エラーハンドリングは `Lazuli::App` 側に集約
    - [x] **暗黙レスポンス化**（ユーザーが `[status, headers, body]` を意識しない）
        - [x] actionが `Lazuli::TurboStream` を返したら自動で `Content-Type: text/vnd.turbo-stream.html` を付与して返す
        - [x] `?format=turbo_stream` でも turbo-stream 扱いにできる
        - [x] 非turbo時のfallback（redirect等）を短く書ける `stream_or(...) { ... }` / `stream_ops_or(...) { ... }` を推奨例に反映
        - [x] `lazuli generate resource` が `stream_or(redirect_to(...)) { ... }` パターンを出力する
    - [x] **DSLを短くする**
        - [x] `turbo_stream { |s| ... }` を `stream { ... }` など短いエイリアスで提供（hooks最小のまま）
        - [x] `fragment:` 必須は維持しつつ、`target:` の頻出ケースを省略しやすいAPIにする（例: `append("items", "items/item", id: 1)` / `append("items", fragment: "items/item", props: {...})`）
    - [x] エラー表示の重複排除
        - [x] turbo-stream エラー表示は `App` に統一（debug/非debug、target/targets は `TurboStream#error_target(s)` を優先）
    - [x] 受け入れ基準（最小の書き味）
        - [x] ユーザーコード例: `def create; stream { |s| s.prepend "items", "items/item", id: 1 }; end` だけで動く
        - [x] `Accept: text/vnd.turbo-stream.html` のとき自動でstream、そうでないときは通常HTML/redirectのまま

- [x] **Sorbet/Ruby LSP の開発環境整備**
    - [x] monorepo rootにGemfile/sorbet configを配置（VSCodeで動作）
    - [x] Rack向けの最小RBI shim追加

- [x] **CI/テスト実行の整備**
    - [x] GitHub Actions: `packages/lazuli` の `bundle install` がGemNotFoundで落ちる問題を解消（working-directory / lockfile / cache）
    - [x] `packages/lazuli` のテストが `minitest` に依存しているので、開発依存に追加して `bundle exec ruby -Itest test/**/*_test.rb` を通す
    - [x] CI で Ruby + Deno のテスト実行

- [x] **Islands Architecture の自動化**
    - [x] `"use hydration"` ディレクティブの自動検出（page先頭のdirectiveでauto Island化）
    - [x] Islandマーカー（`data-lazuli-island`）検出 → hydration runtime を自動注入（1ページ1回）
- [x] **エラーハンドリングの強化**
    - [x] `Lazuli::RendererError` に status を保持（レンダリング失敗時にHTTP statusで扱える）
    - [x] Deno adapterのエラーレスポンスを統一（status付き + debug時のみstack、500は通常ISE）
    - [x] Deno側でのレンダリングエラーをRuby側で適切にキャッチして表示（HTMLエラーページ、500は通常サニタイズ）
    - [x] (任意) turbo-stream時は flash 等に update する共通ハンドラ（Accept turbo-stream 時の RendererError を turbo-stream で返す）
    - [x] 開発モードでの詳細なエラー画面（LAZULI_DEBUG=1でHTMLにmessage/backtraceを表示）
- [x] **データベース連携の強化**
    - [x] マイグレーション機能の統合（`lazuli db create` / `rollback` + `Lazuli::DB`）
    - [x] `Lazuli::Repository` のベースクラス実装（`default_db_path` / `open`）
- [x] **CLI UX拡張**
    - [x] `generate resource`でroute指定（`--route`）+ テンプレート注釈を追加
- [x] **ドキュメント整備**
    - [x] `packages/lazuli/README.md` を実用レベルに拡充（server/types/islands/turbo など）
    - [x] `packages/lazuli/docs/ARCHITECTURE.md` のディレクトリマッピング（views→pages/layouts/components等）を現状に合わせる
- [x] **サンプル拡充**
    - [x] `packages/example` にCRUDフロー + 複数Island + Turbo Streams/targets デモを集約
    - [x] `packages/example/README.md` に手順を明記（`lazuli dev` + `./bin/e2e`）

## 優先度: 低 (Future)

- [ ] **デプロイメントガイド**
    - [ ] Dockerfile の作成
    - [ ] VPS (Kamal等) へのデプロイ手順
- [ ] **テストフレームワークの統合**
    - [ ] Ruby側のRSpec統合
    - [ ] Deno側のテスト統合
- [ ] **ベンチマーク**
    - [x] example にローカルベンチスクリプト追加（`packages/example/bin/bench`）
    - [ ] Rails, Hanami との比較

## 完了済み (Done)

- [x] **アーキテクチャの確立** (Ruby + Deno + Hono JSX)
- [x] **Zero Node Modules の実現** (esm.sh + Import Map)
- [x] **SSRの実装** (Hono JSX)
- [x] **クライアントサイドハイドレーションの実装** (Hono JSX DOM)
- [x] **Unix Domain Socket 通信の実装**
- [x] **Denoアダプターの堅牢化** (Import Map挿入の修正、アセットMIME判定・404対応、ソケット初期化)
- [x] **Ruby側レンダラー/ルーティング改善** (ソケット設定を環境依存化、AssetレスポンスのContent-Type適用、HTTPメソッドによる簡易RESTマッピング)
