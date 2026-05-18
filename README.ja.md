# gh-sandbox-proxy

日本語 | [English](README.md)

`gh-sandbox-proxy` は、公式 GitHub CLI (`gh`) を使い捨ての Docker
コンテナ内で実行する、`gh` 互換寄りの wrapper です。

主な対象は、Claude Code、Codex、または類似の coding agent にローカル shell
command を実行させている開発者です。普段の `gh` workflow の利便性をできるだけ
維持しつつ、host 側の GitHub CLI token が自動化された process や便乗的な
process に回収される難度を上げることを狙っています。

## なぜ作るか

近年のパッケージ supply-chain incident により、特に agent-assisted な開発端末に
置かれた CLI 認証情報の扱いは、より現実的なリスクとして見直す必要が出てきました。
GitHub CLI の認証情報がホスト OS 内の予測しやすい場所に永続化され、
さらに単一のコマンドで利用可能な token を表示できる状態は、攻撃者にとって
価値の高い足場になりえます。

このプロジェクトは、端末侵害そのものを完全に防ぐことを主張しません。狙いは
もっと限定的です。ホスト OS を GitHub CLI credential の回収場所として
使いにくくしつつ、普段の `gh` の利便性をできるだけ落とさないことです。
これは保証ではなく、攻撃者に追加の摩擦を課すための実用的なレイヤーです。

設計上の目標は次の通りです。

- GitHub CLI の auth state をホスト OS に置かない
- ホスト側で `gh auth token` を実行しても有用な token を返さない
- 主要な `gh` コマンドのインターフェースをできるだけ変えない
- 認証済み sandbox を短い TTL で失効させる。デフォルトは `1h`

Docker image は、対応する Linux architecture 向け GitHub CLI release
asset の SHA256 checksum を固定して検証します。

これは任意のローカルコード実行に対する完全な防御ではありません。sandbox
container が生きている間、その container 内でコマンドを実行できる主体は、
container-local の GitHub CLI session を利用できます。

## Setup

この project は一発 setup script を提供しません。shell startup file、symlink、
Docker resource、repository mount 設定に触るため、setup は agent と対話しながら
承認ベースで進めます。

同梱の Claude Code / Codex Skill を使います。

```text
skills/gh-sandbox-proxy-setup/SKILL.md
```

Skill は最初に shell startup file、既存の `gh` 解決先、repository root 候補を
調べます。そのうえで、書き込む file、作る symlink、Docker resource、
`workspace_mounts` を提示し、承認を得てから変更します。

uninstall は削除内容を確認してから実行します。

```zsh
./uninstall.sh
```

## 使い方

通常の `gh` と同じように使います。

```zsh
gh issue view 123
gh pr list
gh pr create -B develop -d
gh workflow run "Deploy" --ref "$(git branch --show-current)"
```

`gh pr list -w` のように browser を開くコマンドも proxy します。Linux 版
`gh` process が container-local hook に URL を渡し、その URL を wrapper が
macOS host 側で開きます。

テスト時は host opener を上書きできます。

```zsh
GH_SANDBOX_OPEN=/bin/echo gh pr list -w
```

初回の認証が必要な command では、container 内で次が実行されます。

```zsh
gh auth login -h github.com --web
```

表示された browser/device flow に従ってください。token は host の GitHub CLI
config や Docker volume ではなく、sandbox に紐づく tmpfs に保存されます。
tmpfs は sandbox container の終了時に揮発します。

## Sandbox 操作

```zsh
gh sandbox status
gh sandbox cleanup
gh sandbox build
gh sandbox config
gh sandbox suggest-mounts
```

`cleanup` は現在の container をすぐに削除します。

## Config

デフォルトの config path:

```text
~/.config/gh-sandbox-proxy/config.yml
```

上書き:

```zsh
export GH_SANDBOX_CONFIG=/path/to/config.yml
```

主な項目:

```yaml
image: gh-sandbox-proxy:latest
ttl: 1h
active_window_enabled: false
active_window_timezone: Asia/Tokyo
active_window_start: "10:00"
active_window_end: "19:00"
auth_storage: tmpfs
auth_tmpfs_size: 16m
workspace_mounts:
  - ~/ghq
  - ~/Documents/src
container_name: gh-sandbox-proxy
auto_auth: true
auth_hostname: github.com
blocked:
  - ["auth", "token"]
  - ["auth", "status", "--show-token"]
```

YAML parser は意図的に小さくしています。`config.example.yml` と同じ単純な
shape で書いてください。

`workspace_mounts` には、git repository を置いている安定した祖先 directory を
指定します。wrapper はこれらの root を一度 mount し、host の current directory
に対応する container path を `docker exec -w` で指定します。これにより `.git`、
remote、current branch を読む repo-aware な `gh` command が、repository 間を
移動するたびに sandbox を作り直さずに動きます。

current directory が `workspace_mounts` のどれにも含まれない場合、local git
context に依存する command は失敗することがあります。その場合は
`--repo OWNER/REPO` を使うか、適切な祖先 directory を `workspace_mounts` に追加
してください。

日本時間の通常稼働時間中は sandbox を維持し、それ以外では `ttl` を使う例:

```yaml
ttl: 1h
active_window_enabled: true
active_window_timezone: Asia/Tokyo
active_window_start: "10:00"
active_window_end: "19:00"
```

これは Docker volume の TTL 機能ではありません。sandbox 起動時に wrapper が
維持時間を計算し、`--rm`、tmpfs auth directory、main process としての
`sleep <seconds>` で container を起動します。sleep が終了すると Docker が
container を削除し、tmpfs 上の auth data も揮発します。

## Security Model

この wrapper は、長期的に残る host GitHub CLI token を不用意に露出するリスクを
下げることを目的にしています。

- host 側の `gh auth token` を block する
- host 側の `gh auth status --show-token` を block する
- 公式 `gh` の auth file を sandbox tmpfs にだけ置く
- container は設定された expiry policy に従って終了する。
  デフォルトは `ttl`、有効化時は active window
- `gh sandbox cleanup` で認証済み container を即時削除する

この wrapper が防げないものもあります。

- Docker administrator は container に inspect / exec できる
- container 内で実行された command は active GitHub session を利用できる
- container を削除しても GitHub 側で発行済み OAuth token が自動 revoke される
  わけではない
- mount された workspace directory は、container 内 command から読み書きできる

## License

MIT
