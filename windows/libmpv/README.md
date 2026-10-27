# 自前ビルドの libmpv (Windows)

`libmpv-2.dll` は media_kit 同梱版ではなく、FFmpeg のフィルタ(`yadif` / `bwdif` / `scale` / `format` / `null` / `setsar` / `fps`)を
有効にして自前ビルドしたものです。同梱版は `--disable-filters` のため、1080i のインターレース解除に使える
フィルタが1つも入っていません。

`windows/CMakeLists.txt` が、プラグインの同梱リスト内の `libmpv-2.dll` をこのファイルに差し替えます。

- SHA-256: `941a4030942cc1131b85db98564ff28de78d0a6376129d13ad533633f1ec324a`
- mpv: be6c22f93b(2024-03-01 時点の master)、FFmpeg ea3d24bbe3(media-kit のレシピ指定)
- 対象: x86_64 / mingw-w64 GCC 13.2.0(クロスコンパイル)

## ビルド手順(WSL Debian)

ベースは <https://github.com/media-kit/libmpv-win32-video-build> (shinchiro/mpv-winbuild-cmake の派生)。
2024-02-29 時点のレシピは、上流の変更で次の修正が必要でした。

1. `packages/ffmpeg.cmake` の `--enable-filter=overlay` の並びに `yadif bwdif scale format null setsar fps` を追加、`libvpl` を外す
2. CMake は 3.26.4 に固定(`pip install cmake==3.26.4`)、`cmake/download_externalproject.cmake` のモジュール取得URLも `v3.26.4` に
3. `CMakeLists.txt` の meson バージョン判定を `VERSION_LESS` に修正(meson 1.12 が数値比較で弾かれる)
4. gcc は削除済みスナップショットをやめ、リリース 13.2.0 に変更(`toolchain/gcc/gcc.cmake`)
5. `main`/`master`/`dev` 追従のパッケージ(約80個)を、2024-03-01 時点の最終コミットSHAに固定。
   固定コミットでは `GIT_REMOTE_NAME` を外す(追跡ブランチ `@{u}` が無く force-update が失敗するため)
6. `git am` を使うパッチは `apply_patches.sh <sha> <patch...>` 経由にして冪等化(`exec.in` が `eval $*` のため)
7. opus は v1.4、mbedtls は v3.5.2 に固定。`lzo` は配布元を変更
8. 追加パッケージ: `python3-jsonschema python3-jinja2 rst2pdf python3-docutils`
9. OOM 対策: `-DMAKEJOBS=4`、`ninja -j 4`(WSL のメモリ 15GB で 40 並列は固まる)

```
cmake -DTARGET_ARCH=x86_64-w64-mingw32 -DSINGLE_SOURCE_LOCATION=$PWD/src_packages \
      -DRUSTUP_LOCATION=$PWD/clang_root/install_rustup -DENABLE_CCACHE=ON -DMAKEJOBS=4 \
      --fresh -G Ninja -B build_x86_64 -S $PWD
ninja -C build_x86_64 download && ninja -C build_x86_64 gcc && ninja -C build_x86_64 update
ninja -j 4 -C build_x86_64 mpv && ninja -C build_x86_64 mpv-packaging
```

成果物は `build_x86_64/mpv-dev-x86_64-*.7z` の中の `libmpv-2.dll`。
