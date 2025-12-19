# Lazuli Reference Guide

このドキュメントは Lazuli を「使う側」のためのリファレンスです（CLI / ルーティング規約 / Resource API / Turbo Streams / Islands / DB）。

## 0. 用語（超短縮）

- **Rack (Ruby)**: ルーティング + Resource 実行 + DB。
- **Renderer (Deno/Hono)**: SSR（ページHTML）と Turbo Streams の `<template>` HTML（JSX fragment）生成、`/assets/*` 配信。
- **App root**: Lazuli アプリのルートディレクトリ（`config.ru` がある場所、通常 `packages/example` のような場所）。

---

## 1. クイックスタート

```bash
# 新規アプリ
lazuli new my_app
cd my_app
bundle install

# DB作成 + migrate（SQLite）
lazuli db create

# 開発起動（Rack + Deno を同時起動）
lazuli dev --reload
```

---

## 2. ディレクトリ構成（規約）

`lazuli new` が作る最小構成:

```
.
├── app/
│   ├── layouts/        # Deno: レイアウト（例: Application.tsx）
│   ├── pages/          # Deno: ページ（例: home.tsx）
│   ├── components/     # Deno: Turbo Streams / Islands 用の fragment/component
│   ├── resources/      # Ruby: Resource（例: users_resource.rb）
│   ├── repositories/   # Ruby: DBアクセス層（任意）
│   └── structs/        # Ruby: Lazuli::Struct（型生成の入力）
├── db/
│   ├── migrate/        # *.up.sql / *.down.sql
│   └── development.sqlite3
├── tmp/
│   └── sockets/        # Deno renderer の UDS
├── config.ru
└── deno.json
```

---

## 3. CLI リファレンス

`lazuli <command> [options]`

### 3.1 `lazuli dev`（推奨: 開発用）

Rack + Deno を **同時起動**（`Lazuli::ServerRunner`）。

```bash
lazuli dev --reload
```

主なオプション:

- `--app-root PATH`（default: cwd）
- `--socket PATH`（default: `tmp/sockets/lazuli-renderer.sock`）
- `--port 9292`
- `--reload`（雑なwatcherで両プロセスを再起動）

### 3.2 `lazuli server`（Rackのみ）

Rack だけを起動します。**Deno renderer は別プロセスで起動**してください。

```bash
lazuli server --port 9292
```

オプション:

- `--app-root PATH`
- `--socket PATH`
- `--port PORT`

### 3.3 Deno renderer の起動（rack-only の場合）

```bash
deno run -A --unstable-net \
  --config "$(pwd)/deno.json" \
  "$(bundle show lazuli)/assets/adapter/server.tsx" \
  --app-root "$(pwd)" \
  --socket "$(pwd)/tmp/sockets/lazuli-renderer.sock"
```

### 3.4 `lazuli db`（SQLite migrate）

#### `lazuli db create`

```bash
lazuli db create
# or
lazuli db create --db db/development.sqlite3 --migrations db/migrate
```

#### `lazuli db rollback`

```bash
lazuli db rollback
lazuli db rollback --steps 2
```

### 3.5 `lazuli new <name>`

新規アプリ雛形を作成。

### 3.6 `lazuli generate resource <name> [app_root] [--route PATH]`

Resource + page + struct + repository の雛形。

```bash
lazuli generate resource users
lazuli generate resource users --route /users
```

### 3.7 `lazuli types [app_root]`

`app/structs/**/*.rb` から TypeScript 型 + RPC client を生成。

---

## 4. ルーティング規約（超重要）

Lazuli のルーティングは「規約ベース」です（いまはルート定義DSL無し）。

### 4.1 URL → Resource / action の対応

パスの先頭セグメントから Resource を解決します:

- `/users` → `UsersResource`
- `/admin/users` → いまは未対応（最初のセグメントのみで解決）

HTTPメソッドと `:id` の有無で action を決めます:

| Request | action |
| --- | --- |
| `GET /users` | `index` |
| `GET /users/:id` | `show` |
| `POST /users` | `create` |
| `PUT/PATCH /users/:id` | `update` |
| `DELETE /users/:id` | `destroy` |

### 4.2 params の扱い

- Query/form params + path params をマージします。
- `/users/123` の `123` は `params[:id]` に入ります。

---

## 5. Resource API（Ruby側の基本構文）

### 5.1 `Render(page, props = {})`

Deno renderer に SSR を依頼して HTML を返します。

```rb
class HomeResource < Lazuli::Resource
  def index
    Render "home", message: "hello"
  end
end
```

- `page` は `app/pages/<page>.tsx`（拡張子なし）に対応。

### 5.2 `redirect(location, status: nil)` / `redirect_to(location, status: nil)`

Rackレスポンス `[status, headers, body]` を返すヘルパ。

- `GET` は 302、`POST/PUT/PATCH/DELETE` は 303 がデフォルト。

### 5.3 Turbo Streams: `stream {}` と `*_stream` アクション

- Ruby は **operations を積むだけ**。
- `<template>` の中身HTMLは **Denoが JSX fragment から生成**。
- リクエストが Turbo Streams（`Accept: text/vnd.turbo-stream.html` / `?format=turbo_stream`）の場合、Router は **`<action>_stream` を優先して呼びます**（無ければ通常の `<action>`）。

```rb
class UsersResource < Lazuli::Resource
  def create
    UserRepository.create(name: params[:name])
    redirect("/users")
  end

  def create_stream
    user = UserRepository.create(name: params[:name])

    stream do |t|
      t.prepend :users_list, "components/UserRow", user: user
      t.update  :flash,      "components/FlashMessage", message: "Created"
    end
  end
end
```

- `stream` は `turbo_stream` の alias。

---

## 6. Turbo

### 6.1 Turbo Drive

`@hotwired/turbo` を読み込むため、リンク遷移/フォーム送信が Drive によりインターセプトされます。

### 6.2 Turbo Frames

フレームワークは Frames に基本ノータッチです。TSX 側で `<turbo-frame id="...">` を書けばOK。

### 6.3 Turbo Streams（API リファレンス）

#### アクション

`Lazuli::TurboStream` に以下が定義されています:

- `append` / `prepend`
- `replace` / `update`
- `before` / `after`
- `remove`

#### `target` / `targets` の省略ルール

- 第一引数が `Symbol` / 通常文字列 → `target:` 扱い
- 第一引数が `"#"` / `"."` / `"["` で始まる文字列 → `targets:` 扱い
- 第一引数が `Array` → `targets:` 扱い（`, ` でjoin）

例:

```rb
stream do |t|
  t.remove "#users_list li"              # targets
  t.update :flash, "components/Flash", message: "hi"  # target
end
```

#### fragment

- `fragment` は `app/<fragment>.tsx` に対応（例: `components/UserRow` → `app/components/UserRow.tsx`）。
- `..` や `/` 開始は禁止（パストラバーサル防止）。

#### props

- `props:` は省略可能（キーワード引数が `props` にマージされます）

---

## 7. Islands（hydration）

### 7.1 最小: `<Island />`

```tsx
import Island from "lazuli/island";
import Counter from "../components/Counter.tsx";

export default function Home() {
  return <Island path="components/Counter" component={Counter} data={{ initialCount: 1 }} />;
}
```

- HTML内に `data-lazuli-island` が存在する場合、Renderer が hydration runtime を自動注入します。

### 7.2 ページ全体: "use hydration"（ページ先頭）

ページモジュール先頭が以下の場合:

```tsx
"use hydration";
```

Renderer が「ページ全体を Island 化」します（全体 hydration）。

---

## 8. 設定（環境変数）

Ruby / Deno 両方で共通に使うもの:

- `LAZULI_APP_ROOT`: アプリルート
- `LAZULI_SOCKET`: Deno renderer の socket
- `LAZULI_DEBUG=1`: デバッグ出力/エラーページ
- `LAZULI_RELOAD_ENABLED=1`: reload を有効化
- `LAZULI_RELOAD_TOKEN_PATH`: reload token file path

Runner/起動関連:

- `LAZULI_DENO` or `DENO`: deno バイナリパス
- `LAZULI_QUIET=1`: runner のログ抑制
- `LAZULI_START_RETRIES`, `LAZULI_START_TIMEOUT`

DB:

- `LAZULI_DB_PATH`（or `LAZULI_DB`）: SQLite DB path

Turbo Streams エラー表示:

- `LAZULI_TURBO_ERROR_TARGET`（default: `flash`）

---

## 9. 受け入れ（e2e）サンプル

`packages/example` が受け入れ用サンプルです。

```bash
cd packages/example
bundle install
lazuli db create
lazuli dev --reload
./bin/e2e
```

何を確認するかは `packages/example/README.md` を参照。
