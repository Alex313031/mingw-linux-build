#!/bin/bash

export HERE=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
ROOT_PATH="$HERE/build"
SRC_PATH="$ROOT_PATH/src"

apply_patches() {
    printf "Applying patches\n"
    mkdir -p $SRC_PATH/patches/ &&
    cp -f -v $HERE/patches/*.patch $SRC_PATH/patches/ &&
    cd $SRC_PATH/binutils &&
    git apply --reject ../patches/binutils-dlltool-zero-ordinals.patch &&
    cd $SRC_PATH/gcc &&
    git apply --reject ../patches/gcc-stdcall-align.patch &&
    git apply --reject ../patches/gcc-trap-terminate.patch &&
    #git apply --reject ../patches/gdb-alternate-main.patch &&
    cd $SRC_PATH/mingw-w64 &&
    git apply --reject ../patches/gendef-no-comment.patch &&
    git apply --reject ../patches/rand_s-win2k.patch &&
    touch $SRC_PATH/patches/applied_patches &&
    cd $HERE
}

apply_patches; exit 0;

