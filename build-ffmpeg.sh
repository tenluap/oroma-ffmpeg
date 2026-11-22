#!/usr/bin/env bash
# Builds Oroma's LGPL FFmpeg for one RID and packs it as ffmpeg-<version>-<rid>.zip, the file Oroma's
# build/OromaFFmpeg.targets downloads from this repository's releases:
#   native/   the shared libraries and the ffmpeg and ffprobe commands (runtimes/<rid>/native in the app)
#   ffmpeg/   LICENSE.md, COPYING.LGPLv2.1, CONFIGURE.txt and licenses/ (each external library's license)
#
# Usage:
#   ./build-ffmpeg.sh <osx-arm64|osx-x64|linux-x64|win-x64> [out-dir]
#   ./build-ffmpeg.sh source-offer [out-dir]     the source offer: every tarball, this script, the patch log
#
# The version and release tag are in release.env.
#
# Runs natively on each platform: macOS with Xcode, Linux with gcc, Windows in an MSYS2 MINGW64 shell. Needs curl,
# cmake, meson, ninja, nasm, pkg-config, make, zip (and patchelf on Linux). .github/workflows/ffmpeg.yml runs it.
set -euo pipefail

RID="${1:?usage: build-ffmpeg.sh <osx-arm64|osx-x64|linux-x64|win-x64|source-offer> [out-dir]}"
ROOT="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "${2:-$ROOT/artifacts}"
OUT="$(cd "${2:-$ROOT/artifacts}" && pwd)"
# FFMPEG_VERSION must match the FFmpeg.AutoGen bindings Oroma uses (OromaFFmpegVersion in Oroma's Directory.Build.props).
# shellcheck source=release.env
. "$ROOT/release.env"
VERSION="$FFMPEG_VERSION"
WORK="${WORK:-$ROOT/obj/ffmpeg-build/$RID}"
SRC="$WORK/src"
PREFIX="$WORK/deps"
INSTALL="$WORK/install"
JOBS="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)"

# Upstream release tarballs, pinned by SHA-256. Changing FFMPEG_VERSION in release.env needs its new hash here.
SOURCES=(
  "ffmpeg|https://ffmpeg.org/releases/ffmpeg-$VERSION.tar.xz|8c3850283eb25fa026482078a04051e0be17347b09ef81a0849bec15a96e002e"
  "dav1d|https://downloads.videolan.org/pub/videolan/dav1d/1.5.4/dav1d-1.5.4.tar.xz|686616b7c69eb88d44459391ab25cac13b6647a3b288835c5784e71c1514a5c5"
  "libvpx|https://github.com/webmproject/libvpx/archive/refs/tags/v1.17.0.tar.gz|1020f184046187baa2985dbde38e0691f49c44088bca7a1842b0236c6081dc0a"
  "libwebp|https://storage.googleapis.com/downloads.webmproject.org/releases/webp/libwebp-1.6.0.tar.gz|e4ab7009bf0629fd11982d4c2aa83964cf244cffba7347ecd39019a9e38c4564"
  "opus|https://downloads.xiph.org/releases/opus/opus-1.6.1.tar.gz|6ffcb593207be92584df15b32466ed64bbec99109f007c82205f0194572411a1"
)

# Never in a shipped build: GPL, nonfree, or encoders with their own licensing (Oroma's LgplCheck.Forbidden matches).
FORBIDDEN=(--enable-gpl --enable-nonfree libx264 libx265 libxvid libfdk libopenh264)

log() { printf '[build-ffmpeg] %s\n' "$*" >&2; }

sha256() { if command -v sha256sum >/dev/null; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi; }

# Downloads every source into $SRC/tarballs and checks its hash.
fetch() {
  mkdir -p "$SRC/tarballs"
  local entry name url hash file got
  for entry in "${SOURCES[@]}"; do
    IFS='|' read -r name url hash <<<"$entry"
    file="$SRC/tarballs/$(basename "$url")"
    if [ ! -f "$file" ]; then
      log "Downloading $url"
      curl -fsSL --retry 3 -o "$file.part" "$url"
      mv "$file.part" "$file"
    fi
    got="$(sha256 "$file")"
    [ "$got" = "$hash" ] || { log "SHA-256 mismatch for $url: expected $hash, got $got"; exit 1; }
  done
}

# Unpacks the source called $1 into $SRC/$1 and prints that folder.
unpack() {
  local entry name url hash
  for entry in "${SOURCES[@]}"; do
    IFS='|' read -r name url hash <<<"$entry"
    [ "$name" = "$1" ] || continue
    rm -rf "${SRC:?}/$name"
    mkdir -p "$SRC/$name"
    tar -xf "$SRC/tarballs/$(basename "$url")" -C "$SRC/$name" --strip-components=1
    printf '%s\n' "$SRC/$name"
    return
  done
  log "Unknown source $1"
  exit 1
}

sources_list() {
  local entry name url hash
  for entry in "${SOURCES[@]}"; do
    IFS='|' read -r name url hash <<<"$entry"
    echo "- $name: $url (sha256 $hash)"
  done
}

if [ "$RID" = "source-offer" ]; then
  fetch
  STAGE="$WORK/offer/ffmpeg-$VERSION-source-offer"
  rm -rf "$WORK/offer"
  mkdir -p "$STAGE"
  cp "$SRC"/tarballs/* "$STAGE/"
  cp "$0" "$STAGE/build-ffmpeg.sh"
  cp "$ROOT/release.env" "$ROOT/README.md" "$STAGE/"
  printf '# Patches\n\nOroma applies no patches to FFmpeg %s or to the libraries built into it.\n' "$VERSION" >"$STAGE/PATCHES.md"
  {
    printf '# Sources\n\n'
    sources_list
    printf '\nBuild each platform with: build-ffmpeg.sh <rid>. Each build zip holds its configure line in ffmpeg/CONFIGURE.txt.\n'
  } >"$STAGE/SOURCES.md"
  rm -f "$OUT/ffmpeg-$VERSION-source-offer.zip"
  (cd "$WORK/offer" && zip -qr "$OUT/ffmpeg-$VERSION-source-offer.zip" "ffmpeg-$VERSION-source-offer")
  log "Wrote $OUT/ffmpeg-$VERSION-source-offer.zip"
  exit 0
fi

EXTRA=()
CMAKE_ARCH=()
case "$RID" in
  osx-arm64|osx-x64)
    if [ "$RID" = osx-arm64 ]; then ARCH=arm64; else ARCH=x86_64; fi
    [ "$(uname -m)" = "$ARCH" ] || { log "Build $RID on a $ARCH Mac (this one is $(uname -m))."; exit 1; }
    export MACOSX_DEPLOYMENT_TARGET=11.0
    export CFLAGS="-arch $ARCH -mmacosx-version-min=11.0"
    export LDFLAGS="-arch $ARCH -mmacosx-version-min=11.0"
    CMAKE_ARCH=(-DCMAKE_OSX_ARCHITECTURES="$ARCH" -DCMAKE_OSX_DEPLOYMENT_TARGET=11.0)
    # @loader_path: each library finds the others beside it, so the folder can be swapped as a whole.
    EXTRA=(--enable-videotoolbox --enable-audiotoolbox --enable-pthreads --enable-zlib --install-name-dir=@loader_path)
    ;;
  linux-x64)
    EXTRA=(--enable-vaapi --enable-pthreads --enable-zlib)
    ;;
  win-x64)
    EXTRA=(--enable-mediafoundation --enable-w32threads --enable-zlib)
    ;;
  *)
    log "Unknown RID $RID"
    exit 1
    ;;
esac

fetch
rm -rf "$PREFIX" "$INSTALL"
mkdir -p "$PREFIX" "$INSTALL"
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig"

CMAKE=(-G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$PREFIX" -DCMAKE_INSTALL_LIBDIR=lib
  -DBUILD_SHARED_LIBS=OFF -DCMAKE_POSITION_INDEPENDENT_CODE=ON "${CMAKE_ARCH[@]}")

log "opus"
dir="$(unpack opus)"
cmake -S "$dir" -B "$dir/build" "${CMAKE[@]}" -DOPUS_BUILD_PROGRAMS=OFF -DOPUS_BUILD_TESTING=OFF >/dev/null
cmake --build "$dir/build" --target install >/dev/null

log "libwebp"
dir="$(unpack libwebp)"
cmake -S "$dir" -B "$dir/build" "${CMAKE[@]}" -DWEBP_BUILD_ANIM_UTILS=OFF -DWEBP_BUILD_CWEBP=OFF -DWEBP_BUILD_DWEBP=OFF \
  -DWEBP_BUILD_GIF2WEBP=OFF -DWEBP_BUILD_IMG2WEBP=OFF -DWEBP_BUILD_VWEBP=OFF -DWEBP_BUILD_WEBPINFO=OFF \
  -DWEBP_BUILD_WEBPMUX=OFF -DWEBP_BUILD_EXTRAS=OFF >/dev/null
cmake --build "$dir/build" --target install >/dev/null

log "dav1d"
dir="$(unpack dav1d)"
meson setup "$dir/build" "$dir" --prefix="$PREFIX" --libdir=lib --buildtype=release --default-library=static \
  -Denable_tools=false -Denable_tests=false >/dev/null
ninja -C "$dir/build" install >/dev/null

log "libvpx"
dir="$(unpack libvpx)"
(cd "$dir" && ./configure --prefix="$PREFIX" --disable-examples --disable-tools --disable-docs --disable-unit-tests \
  --enable-pic --enable-vp9-highbitdepth >/dev/null && make -j"$JOBS" >/dev/null && make install >/dev/null)

log "FFmpeg $VERSION"
dir="$(unpack ffmpeg)"
CONFIGURE=(
  --prefix="$INSTALL"
  --enable-shared --disable-static
  --disable-gpl --disable-nonfree
  --disable-doc --disable-debug --disable-ffplay --disable-autodetect
  --pkg-config-flags=--static
  --enable-libvpx --enable-libopus --enable-libwebp --enable-libdav1d
  --extra-cflags="-I$PREFIX/include"
  --extra-ldflags="-L$PREFIX/lib"
  "${EXTRA[@]}"
)
if ! (cd "$dir" && ./configure "${CONFIGURE[@]}" >"$WORK/configure.log" 2>&1); then
  tail -40 "$WORK/configure.log" >&2
  exit 1
fi
make -C "$dir" -j"$JOBS" >/dev/null
make -C "$dir" install >/dev/null

# The shortest of a library's names is the one FFmpeg.AutoGen loads (libavcodec.63.dylib, libavcodec.so.63).
shortest() { ls -1 "$@" | awk '{ print length, $0 }' | sort -n | head -1 | cut -d' ' -f2-; }

STAGE="$WORK/stage"
rm -rf "$STAGE"
mkdir -p "$STAGE/native" "$STAGE/ffmpeg/licenses"
LIBS=(avcodec avformat avutil avfilter avdevice swscale swresample)
case "$RID" in
  osx-*)
    for lib in "${LIBS[@]}"; do cp -L "$(shortest "$INSTALL/lib/lib$lib".*.dylib)" "$STAGE/native/"; done
    cp "$INSTALL/bin/ffmpeg" "$INSTALL/bin/ffprobe" "$STAGE/native/"
    FFMPEG="$STAGE/native/ffmpeg"
    ;;
  linux-x64)
    for lib in "${LIBS[@]}"; do cp -L "$(shortest "$INSTALL/lib/lib$lib".so.*)" "$STAGE/native/"; done
    cp "$INSTALL/bin/ffmpeg" "$INSTALL/bin/ffprobe" "$STAGE/native/"
    # Each library and command finds the others beside it.
    for f in "$STAGE"/native/*; do patchelf --set-rpath "\$ORIGIN" "$f"; done
    FFMPEG="$STAGE/native/ffmpeg"
    ;;
  win-x64)
    cp "$INSTALL"/bin/*.dll "$INSTALL/bin/ffmpeg.exe" "$INSTALL/bin/ffprobe.exe" "$STAGE/native/"
    FFMPEG="$STAGE/native/ffmpeg.exe"
    ;;
esac

BUILDCONF="$("$FFMPEG" -hide_banner -buildconf)"
ENCODERS="$("$FFMPEG" -hide_banner -encoders)"
for flag in "${FORBIDDEN[@]}"; do
  if grep -q -- "$flag" <<<"$BUILDCONF$ENCODERS"; then
    log "The build has $flag: it must not ship."
    exit 1
  fi
done
"$FFMPEG" -hide_banner -L | grep -q "Lesser General Public" || { log "ffmpeg -L does not report the LGPL."; exit 1; }

cp "$dir/LICENSE.md" "$dir/COPYING.LGPLv2.1" "$STAGE/ffmpeg/"
{
  printf 'Oroma FFmpeg %s for %s\n\nConfigure line:\n  %s\n\nffmpeg -buildconf:\n%s\n\nSources:\n' "$VERSION" "$RID" "${CONFIGURE[*]}" "$BUILDCONF"
  sources_list
  printf '\nPatches: none.\n'
} >"$STAGE/ffmpeg/CONFIGURE.txt"
cp "$SRC/opus/COPYING" "$STAGE/ffmpeg/licenses/opus-COPYING.txt"
cp "$SRC/libwebp/COPYING" "$STAGE/ffmpeg/licenses/libwebp-COPYING.txt"
cp "$SRC/libwebp/PATENTS" "$STAGE/ffmpeg/licenses/libwebp-PATENTS.txt"
cp "$SRC/libvpx/LICENSE" "$STAGE/ffmpeg/licenses/libvpx-LICENSE.txt"
cp "$SRC/libvpx/PATENTS" "$STAGE/ffmpeg/licenses/libvpx-PATENTS.txt"
cp "$SRC/dav1d/COPYING" "$STAGE/ffmpeg/licenses/dav1d-COPYING.txt"

ZIP="$OUT/ffmpeg-$VERSION-$RID.zip"
rm -f "$ZIP"
(cd "$STAGE" && zip -qr "$ZIP" native ffmpeg)
log "Wrote $ZIP"
printf 'OromaFFmpegSha256_%s=%s\n' "${RID//-/_}" "$(sha256 "$ZIP")"
