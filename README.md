# Oroma FFmpeg

The FFmpeg libraries that ship with Oroma, a design and motion editor by Getvate, and their source.

FFmpeg is licensed under the GNU Lesser General Public License version 2.1 or later. FFmpeg is a trademark of Fabrice
Bellard. Getvate does not own FFmpeg. This repository is where Oroma's FFmpeg build, its exact source and its build
instructions are published, as the LGPL requires.

## What each release holds

- `ffmpeg-<version>-<rid>.zip` for `osx-arm64`, `osx-x64`, `linux-x64` and `win-x64`:
  - `native/`: the shared libraries (`libavcodec` and the rest) and the `ffmpeg` and `ffprobe` commands.
  - `ffmpeg/`: FFmpeg's `LICENSE.md` and `COPYING.LGPLv2.1`, the exact configure line in `CONFIGURE.txt`, and the
    license of each library built in (libvpx, Opus, libwebp, dav1d). The Windows zip also carries the MinGW
    runtime DLLs the build links (libgcc under the GCC Runtime Library Exception, winpthreads, zlib), and the Linux
    zip carries libva (MIT); their licenses are in `ffmpeg/licenses`.
- `ffmpeg-<version>-source-offer.zip`: the unmodified FFmpeg source tarball, the source tarball of each library built in,
  this build script, `SOURCES.md` (every source with its SHA-256) and `PATCHES.md`. No patches are applied.

## How it is built

From the official FFmpeg release tarball, as shared libraries, with `--disable-gpl --disable-nonfree` and without
OpenH264, x264, x265, Xvid or fdk-aac. H.264 encoding uses the operating system's encoder: VideoToolbox on macOS,
Media Foundation on Windows, VAAPI on Linux. The build fails if `ffmpeg -buildconf` or `ffmpeg -encoders` lists any
GPL, nonfree or excluded part.

Build one platform yourself, natively on that platform:

```bash
./build-ffmpeg.sh osx-arm64        # or osx-x64, linux-x64, win-x64 (in an MSYS2 MINGW64 shell)
./build-ffmpeg.sh source-offer     # the source offer zip
```

It needs curl, cmake, meson, ninja, nasm, pkg-config, make and zip, and patchelf on Linux. The FFmpeg version and the
release tag are in `release.env`.

## Use your own FFmpeg in Oroma

The libraries are separate files, so you can replace them with your own build. Set `OROMA_FFMPEG_DIR` to a folder
holding your libraries and the `ffmpeg` command before you start Oroma. Their major versions must match the ones in
the release (FFmpeg 9.0: `libavcodec` 63).

## License

The files in this repository (the build script, the workflow and this README) are licensed under the GNU Lesser
General Public License version 2.1 or later; see `LICENSE`. FFmpeg and each library built into it keep their own
licenses, shipped in every release zip.
