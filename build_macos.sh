#!/bin/bash
# build_macos.sh — 在 macOS / GitHub Actions 上产出 arm64 + arm64e 的 qmvcam.dylib 并打 deb
#
# 为什么必须 macOS：Windows 的 ld64.lld 不支持 arm64e 认证指针重定位
#   (INVALID relocation has invalid width of 8 bytes @ __DATA,__objc_const)，
#   而这台 A13 机器的注入链只接受真 arm64e 镜像。
#
# 产物：dist/com.taokk3.qianmian_<ver>.deb  （xz + 单目录 + qmvcam.dylib，ident 与文件名一致）
set -euo pipefail
cd "$(dirname "$0")"

SDK="${SDK:-$(xcrun --sdk iphoneos --show-sdk-path)}"
MIN_IOS="${MIN_IOS:-16.0}"
VERSION="${VERSION:-4.1.0}"
OUT=build
NAME=qmvcam
mkdir -p "$OUT"

echo "== toolchain =="
xcodebuild -version || true
echo "SDK     = $SDK"
echo "MIN_IOS = $MIN_IOS"
echo "VERSION = $VERSION"

COMMON=(
  -isysroot "$SDK"
  -fobjc-arc -O2 -DNDEBUG
  -fno-exceptions -fobjc-runtime=ios-16.0
  -I src -I src/shim
  -Wall -Wno-unused-variable -Wno-unused-function -Wno-deprecated-declarations
  -Wno-nullability-completeness -Wno-objc-method-access
)

FRAMEWORKS=(
  -framework Foundation -framework UIKit -framework AVFoundation
  -framework CoreMedia -framework CoreVideo -framework VideoToolbox
  -framework CoreImage -framework Metal -framework QuartzCore
  -framework IOSurface -framework Security -framework IOKit
  -framework Vision -framework Accelerate -framework PhotosUI
  -framework ImageIO -framework CoreGraphics
)

SRCS=(src/*.m)
SLICES=()

for ARCH in arm64 arm64e; do
  OBJDIR="$OUT/obj-$ARCH"
  mkdir -p "$OBJDIR"
  OBJS=()
  for s in "${SRCS[@]}"; do
    o="$OBJDIR/$(basename "${s%.m}").o"
    clang -target "$ARCH-apple-ios$MIN_IOS" "${COMMON[@]}" -c "$s" -o "$o"
    OBJS+=("$o")
  done

  SLICE="$OUT/$NAME-$ARCH.dylib"
  clang -target "$ARCH-apple-ios$MIN_IOS" -isysroot "$SDK" -dynamiclib \
        -o "$SLICE" "${OBJS[@]}" \
        "${FRAMEWORKS[@]}" \
        -Wl,-install_name,@rpath/$NAME.dylib \
        -Wl,-undefined,dynamic_lookup \
        -Wl,-rpath,@loader_path/.jbroot/Library/Frameworks \
        -Wl,-rpath,@loader_path/.jbroot/usr/lib \
        -Wl,-rpath,@loader_path/Library/Frameworks \
        -Wl,-rpath,@loader_path/usr/lib
  codesign --force --sign - --timestamp=none --identifier "$NAME.dylib" "$SLICE" 2>/dev/null || true
  SLICES+=("$SLICE")
  echo "built $SLICE"
done

FAT="$OUT/$NAME.dylib"
lipo -create "${SLICES[@]}" -output "$FAT"
lipo -info "$FAT"
codesign --force --sign - --timestamp=none --identifier "$NAME.dylib" "$FAT" 2>/dev/null || true

echo "== verify =="
python3 tools/check_sign.py "$FAT"
python3 tools/mk_macos_deb.py "$FAT" "$VERSION"
ls -l dist/
