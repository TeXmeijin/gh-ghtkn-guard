# gh-ghtkn-guard

日本語 | [English](README.md)

`gh-ghtkn-guard` は、Claude Code / Codex などのコーディングエージェントに
ローカル shell command を実行させる開発者向けの、小さな host-side `gh`
wrapper です。

[`ghtkn`](https://github.com/suzuki-shunsuke/ghtkn) で GitHub App User
Access Token を取得し、その token を本家 GitHub CLI (`gh`) の子プロセスにだけ
渡します。wrapper の host-side interface では token を表示する command を
ブロックします。

## 目的

エージェント支援開発では、project script、package lifecycle hook、生成された
shell command などが、GitHub CLI 認証情報のある開発端末上で実行されやすく
なります。

この wrapper の目的は限定的です。

- 長生きする agent shell environment に `GH_TOKEN` を置かない
- host 側の `gh auth token` で注入 token を表示させない
- 通常の `gh` 利用感をできるだけ保つ
- GitHub App permissions と短命 User Access Token で権限境界を作る

これは摩擦層であり、任意のローカルコード実行に対する完全な防御ではありません。
`ghtkn get "$GHTKN_APP_NAME"` を直接実行できるプロセスは、有効な GitHub App
User Access Token を取得できます。

## 要件

- `ghtkn` が credential store にアクセスできる macOS などの環境
- GitHub CLI が `/opt/homebrew/bin/gh` にあること。違う場合は
  `GH_GHTKN_GUARD_REAL_GH` を設定する
- `ghtkn` が `/opt/homebrew/bin/ghtkn` にあること。違う場合は
  `GH_GHTKN_GUARD_GHTKN_BIN` を設定する
- 現在の環境に `GHTKN_APP_NAME` が設定されていること

例:

```zsh
export GHTKN_APP_NAME=your-org/your-ghtkn-app
```

`ghq` で owner ごとにディレクトリが分かれている場合は、owner directory
level の `direnv` や shell startup file で設定します。

```text
~/ghq/github.com/your-org/.envrc
~/ghq/github.com/your-user/.envrc
```

子 repository が独自の `.envrc` を持つ場合は、親設定を読むために `source_up`
を追加します。

## セットアップ

エージェント用 shell で、この repository の `bin` directory を本家 GitHub CLI
より前に置きます。

```zsh
export PATH="/path/to/gh-ghtkn-guard/bin:$PATH"
```

確認:

```zsh
which gh
gh api /user --jq .login
gh auth token
```

期待値:

- `which gh` がこの repository の `bin/gh` を指す
- `GHTKN_APP_NAME` があると `gh api /user` が通る
- `gh auth token` は wrapper によってブロックされる

## 使い方

普段どおり `gh` を使います。

```zsh
gh issue view 123
gh pr list
gh pr create -B develop -d
gh workflow run "Deploy" --ref "$(git branch --show-current)"
```

wrapper 内部では以下の形で実行します。

```text
ghtkn get "$GHTKN_APP_NAME"
GH_TOKEN=<token> GITHUB_TOKEN=<token> /opt/homebrew/bin/gh ...
```

token は本家 `gh` の子プロセスにだけ渡され、親 shell には export されません。

`ghtkn` が GitHub Device Flow の対話認可を必要とする場合、wrapper は
`ghtkn` の stdout を stream しません。stdout は token 取得用に予約しているためです。
`ghtkn` は一回限りの Device Flow code を stderr に出すため、コーディングエージェント
にも `XXXX-XXXX` の code は見えます。token が返らない場合、wrapper は timeout して
実行すべき command を stderr に出して終了します。上に表示された code を GitHub の
device page に入力するか、通常の対話 terminal で一度認可してから、`gh` command を
再実行します。

```zsh
ghtkn get "$GHTKN_APP_NAME" >/dev/null
```

## セキュリティモデル

この wrapper は、host 側での GitHub token の偶発的・安易な露出を減らします。

- `gh auth token` をブロックする
- `gh auth status --show-token` をブロックする
- agent shell environment に `GH_TOKEN` を保持しない
- `gh api` はデフォルトで read-like method (`GET`, `HEAD`, `OPTIONS`) のみに
  制限する

1 shell session だけ write-likely な `gh api` を許可する場合:

```zsh
export GH_GHTKN_GUARD_ALLOW_WRITE=1
```

`ghtkn get` を待つ秒数を変える場合:

```zsh
export GH_GHTKN_GUARD_GHTKN_TIMEOUT_SECONDS=20
```

この wrapper が防がないもの:

- `ghtkn get "$GHTKN_APP_NAME"` を実行できるプロセスによる token 取得
- PATH を迂回して本家 `gh` を直接呼ぶプロセス
- GitHub App User Access Token の失効ポリシー。これは GitHub 側が制御する

## License

MIT
