#!/bin/sh
# `textstack` コマンドを入れる（パイプで渡すための入口）。
#
#   sh scripts/install-cli.sh              # /usr/local/bin/textstack へ
#   PREFIX=~/bin sh scripts/install-cli.sh # 置き場所を変える
#
# アプリ本体への symlink を張るだけ。アプリを更新しても張り直しは要らない。
#
#   kubectl logs -f pod/api | textstack     # パイプで渡す
#   textstack app.log.gz                    # gzip はそのまま開く
#   textstack < app.log                     # リダイレクトも同じ
#
# 外すとき: rm <PREFIX>/textstack
set -eu

APP="${APP:-/Applications/TextStack.app}"
PREFIX="${PREFIX:-/usr/local/bin}"
BIN="$APP/Contents/MacOS/TextStack"

[ -x "$BIN" ] || { echo "TextStack.app が $APP に見つからない。APP=... で場所を渡す。" >&2; exit 1; }
mkdir -p "$PREFIX"
ln -sf "$BIN" "$PREFIX/textstack"

echo "ok    $PREFIX/textstack → $BIN"
case ":$PATH:" in
  *":$PREFIX:"*) ;;
  *) echo "警告  $PREFIX が PATH に無い。シェルの設定に足すこと。" ;;
esac
