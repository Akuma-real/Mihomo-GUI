#!/usr/bin/env bash
set -Eeuo pipefail

# 该脚本在当前仓库内本地构建 RPM：
# - 下载并解压上游预编译二进制到 rpmbuild/SOURCES/mihomo
# - 调用 rpmbuild 使用 packaging/rpm/mihomo.spec 产物

: "${REPO:=MetaCubeX/mihomo}"
: "${CHANNEL:=alpha}"          # alpha | stable | tag
: "${TAG_NAME:=}"              # CHANNEL=tag 时指定，如 v1.19.15
: "${PREFER_TIER:=auto}"       # auto|v3|v2|v1（仅 x86_64 生效）
: "${GVISOR:=keep}"            # keep|with|without|any
# 交叉打包支持
: "${FORCE_ARCH:=}"            # 覆盖目标架构：amd64|arm64|armv7
: "${RPM_TARGET:=}"            # rpmbuild --target 值（默认随 FORCE_ARCH 推断）
: "${GH_TOKEN:=}"              # 可选：提升 API 限额

need() { command -v "$1" >/dev/null 2>&1 || { echo "缺少依赖：$1" >&2; exit 1; }; }
for c in curl jq rpmbuild file; do need "$c"; done
command -v xz >/dev/null 2>&1 || true
command -v gzip >/dev/null 2>&1 || true

workdir=$(pwd)
TOPDIR="$workdir/rpmbuild"
SOURCES="$TOPDIR/SOURCES"
mkdir -p "$TOPDIR"/{BUILD,RPMS,SOURCES,SPECS,SRPMS}

API_URL=
case "$CHANNEL" in
  alpha)  API_URL="https://api.github.com/repos/${REPO}/releases/tags/Prerelease-Alpha" ;;
  stable) API_URL="https://api.github.com/repos/${REPO}/releases/latest" ;;
  tag)    [ -n "$TAG_NAME" ] || { echo "CHANNEL=tag 需设置 TAG_NAME" >&2; exit 1; }
          API_URL="https://api.github.com/repos/${REPO}/releases/tags/${TAG_NAME}" ;;
  *) echo "未知 CHANNEL=${CHANNEL}" >&2; exit 1 ;;
esac

ua=( -H "User-Agent: mihomo-rpm-build" -H "Accept: application/vnd.github+json" )
auth=()
[ -n "$GH_TOKEN" ] && auth=( -H "Authorization: Bearer ${GH_TOKEN}" )

tmp=$(mktemp -d -t mihomo-rpm-XXXXXX)
trap 'rm -rf "$tmp"' EXIT

curl -fsSL --retry 5 --retry-all-errors --retry-delay 2 \
  "${ua[@]}" "${auth[@]}" -o "$tmp/release.json" "$API_URL"

tag=$(jq -r '.tag_name // empty' "$tmp/release.json")
[ -n "$tag" ] || { echo "解析 tag 失败" >&2; exit 1; }

# 架构与偏好
uname_m=$(uname -m)
declare -a patterns

# 统一的选择用机器架构（可被 FORCE_ARCH 覆盖）
MACHINE_FOR_SELECT="$uname_m"
case "$FORCE_ARCH" in
  amd64) MACHINE_FOR_SELECT=x86_64 ;;
  arm64) MACHINE_FOR_SELECT=aarch64 ;;
  armv7) MACHINE_FOR_SELECT=armv7l ;;
  "" ) : ;;
  *) echo "不支持的 FORCE_ARCH=$FORCE_ARCH" >&2; exit 1 ;;
esac

build_patterns() {
  patterns=()
  shopt -s nocasematch
  case "$MACHINE_FOR_SELECT" in
    x86_64)
      local cpu_flags supports_avx2=0 supports_avx=0
      cpu_flags=$(grep -m1 -i '^flags' /proc/cpuinfo 2>/dev/null || true)
      echo "$cpu_flags" | grep -qw avx2 && supports_avx2=1
      echo "$cpu_flags" | grep -qw avx && supports_avx=1
      local tiers=()
      case "$PREFER_TIER" in
        v3) tiers=(v3 v2 v1);;
        v2) tiers=(v2 v1);;
        v1) tiers=(v1);;
        auto|*)
          if [ "$supports_avx2" = 1 ]; then tiers=(v3 v2 v1);
          elif [ "$supports_avx" = 1 ]; then tiers=(v2 v1);
          else tiers=(v1); fi;;
      esac
      # gVisor 偏好：默认保持 keep
      local gseq=()
      case "$GVISOR" in
        with) gseq=(gvisor "");;
        without) gseq=("" gvisor);;
        any) gseq=("" gvisor);;
        keep|*) gseq=("" gvisor);; # 无法读取已装版本，构建时使用通用顺序
      esac
      local t g
      for t in "${tiers[@]}"; do
        for g in "${gseq[@]}"; do
          if [ -n "$g" ]; then patterns+=("linux.*amd64.*${t}.*${g}"); else patterns+=("linux.*amd64.*${t}"); fi
        done
      done
      # 兜底
      for g in "${gseq[@]}"; do [ -n "$g" ] && patterns+=("linux.*amd64.*${g}") || patterns+=("linux.*amd64"); done
      ;;
    aarch64|arm64)
      patterns=( 'linux.*arm64' ) ;;
    armv7l|armv7)
      patterns=( 'linux.*armv7' ) ;;
    *) echo "暂不支持的架构：$uname_m" >&2; exit 1 ;;
  esac
  shopt -u nocasematch
}

is_linux_gz_xz() {
  local name="$1"
  shopt -s nocasematch
  if [[ "$name" =~ linux ]] && [[ "$name" =~ \.(gz|xz)$ ]]; then
    [[ "$name" =~ \.(deb|rpm|pkg\.tar\.zst)$ ]] && { shopt -u nocasematch; return 1; }
    shopt -u nocasematch; return 0
  fi
  shopt -u nocasematch; return 1
}

mapfile -t assets < <(jq -r '(.assets // [])[]? | select(.name and .browser_download_url) | "\(.name)\t\(.browser_download_url)"' "$tmp/release.json")
[ ${#assets[@]} -gt 0 ] || { echo "该 release 无资产" >&2; exit 1; }

build_patterns

chosen=""
shopt -s nocasematch
for pat in "${patterns[@]}"; do
  for line in "${assets[@]}"; do
    name="${line%%$'\t'*}"; url="${line#*$'\t'}"
    is_linux_gz_xz "$name" || continue
    [[ "$name" =~ $pat ]] || continue
    chosen="$name	$url"; break 2
  done
done
if [ -z "$chosen" ]; then
  # 兜底，同架构但不限定 tier/gvisor
  for line in "${assets[@]}"; do
    name="${line%%$'\t'*}"; url="${line#*$'\t'}"
    is_linux_gz_xz "$name" || continue
  case "$MACHINE_FOR_SELECT" in
  x86_64) [[ "$name" =~ linux.*amd64 ]] || continue ;;
  aarch64|arm64) [[ "$name" =~ linux.*arm64 ]] || continue ;;
  armv7l|armv7) [[ "$name" =~ linux.*armv7 ]] || continue ;;
esac
    chosen="$name	$url"; break
  done
fi
shopt -u nocasematch

[ -n "$chosen" ] || { echo "未找到匹配资产" >&2; exit 1; }
asset_name="${chosen%%$'\t'*}"
asset_url="${chosen#*$'\t'}"
echo "选择资产：$asset_name" >&2

# 可能存在的 checksums 与 version.txt
checksums_url=$(jq -r '(.assets // [])[]? | select((try (.name|test("checksums";"i")) catch false) and .browser_download_url) | .browser_download_url' "$tmp/release.json" | head -n1 || true)
verline=""
version_txt_url=$(jq -r '(.assets // [])[]? | select(.name=="version.txt") | .browser_download_url // empty' "$tmp/release.json")
if [ -n "$version_txt_url" ]; then
  curl -fsSL -o "$tmp/version.txt" "$version_txt_url" || true
  verline=$(tr -d '\r' < "$tmp/version.txt" | head -n1 || true)
fi

mkdir -p "$SOURCES"
curl -fsSL --retry 5 --retry-all-errors --retry-delay 2 -o "$tmp/asset" "$asset_url"

# 校验（若有 checksums）
if [ -n "$checksums_url" ]; then
  curl -fsSL -o "$tmp/checksums.txt" "$checksums_url" || true
  if [ -s "$tmp/checksums.txt" ] && grep -Fq "$asset_name" "$tmp/checksums.txt"; then
    expected=$(grep -F "$asset_name" "$tmp/checksums.txt" | head -n1 | awk '{print $1}')
    actual=$(sha256sum "$tmp/asset" | awk '{print $1}')
    [ "$expected" = "$actual" ] || { echo "SHA256 校验失败" >&2; exit 1; }
    echo "校验通过" >&2
  fi
fi

# 解压得到可执行文件 SOURCES/mihomo
if [[ "$asset_name" =~ \.xz$ ]]; then
  xz -dc "$tmp/asset" > "$SOURCES/mihomo"
else
  gunzip -c "$tmp/asset" > "$SOURCES/mihomo"
fi
chmod +x "$SOURCES/mihomo"
file -b "$SOURCES/mihomo" | grep -qi 'ELF' || { echo "解压结果不是 ELF" >&2; exit 1; }

# 计算 RPM 版本/发布号
VER=0
REL=1
BUILDTAG=$(date +%Y%m%d)
case "$CHANNEL" in
  stable|tag)
    # 例如 v1.19.0 -> 1.19.0
    VER=$(echo "$tag" | sed -E 's/^v//')
    REL=1
    ;;
  alpha)
    VER=0
    if [ -n "$verline" ]; then
      # verline 如：alpha-deadbeef，作为 release 后缀
      REL="0.alpha${BUILDTAG}."$(echo "$verline" | sed -E 's/[^A-Za-z0-9]+/_/g')
    else
      REL="0.alpha${BUILDTAG}"
    fi
    ;;
esac

# 复制 spec 与附属源文件
cp -f "$workdir/packaging/rpm/mihomo.spec" "$TOPDIR/SPECS/"
cp -f "$workdir/packaging/rpm/mihomo.service" "$SOURCES/"
cp -f "$workdir/packaging/rpm/mihomo.desktop" "$SOURCES/"
cp -f "$workdir/packaging/rpm/mihomo-gui" "$SOURCES/"
cp -f "$workdir/packaging/rpm/mihomo-control" "$SOURCES/"
cp -f "$workdir/packaging/rpm/mihomo-control.desktop" "$SOURCES/"
cp -f "$workdir/packaging/rpm/mihomo-control-pkexec" "$SOURCES/"
cp -f "$workdir/packaging/rpm/sysconfig.mihomo" "$SOURCES/"

echo "将构建 Version=${VER} Release=${REL}" >&2

if [ -z "$RPM_TARGET" ]; then
  case "$FORCE_ARCH" in
    amd64|'') RPM_TARGET=x86_64 ;;
    arm64)    RPM_TARGET=aarch64 ;;
    armv7)    RPM_TARGET=armv7hl ;;
  esac
fi

rpmbuild -bb "$TOPDIR/SPECS/mihomo.spec" \
  -D "_topdir $TOPDIR" \
  -D "ver $VER" \
  -D "rel $REL" \
  -D "buildtag $BUILDTAG" \
  -D "debug_package %{nil}" \
  --target "$RPM_TARGET"

echo
echo "构建完成。生成的 RPM 位于："
find "$TOPDIR/RPMS" -type f -name "*.rpm" -printf "%p\n"
