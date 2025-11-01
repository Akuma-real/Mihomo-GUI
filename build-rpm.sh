#!/usr/bin/env bash
set -euo pipefail

# 便捷包装：在仓库根目录直接构建 RPM
# 仍复用 packaging/rpm/build.sh 的完整逻辑与参数
# 用法示例：
#   CHANNEL=alpha ./build-rpm.sh
#   CHANNEL=stable ./build-rpm.sh
#   CHANNEL=tag TAG_NAME=v1.19.15 ./build-rpm.sh

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="${ROOT_DIR}/packaging/rpm/build.sh"

if [ ! -x "$SCRIPT" ]; then
  echo "未找到或不可执行：$SCRIPT" >&2
  echo "请确认仓库完整且已赋权：chmod +x packaging/rpm/build.sh" >&2
  exit 1
fi

exec "$SCRIPT" "$@"

