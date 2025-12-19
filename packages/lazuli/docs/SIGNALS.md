# Signals（提案）

このドキュメントは、Lazuli の思想に合う **小さく・依存が軽い「Signals + JSX」クライアントパターン**の提案をまとめたものです。

- **HTML First / Server is source of truth**（DB が真、サーバが返す HTML が正）
- **Islands は小さく**（クライアントの責務は局所的、SPA を目指さない）
- **DX のオーバーヘッドを最小に**（ユーザーが hooks を書かなくてよい）
- **Web 標準寄り**（JSX ランタイムは Hono の `hono/jsx/dom`）

目的は、**瞬時の UI フィードバック（Optimistic UI）** を実現しつつ、失敗時はロールバックし、成功時は **サーバレンダリングの HTML に同期して正に収束**させることです。

---

## 1. 動機：Lazuli における「Signals 的」

メンタルモデルは次の通りです。

1. ユーザー操作 → UI は即時に変わる（optimistic）。
2. クライアントがリクエストを投げる（POST / fetch）。
3. 成功したら → UI は **サーバの正の HTML**（Turbo Stream / HTML 断片）へ収束。
4. 失敗したら → UI は直前状態へロールバックし、エラーを表示。

Signals 的な状態管理が効く理由：

- 値を **読むだけで依存追跡**でき、購読の手書きが不要。
- 更新が即時かつ予測可能。
- 小さな Islands には小さな API だけで十分。

---

## 2. 非目標（Non-goals）

- フル SPA フレームワークを作ること。
- Turbo Drive / Streams を置き換えること。
- リクエストを跨いで共有されるグローバル状態を前提にすること。

これは **小さな Islands 専用**です。

---

## 3. 提案する API

### 3.1 Core

Solid 風（馴染みがあり、hook 不要な）構文：

```ts
const [count, setCount] = createSignal(0);
count();        // read
setCount(1);    // write
setCount(c => c + 1); // functional update
```

最小プリミティブ：

- `createSignal<T>(initial: T): [() => T, (next: T | ((prev: T) => T)) => void]`
- `createEffect(fn: () => void): () => void`（`dispose` を返す）
- `createMemo<T>(fn: () => T): () => T`
- `batch(fn: () => void): void`（複数更新を 1 回に畳む）
- `untrack<T>(fn: () => T): T`（任意：依存追跡を避けたい場合）

### 3.2 DOM / JSX 統合

ユーザーコードを hook-less に保つため、依存が変わったら view を再評価する単一の入口を用意します。

```ts
render(root, View, { strategy: "replace" | "morph" });
```

- `strategy: "replace"` → 最小：`root.replaceChildren(view())`
- `strategy: "morph"` → 任意：morphdom 的 diff で既存ノード/リスナー維持を狙う

view 関数は **Hono JSX DOM ノード**（`hono/jsx/dom`）を返す想定です。

---

## 4. 使い方（ユーザー向け）

### 4.1 最小カウンター

```ts
import { createSignal } from "tiny-signals";
import { render } from "tiny-signals/dom";
import { jsx } from "hono/jsx/dom";

const [count, setCount] = createSignal(0);

const App = () => (
  <div>
    <button onclick={() => setCount(c => c + 1)}>+</button>
    <span>{count()}</span>
  </div>
);

render(document.querySelector("#app")!, App);
```

### 4.2 レンダリング戦略の選択

JSX は同じで、戦略だけを切り替えられます。

```ts
render(root, App, { strategy: "replace" }); // 最小
render(root, App, { strategy: "morph" });   // DOM が大きい場合に有利
```

### 4.3 Optimistic UI（失敗で rollback）

ユーザーにとって一番わかりやすいモデル：

- `apply()`：ローカル UI 状態を即時に変更
- `commit()`：リクエスト実行
- `rollback()`：`commit()` が失敗したら元に戻す

```ts
import { createSignal } from "tiny-signals";
import { render, optimistic } from "tiny-signals/dom";
import { jsx } from "hono/jsx/dom";

const [done, setDone] = createSignal(false);
const [error, setError] = createSignal<string | null>(null);

async function toggle() {
  setError(null);

  await optimistic({
    apply: () => setDone(d => !d),
    rollback: () => setDone(d => !d),
    commit: async () => {
      const res = await fetch("/todos/1/toggle", { method: "POST" });
      if (!res.ok) throw new Error(await res.text());
    },
    onError: (e) => setError(String(e))
  });
}

const App = () => (
  <div>
    <button onclick={toggle}>{done() ? "done" : "todo"}</button>
    {error() && <p class="error">{error()}</p>}
  </div>
);

render(document.querySelector("#app")!, App, { strategy: "morph" });
```

---

## 5. 「Server is truth」：正の HTML へ収束させる

Optimistic UI は半分で、Lazuli の方針（DB/Server が真）を守るには **成功時にサーバ HTML へ収束**させる必要があります。

### 5.1 Turbo Streams を使う（推奨）

- クライアントは `Accept: text/vnd.turbo-stream.html` を付けて `fetch` する。
- サーバは Turbo Stream を返す。
- Turbo が DOM 更新を適用し、UI が正になる。

クライアント側の責務：

- （任意で）optimistic に更新。
- 成功時は **何もしない**（Turbo が DOM を正にする）。
- 失敗時は rollback。

### 5.2 Turbo Streams なし：HTML 断片 + morph

サーバが slot/partial の HTML 断片を返す場合、それを morph で当てられます。

```ts
await optimistic({
  apply: ...,
  rollback: ...,
  commit: async () => {
    const res = await fetch("/todos/1/toggle", {
      method: "POST",
      headers: { Accept: "text/html" }
    });
    if (!res.ok) throw new Error(await res.text());

    const html = await res.text();
    morph(slotEl, html); // 実装詳細：HTML -> Node -> morph
  }
});
```

---

## 6. Island のスコープ規約（よくあるバグを避ける）

1. **サーバレンダリングアプリでは module top-level で signal を作らない。**
   - island の `mount()` 内で作り、インスタンスごとに分離する。
2. **slot 単位レンダリングを優先**する。
   - 再描画/morph は最小 subtree に限定。
3. `dispose()` を提供する。
   - island が置換されるとき、effect/listener を確実に掃除する。
4. 競合（並行）をどう扱うか決める。
   - 小規模：`commit()` 中は二重実行を抑止。
   - 複雑：`tx` を導入（Action queue / reducer アプローチ）。

---

## 7. 実装スケッチ（内部）

期待動作を明確にするためのスケッチです。

- `createSignal` が保持：
  - `value`
  - `subscribers: Set<Effect>`
- 依存追跡：
  - `createEffect` 実行中はグローバルに `currentEffect` を指す。
  - `signal.read()` が `currentEffect` を subscriber に登録。
  - `signal.write()` が subscriber をスケジュール。
- スケジューリング：
  - `batch(fn)` が通知をキューし、最後に 1 回 flush。

DOM 統合：

- `render(root, view)` が effect を登録し、`view()` を再評価。
- 戦略：
  - `replace`: `root.replaceChildren(node)`
  - `morph`: `morphdom(root, node)`

---

## 8. 何をいつ選ぶか

- **最小 Islands** → `render(..., { strategy: "replace" })`
- **DOM が大きい / focus を維持したい** → `render(..., { strategy: "morph" })`
- **正の収束** → Turbo Streams を第一選択、morph はフォールバック

---

## 9. クライアント専用状態（Theme など）

Lazuli の「Server/DB が真」は **ドメイン状態**（例：Todos）に適用する原則であり、
Theme（ライト/ダーク）や UI 開閉のような **クライアント専用の UI 状態**は別枠で扱えます。

- UI 状態は `createSignal()` で管理して OK。
- 永続先は DB ではなく、`localStorage` / cookie 程度で十分。
- ページ全体に効く UI 状態（theme / toast / nav 開閉など）は「クライアント側グローバル」に持ってよい。

### 9.1 `localStorage` に入れるものの原則

- **基本 OK**：theme / 表示密度 / dismissed banner / UI の折りたたみ / 下書き（draft）
- **慎重**：権限、課金状態、在庫、Todos 一覧など「サーバが真のデータ」をフルコピーして保持
- **避ける**：認証トークン等の機微情報（特に XSS リスクが上がるため）

FOUC（初期チラつき）を避けたい場合は、theme を cookie にも保存し、サーバが `<html data-theme=...>` を最初から出せるようにします。

---

## 10. Turbo なしでも使えるか

使えます。Turbo は「成功時にサーバの正へ収束させる」ための選択肢の 1 つです。
Turbo なしの場合の収束パターン：

1. **JSON を返す** → 返ってきた値で signals の state を確定更新
2. **HTML 断片を返す** → `morph` 戦略で該当 slot に差分適用
3. **何も返さない** → optimistic の状態を確定（UI-only 操作ならこれで十分）

---

## 11. Island 以外でも使えるか

設計自体は Island 以外でも動きます（ページ全体を 1 root として `render()` して SPA 的に使うことも可能）。
ただし、Island 前提を外すと次のコストが増えます。

- `render()` の再評価範囲が大きくなり、`replace` は厳しくなる（`morph` 寄りになる）
- ドメイン状態をクライアントで二重管理しがちで、整合性が難しくなる
- ルーティング/データ取得/キャッシュ/並行操作など、クライアント側の責務が増える

Lazuli の強み（HTML First / Server as truth）を活かすなら、まずは **Island（小さな範囲）**での利用を推奨します。

---

## 12. 未決事項

- 命名：`createSignal/createEffect`（Solid 風） vs `signal/effect`（Preact 風）
- `render()` は `{ dispose }` を返すべきか？
- Turbo Streams をどこまで標準化し、HTML 断片をどこまで許容するか？
