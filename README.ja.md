<div align="center">

# tmux-autoreload-revamped

<strong>tmuxの設定を編集して保存するだけで、キーもコマンドも使わずに自動で再読み込みされます。</strong>

[English](README.md) | 日本語 | [简体中文](README.zh-Hans.md) | [繁體中文（香港）](README.zh-HK.md)

[![family](https://img.shields.io/github/actions/workflow/status/tmux-revamped/tmux-autoreload-revamped/family.yml?branch=main&style=flat-square&label=family)](https://github.com/tmux-revamped/tmux-autoreload-revamped/actions/workflows/family.yml)
[![tests](https://img.shields.io/github/actions/workflow/status/tmux-revamped/tmux-autoreload-revamped/tests.yml?branch=main&style=flat-square&label=tests)](https://github.com/tmux-revamped/tmux-autoreload-revamped/actions/workflows/tests.yml)
[![release](https://img.shields.io/github/v/release/tmux-revamped/tmux-autoreload-revamped?style=flat-square&label=release)](https://github.com/tmux-revamped/tmux-autoreload-revamped/releases/latest)
[![openssf scorecard](https://img.shields.io/ossf-scorecard/github.com/tmux-revamped/tmux-autoreload-revamped?style=flat-square&label=openssf%20scorecard)](https://scorecard.dev/viewer/?uri=github.com/tmux-revamped/tmux-autoreload-revamped)
[![license](https://img.shields.io/github/license/tmux-revamped/tmux-autoreload-revamped?style=flat-square&label=license)](LICENSE)

<p align="center">
  <a href="#what-it-does">機能</a> |
  <a href="#requirements">動作要件</a> |
  <a href="#installation">インストール</a> |
  <a href="#usage">使い方</a> |
  <a href="#configuration">設定</a> |
  <a href="#key-bindings">キーバインド</a> |
  <a href="#how-it-works">仕組み</a>
</p>

</div>

監視バックエンド**4**種類。オプション**12**個。サブコマンド**5**個。CIはLinuxとmacOSの**10**通りのツールチェーンの組み合わせでテストを実行します。

---

<a id="what-it-does"></a>

## 機能

tmuxが読み込んだすべての設定ファイルと、それらが`source`するすべてのファイルを監視します。いずれかが変更されると設定を再読み込みし、ステータスラインに`tmux config reloaded (tmux.conf)`と表示します。

- 内容のチェックサムを比較するため、バイト列が変わらない保存では再読み込みしません。
- エラーを含む編集では、失敗したファイルとtmuxのエラーメッセージを表示し、そのファイルの最後に正常に読み込めた版を読み込み直します。
- ペインがコピーモードのときの変更は保留されるため、再読み込みが選択操作を中断することはありません。すべてのペインがモードを抜けた後の最初のチェックで適用されます。ポーリングでは次の周期、監視ツールがある場合は次のファイルイベントです。
- 監視プロセスはtmuxサーバーごとに1つだけ動きます。プラグインを再読み込みすると、生きている監視プロセスはそのまま使い、停止しているものは置き換えます。

<a id="requirements"></a>

## 動作要件

| ツール | バージョン | 用途 |
|:-----|:--------|:-----------|
| tmux | 3.2以降 | 読み込まれた設定ファイルを列挙する`#{config_files}` |
| bash | 3.2以降 | macOSの`/bin/bash`を含むすべてのスクリプト |
| `fswatch`、`inotifywait`または`entr` | 任意 | 任意。イベント駆動の再読み込み。どれもなければポーリングします |
| `osascript`または`notify-send` | 任意 | 任意。デスクトップ通知 |

macOSとLinux、x86_64とarm64で動作します。ファイルの更新時刻はGNUの`stat -c`を先に、BSDの`stat -f`を次に試すため、macOS標準のツール、GNU coreutils、uutils coreutilsのいずれでも動作します。

<a id="installation"></a>

## インストール

### TPMでインストール

`~/.tmux.conf`にプラグインを追加し、`prefix + I`を押します。

```tmux
set -g @plugin 'tmux-revamped/tmux-autoreload-revamped'
```

### 手動インストール

```bash
git clone https://github.com/tmux-revamped/tmux-autoreload-revamped ~/.tmux/plugins/tmux-autoreload-revamped
```

次の行を`~/.tmux.conf`に追加し、tmuxを一度再読み込みします。

```tmux
run-shell ~/.tmux/plugins/tmux-autoreload-revamped/autoreload-revamped.tmux
```

<a id="usage"></a>

## 使い方

`~/.tmux.conf`か、そこから読み込まれるファイルを保存します。tmuxは次のファイルイベントで設定を適用します。監視ツールがない場合は`@autoreload_revamped_interval`秒以内に適用します。

[`src/autoreload.sh`](src/autoreload.sh)のスクリプトはサブコマンドも受け付けます。

| サブコマンド | 動作 |
|:-----------|:-------|
| `reload` | エントリーポイントを今すぐ読み込む |
| `pause` | 変更への反応を止める |
| `resume` | 変更への反応を再開する |
| `toggle` | 一時停止と動作中を切り替える |
| `status` | 状態、監視プロセスのpid、バックエンドを表示する |

```bash
~/.tmux/plugins/tmux-autoreload-revamped/src/autoreload.sh status
```

```text
autoreload-revamped: active; watcher pid 48213; backend fswatch
```

<a id="configuration"></a>

## 設定

| オプション | 既定値 | 意味 |
|:-------|:--------|:--------|
| `@autoreload_revamped_files` | 空 | 監視するファイル。カンマまたは空白で区切り、`~`を展開します。設定するとtmuxが読み込んだファイルの代わりに使います |
| `@autoreload_revamped_entrypoints` | 読み込まれた設定ファイル | 再読み込みのたびに読み込むファイル |
| `@autoreload_revamped_interval` | `2` | ポーリング時のチェック間隔の秒数 |
| `@autoreload_revamped_quiet` | `0` | `1`で再読み込みのメッセージを表示しない |
| `@autoreload_revamped_discover` | `1` | `source`と`source-file`の行を8階層までたどる。`0`で最上位のファイルだけを監視 |
| `@autoreload_revamped_atomic` | `1` | 各ファイルのディレクトリも監視し、名前の変更で保存するエディタにも対応する。`0`でファイルだけを監視 |
| `@autoreload_revamped_validate` | `1` | 読み込みエラー時に、失敗したファイルの最後の正常な版を読み込む。`0`でロールバックしない |
| `@autoreload_revamped_defer` | `1` | いずれかのペインがコピーモードなどのモード中は待つ。`0`ですぐに再読み込み |
| `@autoreload_revamped_selective` | `0` | `1`で、変更されたファイルをインクルードの木に含むエントリーポイントだけを読み込む |
| `@autoreload_revamped_backoff_max` | `30` | 再読み込みの失敗が続いたときのポーリング間隔の上限秒数 |
| `@autoreload_revamped_flash` | `0` | `1`で再読み込みのメッセージを反転表示でもう一度表示 |
| `@autoreload_revamped_notify` | `0` | `1`で再読み込みのたびにデスクトップ通知を送る |

```tmux
set -g @autoreload_revamped_files '~/.tmux.conf ~/.config/tmux/theme.conf'
set -g @autoreload_revamped_notify '1'
```

### 内部状態

次のオプションはプラグインが自身で書き込みます。設定しないでください。

| オプション | 内容 |
|:-------|:------|
| `@autoreload_revamped_pid` | 動作中の監視プロセスのpid |
| `@autoreload_revamped_paused` | 一時停止中は`1`、それ以外は`0` |
| `@autoreload_revamped_snapshot` | 監視対象ファイルごとの`path mtime`の行 |
| `@autoreload_revamped_hash` | 監視対象のすべてのファイル内容のチェックサム |
| `@autoreload_revamped_fail_count` | 連続した再読み込みの失敗回数。ポーリング間隔を`@autoreload_revamped_backoff_max`まで延ばします |

<a id="key-bindings"></a>

## キーバインド

このプラグインはキーを割り当てません。tmuxから再読み込みや一時停止をするには、サブコマンドを自分で割り当てます。

```tmux
bind R run-shell "~/.tmux/plugins/tmux-autoreload-revamped/src/autoreload.sh reload"
bind P run-shell "~/.tmux/plugins/tmux-autoreload-revamped/src/autoreload.sh toggle"
```

<a id="how-it-works"></a>

## 仕組み

```mermaid
graph LR
    Load[プラグインの読み込み] --> Ensure[監視プロセスがなければ起動]
    Ensure --> Wait[変更を待つ]
    Wait --> Diff[更新時刻とチェックサムを比較]
    Diff -->|変更なし| Wait
    Diff -->|変更あり| Source[エントリーポイントを読み込む]
    Source -->|エラー| Rollback[エラーを表示し最後の正常な版を読み込む]
    Source -->|成功| Announce[再読み込みのメッセージを表示]
    Rollback --> Wait
    Announce --> Wait
```

監視プロセスは`fswatch`、`inotifywait`、`entr`の順に最初に見つかったツールを使い、どれもなければポーリングします。ポーリングは再読み込みが失敗するたびに待ち時間を倍にし、上限は`@autoreload_revamped_backoff_max`秒です。

監視プロセスは起動時にtmuxサーバーのpidを記録します。そのサーバーがなくなるか、ソケットで別のサーバーが応答すると終了します。

エントリーポイントのバックアップは`~/.tmux/autoreload-revamped/backup`に置かれます。監視プロセスは起動時と、再読み込みが成功するたびに書き込みます。場所を変えるには環境変数`AR_CACHE_DIR`を設定します。

<a id="development"></a>

## 開発

| コマンド | 実行内容 |
|:--------|:-------------|
| `make test` | [`test/`](test)以下のbatsテスト |
| `make lint` | すべてのシェルファイルへのshellcheck |
| `make coverage` | Linuxでのkcovによる行カバレッジ。95%未満で失敗します |

監視ツールの選択、変更の検出、パスの処理を行う純粋関数は[`src/lib/autoreload/autoreload.sh`](src/lib/autoreload/autoreload.sh)にあります。

<a id="license"></a>

## ライセンス

[MIT](LICENSE)、copyright Gustavo Franco。

<!-- family:begin -->

## tmux-revamped ファミリー

このプラグインは tmux-revamped ファミリーの一員です。すべてのメンバーが [`FAMILY.md`](FAMILY.md) の同じ規約、`family/` 配下の同じツール、同じ共有ライブラリを持ち、チェックサムの一覧によってバイト単位で同一に保たれています。メンバーは一緒にインストールする前提で作られており、ほかのメンバーが使うキーや tmux オプションを使うメンバーはありません。

あるメンバーで見つかった不具合は、修正完了とする前に全メンバーで同じ不具合を探します。この義務は記憶に頼らず規約に書かれており、`family/bin/sweep` がその作業を行います。

| メンバー | 機能 |
|---|---|
| [`tmux-autoreload-revamped`](https://github.com/tmux-revamped/tmux-autoreload-revamped) | **このプラグイン**、tmuxの設定を編集して保存するだけで、キーもコマンドも使わずに自動で再読み込みされます |
| [`tmux-battery-revamped`](https://github.com/tmux-revamped/tmux-battery-revamped) | tmuxのステータスバーに電池の状態を表示し、ステータスの描画を一切止めません |
| [`tmux-bluetooth-revamped`](https://github.com/tmux-revamped/tmux-bluetooth-revamped) | 接続中のすべてのBluetooth機器とその電池残量をtmuxのステータスバーに表示し、描画を止めません |
| [`tmux-cpu-revamped`](https://github.com/tmux-revamped/tmux-cpu-revamped) | CPUの負荷、温度、周波数をtmuxのステータスバーに表示し、描画を一切止めません |
| [`tmux-disk-revamped`](https://github.com/tmux-revamped/tmux-disk-revamped) | tmuxのステータスバーにディスク使用量を表示し、ステータスの描画を一切止めません |
| [`tmux-extract-revamped`](https://github.com/tmux-revamped/tmux-extract-revamped) | 画面上の URL、パス、ハッシュなどのトークンを fzf で選び、カーソル位置に入力します。純粋なシェルだけで動きます |
| [`tmux-fzf-revamped`](https://github.com/tmux-revamped/tmux-fzf-revamped) | ポップアップ内の fzf ピッカーから、tmux のセッション、ウィンドウ、ペインの切り替え、終了、名前変更、作成を行います |
| [`tmux-git-revamped`](https://github.com/tmux-revamped/tmux-git-revamped) | アクティブなペインのgitブランチ、変更、プロバイダーの件数を、描画を止めずにtmuxのステータスバーに表示します |
| [`tmux-gpu-revamped`](https://github.com/tmux-revamped/tmux-gpu-revamped) | NVIDIA、AMD、Intel、Apple の GPU の負荷、温度、クロック、電力、メモリを tmux のステータスバーに表示します |
| [`tmux-kube-revamped`](https://github.com/tmux-revamped/tmux-kube-revamped) | 現在の Kubernetes コンテキストと名前空間を、kubectl を使わずに kubeconfig から解析して tmux のステータスバーに表示します |
| [`tmux-launcher-revamped`](https://github.com/tmux-revamped/tmux-launcher-revamped) | 任意の TUI アプリを、現在のペインのディレクトリでポップアップまたはウィンドウとして起動します。アプリごとにキーを設定できます |
| [`tmux-logging-revamped`](https://github.com/tmux-revamped/tmux-logging-revamped) | 任意のペインをファイルに保存します。ライブのログ記録、スクロールバック全体、1 回限りのスクリーンショットに対応します |
| [`tmux-music-revamped`](https://github.com/tmux-revamped/tmux-music-revamped) | 再生中の曲をステータスバーに表示し、ステータスの描画を止めません |
| [`tmux-network-revamped`](https://github.com/tmux-revamped/tmux-network-revamped) | ネットワークのスループットをステータスバーに表示し、描画を止めません |
| [`tmux-pain-control-revamped`](https://github.com/tmux-revamped/tmux-pain-control-revamped) | tmux のペインとウィンドウの操作キー。tmux のバージョンに対応し、vim と共存でき、どの prefix キーも無効にできます |
| [`tmux-persist-revamped`](https://github.com/tmux-revamped/tmux-persist-revamped) | tmuxのすべてのセッション、ウィンドウ、ペインを保存し、タイマーで自動保存して、再起動後にすべて復元します |
| [`tmux-plugin-template`](https://github.com/tmux-revamped/tmux-plugin-template) | tmux-revampedプラグインの出発点です。共有ライブラリ、batsハーネス、CI、ファミリーのツールを含みます |
| [`tmux-pomodoro-revamped`](https://github.com/tmux-revamped/tmux-pomodoro-revamped) | すべての状態をtmuxオプションに保持し、一時ファイルを使わない、tmuxステータスバーのポモドーロタイマーです |
| [`tmux-ram-revamped`](https://github.com/tmux-revamped/tmux-ram-revamped) | RAM、スワップ、メモリプレッシャーをtmuxのステータスバーに表示します。計測はバックグラウンドで行うため描画を待たせません |
| [`tmux-reorder-revamped`](https://github.com/tmux-revamped/tmux-reorder-revamped) | tmuxのステータスバー上でウィンドウのタブをマウスでドラッグして、そのウィンドウを移動します |
| [`tmux-scroll-revamped`](https://github.com/tmux-revamped/tmux-scroll-revamped) | 自分でスクロールできるアプリにはマウスホイールを渡し、それ以外ではtmuxのコピーモードに入ります |
| [`tmux-sensible-revamped`](https://github.com/tmux-revamped/tmux-sensible-revamped) | tmuxのバージョンと端末に合わせて適用され、ユーザーが設定したオプションには触れない、妥当な初期設定です |
| [`tmux-tiling-revamped`](https://github.com/tmux-revamped/tmux-tiling-revamped) | tmuxのタイル型ウィンドウ管理です。BSPのdwindleとspiralを含む8つのレイアウトと、レイアウトの取り消しがあります |
| [`tmux-time-revamped`](https://github.com/tmux-revamped/tmux-time-revamped) | ステータスバーにローカル時計と世界時計を時間帯ごとの色で表示し、カウントダウンと夏時間の警告も出します |
| [`tmux-weather-revamped`](https://github.com/tmux-revamped/tmux-weather-revamped) | wttr.inの天気をバックグラウンドで取得し、ステータスバーを待たせずに表示します |

### インストールの確認

全メンバーがディスク上にあれば、1 つのコマンドでメンバー間の衝突を報告できます。

```sh
family/bin/doctor --live
```

各メンバーと実行中の tmux サーバーを読み取り、重複したキー、重複したステータスのプレースホルダー、命名規則に合わないオプション、規約のバージョンが古いメンバーを報告します。

<!-- family:end -->
