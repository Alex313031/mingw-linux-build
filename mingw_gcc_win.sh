#!/bin/bash

# Copyright (C) 2025 Kyle Schwarz <zeranoe@gmail.com>
# Copyright (C) 2026 Alex Frick <alex313031@gmail.com>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

SCRIPTNAME=$(basename "$0")
SCRIPTVER="2.1.7"

export HERE=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
ROOT_PATH="$HERE/build/win_gcc"
SRC_PATH="$ROOT_PATH/src"
BLD_PATH="$ROOT_PATH/bld"
LOG_FILE="$ROOT_PATH/build.log"

# Source URLs, using GitHub instead of originals for cloning speed
MINGW_W64_URL="https://github.com/mingw-w64/mingw-w64" # https://git.code.sf.net/p/mingw-w64/mingw-w64
BINUTILS_URL="https://github.com/rtems/sourceware-mirror-binutils-gdb" # https://git.sr.ht/~sourceware/binutils-gdb
GCC_URL="https://github.com/gcc-mirror/gcc" # https://git.sr.ht/~sourceware/gcc
# What branches to checkout
MINGW_W64_BRANCH="v14.x"
BINUTILS_BRANCH="binutils-2_46-branch"
GCC_BRANCH="releases/gcc-16"

# Controls minimum Windows target, should always be set non-zero later.
WIN32_WINNT="0"

# Thread model
ENABLE_THREADS="--enable-threads=posix"

# CRT compatibility. crtdll (win 95), or msvcrt (Win 98/NT 4.0 with update, 2000+)
LINKED_RUNTIME="msvcrt"

JOB_COUNT=$(getconf _NPROCESSORS_ONLN)

IS_DEBUG=false
USE_MMX=false
USE_SSE2=false
USE_SSE3=false
USE_SSE41=false
USE_SSE42=false
USE_AVX=false
USE_AVX2=false
USE_AVX512=false

# Colors
YEL='\033[1;33m' # Yellow
CYA='\033[1;96m' # Cyan
RED='\033[1;31m' # Red
GRE='\033[1;32m' # Green
c0='\033[0;00m'  # Reset Text
bold='\033[1;37m' # Bold Text
underline='\033[4m' # Underline Text

show_help() {
  cat <<EOF
Usage:
  $SCRIPTNAME <arch> [options]

Archs:
  i586         - Windows 32-bit for old CPUs without SSE (Intel Pentium (MMX), Pentium II, AMD K5, K6, K7)
  i686 | x32   - Windows 32-bit for CPUs with SSE (Intel Pentium III and newer, Athlon XP and newer)
  x86_64 | x64 - Windows 64-bit for CPUs with SSE2 (Intel Prescott, AMD K8 and newer)

Options:
  -h, --help                  Show this help.
  -v, --verbose               Log build output to the console as well as the build.log file.
  -a, --all                   Build all three archs: i586, i686 and x86_64.
  --version                   Show script version.
  --deps                      Install prerequisites for using this script (Ubuntu/Debian only).
  -j <count>, --jobs <count>  Override make job count. (default: $JOB_COUNT)
  --package                   After a successful build, zip each built arch into <root>/<arch>.zip (x86_64 becomes x64.zip).
  --prefix <path>             Change install location. (default: $ROOT_PATH/<arch>)
  --root <path>               Location for sources, build artifacts and the resulting compiler. (default: $ROOT_PATH)
  --keep-artifacts            Don't remove source and build files after a successful build.
  --disable-threads           Disable pthreads and STL <thread>.
  -c, --cached-sources        Use existing sources instead of downloading new ones and patching them.
  -d, --download-sources      Only download sources, then exit; for making local modifications.
  -p, --patch                 Only apply patches to already-downloaded sources, then exit; needs no arch.
  --clean                     Removes all sources and build artifacts, and output (keeps the previous build.log as build.log.old).
  --keep-src                  Like --clean but keeps the src/ tree (downloaded + patched sources), so a later build with -c skips re-downloading and re-patching.
  --binutils-url <url>        Set Binutils source URL, (default: $BINUTILS_URL)
  --binutils-branch <branch>  Set Binutils branch, (default: $BINUTILS_BRANCH)
  --gcc-url <url>             Set GCC source URL, (default: $GCC_URL)
  --gcc-branch <branch>       Set GCC branch, (default: $GCC_BRANCH)
  --mingw-url <url>           Set MinGW-w64 source url, (default: $MINGW_W64_URL)
  --mingw-branch <branch>     Set MinGW-w64 branch, (default: $MINGW_W64_BRANCH)
  --crtlib <runtime>          Set MinGW Linked CRT (crtdll, msvcrt, ucrt); should usually be left alone. (default: $LINKED_RUNTIME)
  --win32-winnt <version>     Set default _WIN32_WINNT value for minimum Windows version target. (default: $WIN32_WINNT)

Compilation Flags:
  --debug                     Create a debug build (default is release mode).
  --mmx                       Compile with MMX, only has an effect on i586 builds. (default: $USE_MMX)
  --sse2                      Compile with SSE2, only has an effect on i686 builds. (default: $USE_SSE2)
  --sse3                      Compile with SSE3, i686 & x86_64 (default: $USE_SSE3)
  --sse41                     Compile with SSE4.1, i686 & x86_64 (default: $USE_SSE41)
  --sse42                     Compile with SSE4.2, i686 & x86_64 (default: $USE_SSE42)
  --avx                       Compile with AVX, x86_64 only. (default: $USE_AVX)
  --avx2                      Compile with AVX2, x86_64 only. (default: $USE_AVX2)
  --avx512                    Compile with AVX-512, x86_64 only, experimental. (default: $USE_AVX512)

For possible _WIN32_WINNT values, see:
https://learn.microsoft.com/en-us/cpp/porting/modifying-winver-and-win32-winnt

EOF
}

show_version() {
  printf "\n %s Version %s \n\n" "$SCRIPTNAME" "$SCRIPTVER"
  exit 0
}

error_exit() {
  local error_msg="$1"
  shift 1

  if [ "$error_msg" ]; then
    log "${RED}%s${c0}\n" "$error_msg" >&2
  else
    log "${RED}An error occured.${c0}\n" >&2
  fi
  exit 1
}

arg_error() {
  local error_msg="$1"
  shift 1

  error_exit "$error_msg, see --help for options" "$error_msg"
}

execute() {
  local info_msg="$1"
  local error_msg="$2"
  shift 2

  if [ ! "$error_msg" ]; then
    error_msg="error"
  fi

  if [ "$info_msg" ]; then
    printf "${CYA}(%d/%d): %s${c0}\n" "$CURRENT_STEP" "$TOTAL_STEPS" "$info_msg"
    CURRENT_STEP=$((CURRENT_STEP + 1))
  fi
  if [ "$VERBOSE" == "1" ]; then
    # mirror output to the console as well as the log file
    # (process substitution keeps "$@"'s exit status, unlike a pipe to tee)
    "$@" > >(tee -a "$LOG_FILE") 2>&1 || error_exit "$error_msg, check $LOG_FILE for details."
  else
    "$@" >>"$LOG_FILE" 2>&1 || error_exit "$error_msg, check $LOG_FILE for details."
  fi
}

log() {
  # Print a message (printf-style: format then args) to the console with color,
  # and append a color-stripped copy to the log file so build.log stays clean.
  # Unlike execute(), it runs no command and does no error handling. The log
  # write is skipped until the log directory exists (e.g. early arg errors).
  printf "$@"
  if [ -d "$(dirname "$LOG_FILE")" ]; then
    printf "$@" | sed -E 's/\x1b\[[0-9;]*m//g' >> "$LOG_FILE"
  fi
}

create_dir() {
  local path="$1"
  shift 1

  local MKDIRFLAGS="-p"
  if [ "$VERBOSE" == "1" ]; then
    MKDIRFLAGS+=" -v"
  fi
  execute "" "Unable to create directory '$path'" \
      mkdir $MKDIRFLAGS "$path"
}

remove_path() {
  local path="$1"
  shift 1

  local RMDIRFLAGS="-f -r"
  if [ "$VERBOSE" == "1" ]; then
    RMDIRFLAGS+=" -v"
  fi
  execute "" "Unable to remove path '$path'" \
      rm $RMDIRFLAGS "$path"
}

clean_build() {
  local keep_src="$1"
  if [ ! -d "$ROOT_PATH" ]; then
    printf "${YEL}Nothing to clean: '%s' does not exist.${c0}\n" "$ROOT_PATH"
    return
  fi

  local MVFLAGS="-f"
  local RMFLAGS="-rf"
  if [ "$VERBOSE" == "1" ]; then
    MVFLAGS+=" -v"
    RMFLAGS+=" -v"
  fi

  # keep the previous build log around as build.log.old
  if [ -f "$LOG_FILE" ]; then
    mv $MVFLAGS "$LOG_FILE" "$LOG_FILE.old"
  fi

  # nuke everything else under the build directory, preserving build.log.old.
  # With --keep-src also preserve the downloaded+patched src tree so a later
  # build can reuse it via -c instead of re-cloning and re-patching.
  local keep_args=( ! -name "$(basename "$LOG_FILE").old" )
  if [ "$keep_src" ]; then
    keep_args+=( ! -name "$(basename "$SRC_PATH")" )
  fi
  find "$ROOT_PATH" -mindepth 1 -maxdepth 1 \
      "${keep_args[@]}" -exec rm $RMFLAGS {} +

  if [ "$keep_src" ]; then
    printf "${YEL}Cleaned '%s' (kept %s/).${c0}\n" "$ROOT_PATH" "$(basename "$SRC_PATH")"
  else
    printf "${YEL}Cleaned '%s'.${c0}\n" "$ROOT_PATH"
  fi
}

change_dir() {
  local path="$1"
  shift 1

  execute "" "Unable to cd to directory '$path'" \
      cd "$path"
}

download_sources() {
  remove_path "$SRC_PATH"
  create_dir "$SRC_PATH"
  change_dir "$SRC_PATH"
  # --progress forces git's progress meter even when writing to the log; only
  # want it in verbose mode (otherwise it spams build.log with \r updates)
  local git_progress=""
  [ "$VERBOSE" == "1" ] && git_progress="--progress"
  printf "${GRE}Downloading sources${c0}\n"
  execute "Cloning MinGW source..." "Unable to clone MinGW-w64, to use the official mirror: --mingw-url 'https://git.code.sf.net/p/mingw-w64/mingw-w64'" \
      git clone $git_progress --depth 1 -b "$MINGW_W64_BRANCH" \
      "$MINGW_W64_URL" mingw-w64

  execute "Cloning Binutils source..." "Unable to clone Binutils, to use the official mirror: --binutils-url 'https://git.sr.ht/~sourceware/binutils-gdb'" \
      git clone $git_progress --depth 1 -b "$BINUTILS_BRANCH" \
      "$BINUTILS_URL" binutils

  execute "Cloning GCC source..." "Unable to clone GCC, to use the official mirror: --gcc-url 'https://git.sr.ht/~sourceware/gcc'" \
      git clone $git_progress --depth 1 -b "$GCC_BRANCH" \
      "$GCC_URL" gcc

  execute "Copying config.guess..." "" \
      cp -fv ${HERE}/assets/config.guess ./
  printf "${GRE}Done downloading sources!${c0}\n"
}

apply_patches() {
  log "${GRE}Applying patches...${c0}\n"
  create_dir "$SRC_PATH/patches"
  execute "" "Unable to copy patches" \
      cp -fv "$HERE"/patches/*/*.patch "$SRC_PATH/patches/"
  printf "${YEL}  Patching binutils...${c0}\n"
  change_dir "$SRC_PATH/binutils"
  execute "" "Failed to apply binutils-dlltool-zero-ordinals.patch" \
      git apply --reject ../patches/binutils-dlltool-zero-ordinals.patch
  printf "${YEL}  Patching GCC...${c0}\n"
  change_dir "$SRC_PATH/gcc"
  execute "" "Failed to apply gcc-stdcall-align.patch" \
      git apply --reject ../patches/gcc-stdcall-align.patch
  execute "" "Failed to apply gcc-trap-terminate.patch" \
      git apply --reject ../patches/gcc-trap-terminate.patch
  #execute "" "Failed to apply gdb-alternate-main.patch" \
  #    git apply --reject ../patches/gdb-alternate-main.patch
  if (( WIN32_WINNT < 0x0600 )); then
    execute "" "Failed to apply gcc-tzdb-getdynamic.patch" \
        git apply --reject ../patches/gcc-tzdb-getdynamic.patch
  fi
  printf "${YEL}  Patching MinGW...${c0}\n"
  change_dir "$SRC_PATH/mingw-w64"
  execute "" "Failed to apply gendef-no-comment.patch" \
      git apply --reject ../patches/gendef-no-comment.patch
  if (( WIN32_WINNT < 0x0501 )); then
    execute "" "Failed to apply rand_s-win2k.patch" \
        git apply --reject ../patches/rand_s-win2k.patch
  fi
  execute "" "Failed to apply MinGW headers.patch" \
      git apply --reject ../patches/headers.patch
  execute "" "Unable to mark patches as applied" \
      touch "$SRC_PATH/patches/applied_patches"
  printf "${GRE}Done patching sources!${c0}\n"
  change_dir "$HERE"
}

# Echo "<branch> <commit>" for the git repo at $1, falling back to the
# branch label $2 if HEAD is detached or git can't read the repo.
git_ref() {
  local dir="$1" fallback="$2" branch commit
  branch=$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null)
  if [ -z "$branch" ] || [ "$branch" = "HEAD" ]; then
    branch="$fallback"
  fi
  commit=$(git -C "$dir" rev-parse HEAD 2>/dev/null)
  printf '%s %s' "$branch" "$commit"
}

# Write a VERSION.txt manifest into an arch's install prefix. All values are
# gathered live: branch/commit from git, config.guess from its timestamp line,
# the script name/version, and the effective build flags for that arch.
# $1 = arch, $2 = install prefix, $3 = arch-relevant flag lines (KEY=value\n...)
write_version_file() {
  local arch="$1" prefix="$2" flag_lines="$3"
  local mingw_ref gcc_ref binutils_ref config_guess_ver

  mingw_ref=$(git_ref "$SRC_PATH/mingw-w64" "$MINGW_W64_BRANCH")
  gcc_ref=$(git_ref "$SRC_PATH/gcc" "$GCC_BRANCH")
  binutils_ref=$(git_ref "$SRC_PATH/binutils" "$BINUTILS_BRANCH")
  config_guess_ver=$(grep -m1 '^timestamp=' "$SRC_PATH/config.guess" | cut -d"'" -f2)

  cat > "$prefix/VERSION.txt" <<EOF
---- Versions ----

MinGW Version: $mingw_ref

GCC Version: $gcc_ref

Binutils Version: $binutils_ref

config.guess Version: $config_guess_ver

Built using $SCRIPTNAME Version: $SCRIPTVER

---- Build Details ----

Arch: $arch

WIN32_WINNT=$WIN32_WINNT
IS_DEBUG=$IS_DEBUG
$flag_lines
EOF
  printf "${GRE}Wrote version file ${bold}${prefix}/VERSION.txt ${c0}\n"
}

download_gcc_deps() {
  change_dir "$SRC_PATH/gcc"

  # download_prerequisites fetches gmp/mpfr/mpc/isl into the gcc tree; skip the
  # re-download if they're already present (e.g. on a --cached-sources rebuild)
  if [ ! -e "$SRC_PATH/gcc/gmp" ]; then
    execute "Downloading GCC prerequisites" "Failed to download GCC dependencies." \
        ./contrib/download_prerequisites
  fi

  # Link for binutils to pick up
  for i in mpc isl mpfr gmp; do
    ln -sfn "$SRC_PATH/gcc/$i" "$SRC_PATH/binutils/$i"
  done
}

copy_extra_files() {
  local arch="$1" prefix="$2"
  local outpath="$prefix/$arch-w64-mingw32/include"
  log "${GRE}Copying extra headers to $outpath${c0}\n"
  execute "" "Failed to copy sdkddkver.h" cp -fv ${HERE}/patches/mingw/sdkddkver.h $outpath
  execute "" "Failed to copy winsdkver.h" cp -fv ${HERE}/patches/mingw/winsdkver.h $outpath
  log "${GRE}Copying logo SVG to $prefix${c0}\n"
  execute "" "Failed to copy mingw.svg" cp -fv ${HERE}/assets/mingw-w64.svg $prefix/mingw.svg
}

# Build an <arch>-w64-mingw32 toolchain into $2.
#
# Two args (arch, prefix) build the normal Linux-hosted cross toolchain --
# identical to what mingw_gcc_linux.sh produces. A third arg of "windows"
# switches to a Canadian cross: the binutils/gcc/gendef driver binaries are
# built --host=$arch-w64-mingw32 (so they run on Windows) and statically linked,
# so the shipped toolchain carries no libgcc/libstdc++/libwinpthread DLL deps.
# The target libraries (CRT, libgcc, libstdc++, winpthreads) are always compiled
# for the Windows target by the Phase 1 cross compiler that build() left on PATH.
build_toolchain() {
  if [ "$WIN32_WINNT" != "0" ]; then
    export _WIN32_WINNT=$WIN32_WINNT
  else
    error_exit "WIN32_WINNT should not be 0!"
  fi

  if [[ -f "$SRC_PATH/patches/applied_patches" ]]; then
    printf "${YEL}Already applied patches.${c0}\n"
  else
    apply_patches || error_exit "Failed to apply patches"
  fi

  log "${GRE}Starting build using $JOB_COUNT jobs.${c0}\n"

  local arch="$1"
  local prefix="$2"
  local windows_host="$3"
  shift 2

  local bld_path="$BLD_PATH/$arch"
  local host="$arch-w64-mingw32"

  # Canadian-cross knobs: empty for the Linux-hosted build, populated when
  # producing the Windows-hosted toolchain. CROSS_FLAGS makes binutils/gcc build
  # host binaries that run on Windows; GENDEF_HOST does the same for gendef
  # (which already passes its own --build); EXE_EXT names the resulting tools.
  local CROSS_FLAGS="" GENDEF_HOST="" EXE_EXT="" host_label="Linux-hosted"
  if [ "$windows_host" = "windows" ]; then
    CROSS_FLAGS="--build=$BUILD --host=$host"
    GENDEF_HOST="--host=$host"
    EXE_EXT=".exe"
    host_label="Windows-hosted"
  fi

  # The Linux-hosted build puts its own bin/ on PATH so the freshly built
  # $arch-w64-mingw32-* tools drive the later steps. The Windows-hosted build
  # must NOT prepend its prefix -- those are Windows .exe binaries that can't run
  # here; it relies on the Phase 1 cross already on PATH from build().
  if [ -z "$windows_host" ]; then
    export PATH="$prefix/bin:$PATH"
  fi

  remove_path "$bld_path"
  # don't remove a user defined prefix (could be /usr/local)
  if [ ! "$PREFIX" ]; then
    remove_path "$prefix"
  fi

  # TARGET_CFLAGS are used to build code that runs on the Windows target
  # (libgcc, libstdc++, the CRT, winpthreads). These can safely restrict the
  # instruction set to the oldest supported CPU.
  #
  # OPT_FLAGS / STRIP_FLAG are controlled by IS_DEBUG. The test is
  # [ "$IS_DEBUG" = true ], NOT [ "$IS_DEBUG" ]: IS_DEBUG defaults to the
  # string "false", which a plain non-empty test would wrongly treat as true.
  # Baseline flags that everything needs
  local BASE_FLAGS="-Wno-maybe-uninitialized -Wno-unused-parameter -Wno-error"
  local OPT_FLAGS="$BASE_FLAGS"
  if [ "$IS_DEBUG" = true ]; then
    OPT_FLAGS+=" -Og -g2 -DDEBUG -D_DEBUG"
    local STRIP_FLAG=""
  else
    OPT_FLAGS+=" -O3 -g0 -DNDEBUG -D_NDEBUG"
    local STRIP_FLAG="-s"
  fi
  # TARGET_LDFLAGS starts from the strip setting; arch blocks may append to it
  local TARGET_LDFLAGS="$STRIP_FLAG"
  # Statically link the host C++/gcc runtime so the toolchain binaries don't rely
  # on the machine's libstdc++/libgcc (matches mingw_gcc_linux.sh). The
  # Windows-hosted build adds -static for fully self-contained .exe binaries.
  local HOST_STATIC="-static-libgcc -static-libstdc++"
  if [ "$windows_host" = "windows" ]; then
    HOST_STATIC="-static $HOST_STATIC"
  fi
  if [ "$arch" = "i586" ]; then
    local SIMD_FLAGS="-mfpmath=387"
    local MARCH=""
    if [ "$USE_MMX" = true ]; then
      SIMD_FLAGS+=" -mmmx -mno-fxsr -mno-sse -mno-sse2"
      MARCH="pentium-mmx"
    else
      SIMD_FLAGS+=" -mno-mmx -mno-fxsr -mno-sse -mno-sse2"
      MARCH="pentium"
    fi
    local VERSION_FLAGS="USE_MMX=$USE_MMX"
  elif [ "$arch" = "i686" ]; then
    # higher SSE levels imply the lower ones; use local copies so we never
    # mutate the global USE_* flags between successive arch builds
    local sse2=$USE_SSE2 sse3=$USE_SSE3 sse41=$USE_SSE41 sse42=$USE_SSE42
    [ "$sse42" = true ] && sse41=true
    [ "$sse41" = true ] && sse3=true
    [ "$sse3"  = true ] && sse2=true

    local SIMD_FLAGS="-mfpmath=sse -mmmx"
    local MARCH=""
    if [ "$sse2" = true ]; then
      SIMD_FLAGS+=" -mfxsr -msse2"
      MARCH="pentium4"
    else
      SIMD_FLAGS+=" -mfxsr -msse"
      MARCH="pentium3"
    fi
    if [ "$sse3" = true ]; then
      SIMD_FLAGS+=" -msse3"
      MARCH="prescott"
    fi
    if [ "$sse41" = true ]; then
      SIMD_FLAGS+=" -msse4.1"
      MARCH="core2"
    fi
    if [ "$sse42" = true ]; then
      SIMD_FLAGS+=" -mssse3 -msse4.2"
      MARCH="nehalem"
    fi
    local VERSION_FLAGS="USE_SSE2=$sse2
USE_SSE3=$sse3
USE_SSE41=$sse41
USE_SSE42=$sse42"
  elif [ "$arch" = "x86_64" ]; then
    # higher SIMD levels imply the lower ones; use local copies so we never
    # mutate the global USE_* flags between successive arch builds
    local sse3=$USE_SSE3 sse41=$USE_SSE41 sse42=$USE_SSE42
    local avx=$USE_AVX avx2=$USE_AVX2 avx512=$USE_AVX512
    [ "$avx512" = true ] && avx2=true
    [ "$avx2"   = true ] && avx=true
    [ "$avx"    = true ] && sse42=true
    [ "$sse42"  = true ] && sse41=true
    [ "$sse41"  = true ] && sse3=true

    # SSE and SSE2 are part of the x86-64 baseline, so they are always on
    local SIMD_FLAGS="-mfpmath=sse -mmmx -mfxsr -msse -msse2"
    local MARCH="x86-64"
    if [ "$sse3" = true ]; then
      SIMD_FLAGS+=" -msse3"
      MARCH="nocona"
    fi
    if [ "$sse41" = true ]; then
      SIMD_FLAGS+=" -msse4.1"
      MARCH="core2"
    fi
    if [ "$sse42" = true ]; then
      SIMD_FLAGS+=" -mssse3 -msse4.2"
      MARCH="x86-64-v2"
    fi
    if [ "$avx" = true ]; then
      SIMD_FLAGS+=" -mavx -maes -mpclmul"
      MARCH="sandybridge"
    fi
    if [ "$avx2" = true ]; then
      # -fp-contract enables FP contraction (FMA) at compile time; the
      # link-time codegen form is prefixed with an extra "f": -ffp-contract
      SIMD_FLAGS+=" -mavx2 -mfma -mrdrnd -mf16c -mbmi -mbmi2 -fp-contract=fast"
      TARGET_LDFLAGS+=" -ffp-contract=fast"
      MARCH="x86-64-v3"
    fi
    if [ "$avx512" = true ]; then
      SIMD_FLAGS+=" -mavx512f -mavx512cd -mavx512vl -mavx512bw -mavx512dq"
      MARCH="x86-64-v4"
    fi
    local VERSION_FLAGS="USE_SSE3=$sse3
USE_SSE41=$sse41
USE_SSE42=$sse42
USE_AVX=$avx
USE_AVX2=$avx2
USE_AVX512=$avx512"
  fi
  local TARGET_CFLAGS="$OPT_FLAGS $SIMD_FLAGS -pipe"
  local TARGET_CXXFLAGS="$TARGET_CFLAGS"

  # HOST_CFLAGS are used to build the toolchain tools themselves (binutils, the
  # gcc driver, gendef) -- which run on the build machine in Phase 1 and on the
  # Windows host in Phase 2. They must NOT inherit the target's
  # -mno-sse/-mfpmath=387: on x86-64 the SysV ABI returns doubles in SSE
  # registers, so -mno-sse breaks the host build of libiberty with
  # "SSE register return with SSE disabled".
  # Always use SSE3, since most people using this project will be on capable CPUs
  local HOST_CFLAGS="$OPT_FLAGS -mfpmath=sse -msse2 -msse3 -pipe"
  local HOST_CXXFLAGS="$HOST_CFLAGS"
  local HOST_LDFLAGS="$HOST_STATIC $STRIP_FLAG"

  if [ "$arch" = "i586" ] || [ "$arch" = "i686" ]; then
    # Causes top level configure warnings: Ignore, they are harmless
    local x86_dwarf="--disable-sjlj-exceptions --with-dwarf2"
    local crt_lib="--enable-lib32 --disable-lib64"
  elif [ "$arch" = "x86_64" ]; then
    local x86_dwarf=""
    local crt_lib="--enable-lib64 --disable-lib32"
  else
    error_exit "No matching arch: '$arch'"
  fi
  local VFLAGS=""
  if [ "$VERBOSE" == "1" ]; then
    VFLAGS+=" VERBOSE=1 V=1"
  fi

  log "${CYA}HOST           = ${bold}$host_label ${c0}\n"
  log "${CYA}HOST_CFLAGS    = ${bold}$HOST_CFLAGS ${c0}\n"
  log "${CYA}HOST_LDFLAGS   = ${bold}$HOST_LDFLAGS ${c0}\n"
  log "${CYA}TARGET_CFLAGS  = ${bold}$TARGET_CFLAGS ${c0}\n"
  log "${CYA}TARGET_LDFLAGS = ${bold}$TARGET_LDFLAGS ${c0}\n"
  log "${CYA}_WIN32_WINNT   = ${bold}${_WIN32_WINNT} ${c0}\n"
  sleep 1

  create_dir "$bld_path/binutils" &&
  change_dir "$bld_path/binutils" &&

  execute "($arch): Configuring Binutils" "" \
      "$SRC_PATH/binutils/configure" --prefix="$prefix" --disable-shared \
      --enable-static --with-sysroot="$prefix" --target="$host" \
      --disable-multilib --disable-nls --enable-lto --disable-gdb $CROSS_FLAGS \
      CFLAGS="$HOST_CFLAGS" CXXFLAGS="$HOST_CXXFLAGS" LDFLAGS="$HOST_LDFLAGS"

  execute "($arch): Building Binutils" "" \
      make -j $JOB_COUNT $VFLAGS

  execute "($arch): Installing Binutils" "" \
      make install $VFLAGS

  create_dir "$bld_path/mingw-w64-headers"
  change_dir "$bld_path/mingw-w64-headers"

  execute "($arch): Configuring MinGW headers" "" \
      "$SRC_PATH/mingw-w64/mingw-w64-headers/configure" --build="$BUILD" \
      --host="$host" --prefix="$prefix/$host" \
      --with-default-win32-winnt=$WIN32_WINNT \
      --with-default-msvcrt=$LINKED_RUNTIME \
      CFLAGS="$TARGET_CFLAGS" CXXFLAGS="$TARGET_CXXFLAGS" LDFLAGS="$TARGET_LDFLAGS"

  execute "($arch): Installing MinGW headers" "" \
      make install $VFLAGS

  create_dir "$bld_path/gcc"
  change_dir "$bld_path/gcc"

  local GCC_FLAGS="--with-arch=$MARCH $x86_dwarf"
  execute "($arch): Configuring GCC with arch: $MARCH" "Configuring GCC failed" \
      "$SRC_PATH/gcc/configure" --target="$host" --disable-shared \
      --enable-static --disable-multilib --prefix="$prefix" \
      --enable-languages=c,c++ --disable-nls $ENABLE_THREADS $GCC_FLAGS $CROSS_FLAGS \
      CFLAGS="$HOST_CFLAGS" CXXFLAGS="$HOST_CXXFLAGS" LDFLAGS="$HOST_LDFLAGS" \
      CFLAGS_FOR_TARGET="$TARGET_CFLAGS" CXXFLAGS_FOR_TARGET="$TARGET_CXXFLAGS" \
      LDFLAGS_FOR_TARGET="$TARGET_LDFLAGS"

  execute "($arch): Building minimal GCC (all-gcc)" "Building Minimal GCC failed" \
      make -j $JOB_COUNT all-gcc $VFLAGS
  execute "($arch): Installing minimal GCC (install-gcc)" "Installing Minimal GCC failed" \
      make install-gcc $VFLAGS

  create_dir "$bld_path/mingw-w64-crt"
  change_dir "$bld_path/mingw-w64-crt"

  execute "($arch): Configuring MinGW CRT" "Configuring MinGW CRT failed" \
      "$SRC_PATH/mingw-w64/mingw-w64-crt/configure" --build="$BUILD" \
      --host="$host" --prefix="$prefix/$host" \
      --with-default-msvcrt=$LINKED_RUNTIME \
      --with-default-win32-winnt=$WIN32_WINNT \
      --with-sysroot="$prefix/$host" $crt_lib \
      CFLAGS="$TARGET_CFLAGS" CXXFLAGS="$TARGET_CXXFLAGS" LDFLAGS="$TARGET_LDFLAGS"

  execute "($arch): Building MinGW CRT with minimal GCC" "Building MinGW CRT failed" \
      make -j $JOB_COUNT $VFLAGS
  execute "($arch): Installing MinGW CRT" "Installing MinGW CRT failed" \
      make install $VFLAGS

  create_dir "$bld_path/mingw-w64-gendef"
  change_dir "$bld_path/mingw-w64-gendef"

  execute "($arch): Configuring MinGW gendef" "Configuring gendef failed" \
      "$SRC_PATH/mingw-w64/mingw-w64-tools/gendef/configure" --build="$BUILD" \
      --prefix="$prefix/$host" $GENDEF_HOST \
      CFLAGS="$HOST_CFLAGS" CXXFLAGS="$HOST_CXXFLAGS" LDFLAGS="$HOST_LDFLAGS"

  execute "($arch): Building MinGW gendef" "Building gendef failed" \
      make -j $JOB_COUNT $VFLAGS
  execute "($arch): Installing MinGW gendef" "Installing gendef failed" \
      cp -v "gendef$EXE_EXT" "$prefix/bin"

  if [ "$ENABLE_THREADS" ]; then
    create_dir "$bld_path/mingw-w64-winpthreads"
    change_dir "$bld_path/mingw-w64-winpthreads"

    execute "($arch): Configuring winpthreads" "Configuring winpthreads failed" \
        "$SRC_PATH/mingw-w64/mingw-w64-libraries/winpthreads/configure" \
        --build="$BUILD" --host="$host" --disable-shared \
        --enable-static --prefix="$prefix/$host" \
        CFLAGS="$TARGET_CFLAGS" CXXFLAGS="$TARGET_CXXFLAGS" LDFLAGS="$TARGET_LDFLAGS"

    execute "($arch): Building winpthreads" "Building winpthreads failed" \
        make -j $JOB_COUNT $VFLAGS

    execute "($arch): Installing winpthreads" "Installing winpthreads failed" \
        make install $VFLAGS
  fi

  change_dir "$bld_path/gcc"

  execute "($arch): Building final GCC" "Building final GCC failed" \
      make -j $JOB_COUNT $VFLAGS
  execute "($arch): Installing final GCC + libs" "Installing final GCC failed" \
      make install $VFLAGS

  # Only the Windows-hosted deliverable gets the custom MSVC-compat headers.
  # Skipping Phase 1 keeps its throwaway cross compiler's sysroot 100% stock, so
  # Phase 2's target libs are built against stock mingw-w64 headers.
  if [ "$windows_host" = "windows" ]; then
    copy_extra_files "$arch" "$prefix"
  fi
  write_version_file "$arch" "$prefix" "$VERSION_FLAGS"
  log "${GRE}Done building $host_label toolchain for ${CYA}$arch ${c0}\n"
}

# Build a Windows-hosted toolchain for $arch via a two-phase Canadian cross.
# Phase 1 builds a Linux-hosted cross toolchain into an intermediate prefix and
# leaves its bin/ on PATH (the build->host and build->target compiler). Phase 2
# reuses those $arch-w64-mingw32-* tools to cross-compile the Windows-hosted
# toolchain (binutils/gcc/gendef --host=$arch-w64-mingw32, statically linked)
# into $prefix.
build() {
  local arch="$1"
  local prefix="$2"
  shift 2

  # Phase 1: Linux-hosted cross toolchain into an intermediate prefix.
  # build_toolchain() adds its bin/ to PATH, exposing $arch-w64-mingw32-* tools.
  local linux_prefix="$ROOT_PATH/linux-cross/$arch"
  log "${GRE}=== ($arch) Starting Phase 1: Linux-hosted cross toolchain ===${c0}\n"
  build_toolchain "$arch" "$linux_prefix"

  # Phase 2: Canadian-cross the Windows-hosted toolchain into $prefix, driven by
  # the phase-1 $arch-w64-mingw32-* tools now on PATH.
  log "${GRE}=== ($arch) Starting Phase 2: Windows-hosted toolchain ===${c0}\n"
  build_toolchain "$arch" "$prefix" windows
}

# Zip an arch's install prefix into <root>/<pkgname>.zip. The 64-bit build is
# packaged as x64.zip even though its prefix dir is x86_64; to give the archive a
# matching top-level folder we stage a hardlink tree (cheap, no extra disk, and
# leaves the original prefix untouched).
package_arch() {
  local arch="$1" pkgname="$2"
  local dir="$ROOT_PATH/$arch"
  [ -d "$dir" ] || error_exit "Cannot package '$arch': '$dir' not found"

  change_dir "$ROOT_PATH"
  rm -f "$pkgname.zip"
  if [ "$arch" = "$pkgname" ]; then
    execute "Packaging ${pkgname}.zip..." "Failed to create ${pkgname}.zip" \
        zip -r -q "$pkgname.zip" "$arch"
  else
    remove_path "$pkgname"
    execute "Running cp -al" "Failed to stage '$pkgname'" \
        cp -al "$arch" "$pkgname"
    execute "Packaging ${pkgname}.zip..." "Failed to create ${pkgname}.zip" \
        zip -r -q "$pkgname.zip" "$pkgname"
    remove_path "$pkgname"
  fi
}

install_deps() {
  if ! command -v apt-get >/dev/null; then
    error_exit "--deps only supports apt-based systems (Ubuntu/Debian); install the prerequisites manually"
  fi
  # use sudo only when not already root (e.g. plain CI containers lack sudo)
  local sudo=""
  [ "$(id -u)" -ne 0 ] && sudo="sudo"

  printf "${GRE}Installing dependencies for $SCRIPTNAME...${c0}\n"
  # build-essential: gcc, g++, make. The rest provide the remaining tools the
  # missing-executable check requires, plus zip for --package.
  $sudo apt-get update || error_exit "apt-get update failed"
  $sudo apt-get install -y \
      build-essential flex bison texinfo m4 bzip2 git curl zip autoconf diffutils \
      || error_exit "Failed to install dependencies"
  printf "${GRE}Done installing dependencies!${c0}\n"
}

while :; do
  case $1 in
    -h|--help)
        show_help
        exit 0
        ;;
    --version)
        show_version
        ;;
    --deps)
        install_deps
        exit 0
        ;;
    -v|--verbose)
        VERBOSE=1
        ;;
    --debug)
        IS_DEBUG=true
        ;;
    -j|--jobs)
        if [ "$2" ]; then
          JOB_COUNT=$2
          shift
        else
          arg_error "'--jobs' requires a non-empty option argument"
        fi
        ;;
    --prefix)
        if [ "$2" ]; then
          PREFIX="$2"
          shift
        else
          arg_error "'--prefix' requires a non-empty option argument"
        fi
        ;;
    --prefix=?*)
        PREFIX=${1#*=}
        ;;
    --prefix=)
        arg_error "'--prefix' requires a non-empty option argument"
        ;;
    --root)
        if [ "$2" ]; then
          ROOT_PATH_ARG="$2"
          shift
        else
          arg_error "'--root' requires a non-empty option argument"
        fi
        ;;
    --root=?*)
        ROOT_PATH_ARG="${1#*=}"
        ;;
    --root=)
        arg_error "'--root' requires a non-empty option argument"
        ;;
    --keep-artifacts)
        KEEP_ARTIFACTS=1
        ;;
    --clean)
        CLEAN=1
        ;;
    --keep-src)
        KEEP_SRC=1
        ;;
    -p|--patch)
        PATCHES_ONLY=1
        ;;
    --disable-threads)
        ENABLE_THREADS=""
        ;;
    -c|--cached-sources)
        CACHED_SOURCES=1
        ;;
    -d|--download-sources)
        JUST_SOURCES=1
        ;;
    --binutils-url)
        if [ "$2" ]; then
          BINUTILS_URL="$2"
          shift
        else
          arg_error "'--binutils-url' requires a non-empty option argument"
        fi
        ;;
    --binutils-url=?*)
        BINUTILS_URL=${1#*=}
        ;;
    --binutils-url=)
        arg_error "'--binutils-url' requires a non-empty option argument"
        ;;
    --binutils-branch)
        if [ "$2" ]; then
          BINUTILS_BRANCH="$2"
          shift
        else
          arg_error "'--binutils-branch' requires a non-empty option argument"
        fi
        ;;
    --binutils-branch=?*)
        BINUTILS_BRANCH=${1#*=}
        ;;
    --binutils-branch=)
        arg_error "'--binutils-branch' requires a non-empty option argument"
        ;;
    --gcc-url)
        if [ "$2" ]; then
          GCC_URL="$2"
          shift
        else
          arg_error "'--gcc-url' requires a non-empty option argument"
        fi
        ;;
    --gcc-url=?*)
        GCC_URL=${1#*=}
        ;;
    --gcc-url=)
        arg_error "'--gcc-url' requires a non-empty option argument"
        ;;
    --gcc-branch)
        if [ "$2" ]; then
          GCC_BRANCH="$2"
          shift
        else
          arg_error "'--gcc-branch' requires a non-empty option argument"
        fi
        ;;
    --gcc-branch=?*)
        GCC_BRANCH=${1#*=}
        ;;
    --gcc-branch=)
        arg_error "'--gcc-branch' requires a non-empty option argument"
        ;;
    --crtlib)
        if [ "$2" ]; then
          LINKED_RUNTIME="$2"
          shift
        else
          arg_error "'--crtlib' requires a non-empty option argument"
        fi
        ;;
    --crtlib=?*)
        LINKED_RUNTIME=${1#*=}
        ;;
    --crtlib=)
        arg_error "'--crtlib' requires a non-empty option argument"
        ;;
    --mingw-url)
        if [ "$2" ]; then
          MINGW_W64_URL="$2"
          shift
        else
          arg_error "'--mingw-url' requires a non-empty option argument"
        fi
        ;;
    --mingw-url=?*)
        MINGW_W64_URL=${1#*=}
        ;;
    --mingw-url=)
        arg_error "'--mingw-url' requires a non-empty option argument"
        ;;
    --mingw-branch)
        if [ "$2" ]; then
          MINGW_W64_BRANCH="$2"
          shift
        else
          arg_error "'--mingw-branch' requires a non-empty option argument"
        fi
        ;;
    --mingw-branch=?*)
        MINGW_W64_BRANCH=${1#*=}
        ;;
    --mingw-branch=)
        arg_error "'--mingw-branch' requires a non-empty option argument"
        ;;
    --win32-winnt)
        if [ "$2" ]; then
          WIN32_WINNT="$2"
          GOT_WIN32_WINNT=1
          shift
        else
          arg_error "'--win32-winnt' requires a non-empty option argument"
        fi
        ;;
    --win32-winnt=?*)
        WIN32_WINNT=${1#*=}
        GOT_WIN32_WINNT=1
        ;;
    --win32-winnt=)
        arg_error "'--win32-winnt' requires a non-empty option argument"
        ;;
    i586)
        BUILD_I586=1
        ;;
    i686|x32)
        BUILD_I686=1
        ;;
    x86_64|x64)
        BUILD_X86_64=1
        ;;
    -a|--all)
        # build every arch; each picks its own _WIN32_WINNT default at
        # dispatch unless the user passed --win32-winnt
        BUILD_I586=1
        BUILD_I686=1
        BUILD_X86_64=1
        ;;
    --package)
        PACKAGE=1
        ;;
    --mmx)
        WANT_MMX=1
        ;;
    --sse2)
        WANT_SSE2=1
        ;;
    --sse3)
        WANT_SSE3=1
        ;;
    --sse41)
        WANT_SSE41=1
        ;;
    --sse42)
        WANT_SSE42=1
        ;;
    --avx)
        WANT_AVX=1
        ;;
    --avx2)
        WANT_AVX2=1
        ;;
    --avx512)
        WANT_AVX512=1
        ;;
    --)
        shift
        break
        ;;
    -?*)
        arg_error "Unknown option '$1'"
        ;;
    ?*)
        arg_error "Unknown architecture '$1'"
        ;;
    *)
        break
  esac

  shift
done

if [ "$ROOT_PATH_ARG" ]; then
  if { [ "$CLEAN" ] || [ "$KEEP_SRC" ]; } && [ ! -d "$ROOT_PATH_ARG" ]; then
    # don't create the directory just to clean it
    ROOT_PATH="$ROOT_PATH_ARG"
  else
    ROOT_PATH=$(mkdir -p "$ROOT_PATH_ARG" && cd "$ROOT_PATH_ARG" && pwd)
  fi
  # ROOT_PATH moved, so re-derive everything anchored to it
  SRC_PATH="$ROOT_PATH/src"
  BLD_PATH="$ROOT_PATH/bld"
  LOG_FILE="$ROOT_PATH/build.log"
fi

# --clean / --keep-src are standalone commands: wipe the build dir and exit, no
# arch needed. --keep-src preserves the src/ tree for a fast cached rebuild (-c).
if [ "$CLEAN" ] || [ "$KEEP_SRC" ]; then
  clean_build "$KEEP_SRC"
  exit 0
fi

# --patch is a standalone command: (re)apply patches to already-downloaded
# sources, then exit, without building. Needs no arch. Intended to follow
# --download-sources plus local edits.
if [ "$PATCHES_ONLY" ]; then
  if [ ! -d "$SRC_PATH/gcc" ] || [ ! -d "$SRC_PATH/binutils" ] || [ ! -d "$SRC_PATH/mingw-w64" ]; then
    arg_error "No sources to patch; run --download-sources first"
  fi
  mkdir -p "$ROOT_PATH"
  touch "$LOG_FILE"
  if [ -f "$SRC_PATH/patches/applied_patches" ]; then
    printf "${YEL}Patches already applied.${c0}\n"
  else
    apply_patches || error_exit "Failed to apply patches"
  fi
  exit 0
fi

NUM_BUILDS=$((BUILD_I586 + BUILD_I686 + BUILD_X86_64))
# --download-sources only clones the repos and exits, so it needs no arch
if [ "$NUM_BUILDS" -eq 0 ] && [ ! "$JUST_SOURCES" ]; then
  arg_error "No ARCH was specified"
fi

MISSING_EXECS=""
for exec in g++ flex bison git makeinfo m4 bzip2 curl make diff; do
  if ! command -v "$exec" >/dev/null; then
    MISSING_EXECS="$MISSING_EXECS $exec"
  fi
done
if [ "$MISSING_EXECS" ]; then
  error_exit "Missing required executable(s): $MISSING_EXECS"
fi

if [ "$PACKAGE" ]; then
  if [ "$PREFIX" ]; then
    arg_error "--package cannot be combined with --prefix (it packages the per-arch build dirs)"
  fi
  if ! command -v zip >/dev/null; then
    error_exit "--package requires 'zip' to be installed"
  fi
fi

TOTAL_STEPS=0

if [ ! "$CACHED_SOURCES" ]; then
  TOTAL_STEPS=$((TOTAL_STEPS + 4))
fi

# Each arch runs the full sequence twice (Phase 1 Linux-hosted + Phase 2
# Windows-hosted), so per-arch step counts are doubled relative to the
# single-phase Linux build script: 3 winpthreads steps and 16 build steps
# per phase.
if [ "$ENABLE_THREADS" ]; then
  THREADS_STEPS=$((3 * 2))
else
  THREADS_STEPS=0
fi

THREADS_STEPS=$((THREADS_STEPS * NUM_BUILDS))
BUILD_STEPS=$((16 * 2 * NUM_BUILDS))

# one GCC-prerequisites download step (runs once, not per-arch): always on a
# fresh clone, or on cached sources only if they aren't already present
if [ ! "$CACHED_SOURCES" ] || [ ! -e "$SRC_PATH/gcc/gmp" ]; then
  PREREQ_STEPS=1
else
  PREREQ_STEPS=0
fi

# one packaging step (the zip) per built arch
if [ "$PACKAGE" ]; then
  PACKAGE_STEPS=$NUM_BUILDS
else
  PACKAGE_STEPS=0
fi

if [ "$JUST_SOURCES" ]; then
  TOTAL_STEPS=4
else
  TOTAL_STEPS=$((TOTAL_STEPS + PREREQ_STEPS + THREADS_STEPS + BUILD_STEPS + PACKAGE_STEPS))
fi

if [ "$PREFIX" ]; then
  I586_PREFIX="$PREFIX"
  I686_PREFIX="$PREFIX"
  X86_64_PREFIX="$PREFIX"
else
  I586_PREFIX="$ROOT_PATH/i586"
  I686_PREFIX="$ROOT_PATH/i686"
  X86_64_PREFIX="$ROOT_PATH/x64"
fi

CURRENT_STEP=1

# clean log file for execute()
mkdir -p "$ROOT_PATH"
rm -f "$LOG_FILE"
touch "$LOG_FILE"


if [ ! "$CACHED_SOURCES" ] || [ "$JUST_SOURCES" ]; then
  download_sources
  if [ "$JUST_SOURCES" ]; then
    exit 0;
  fi
else
  if [ ! -f "$SRC_PATH/config.guess" ]; then
    arg_error "No sources found, run with --download sources first."
  fi
  if [ "$CACHED_SOURCES" ]; then
    log "${YEL}NOTE: Using cached sources.${c0}\n"
  fi
fi

BUILD=$(sh "$SRC_PATH/config.guess")

download_gcc_deps

ADD_TO_PATH=()

if [ "$BUILD_I586" ]; then
  [ "$GOT_WIN32_WINNT" ] || WIN32_WINNT="0x0400"
  if [ "$WANT_MMX" ]; then
    USE_MMX=true
  fi
  build i586 "$I586_PREFIX"
  ADD_TO_PATH+=("'$I586_PREFIX/bin'")
fi

if [ "$BUILD_I686" ]; then
  [ "$GOT_WIN32_WINNT" ] || WIN32_WINNT="0x0500"
  if [ "$WANT_SSE2" ]; then
    USE_SSE2=true
  fi
  if [ "$WANT_SSE3" ]; then
    USE_SSE3=true
  fi
  if [ "$WANT_SSE41" ]; then
    USE_SSE41=true
  fi
  if [ "$WANT_SSE42" ]; then
    USE_SSE42=true
  fi
  build i686 "$I686_PREFIX"
  ADD_TO_PATH+=("'$I686_PREFIX/bin'")
fi

if [ "$BUILD_X86_64" ]; then
  [ "$GOT_WIN32_WINNT" ] || WIN32_WINNT="0x0502"
  if [ "$WANT_SSE3" ]; then
    USE_SSE3=true
  fi
  if [ "$WANT_SSE41" ]; then
    USE_SSE41=true
  fi
  if [ "$WANT_SSE42" ]; then
    USE_SSE42=true
  fi
  if [ "$WANT_AVX" ]; then
    USE_AVX=true
  fi
  if [ "$WANT_AVX2" ]; then
    USE_AVX2=true
  fi
  if [ "$WANT_AVX512" ]; then
    USE_AVX512=true
  fi
  build x86_64 "$X86_64_PREFIX"
  ADD_TO_PATH+=("'$X86_64_PREFIX/bin'")
fi

# Reaching here means every requested build succeeded (build() aborts on error).
# Package each built arch; the 64-bit one is named x64.zip.
if [ "$PACKAGE" ]; then
  [ "$BUILD_I586" ]   && package_arch i586 i586
  [ "$BUILD_I686" ]   && package_arch i686 i686
  [ "$BUILD_X86_64" ] && package_arch x64 x64
fi

if [ ! "$KEEP_ARTIFACTS" ]; then
  if [ ! "$CACHED_SOURCES" ]; then
    remove_path "$SRC_PATH"
  fi
  remove_path "$BLD_PATH"
  # the Phase 1 Linux-hosted toolchains are only an intermediate used to drive
  # the Canadian cross; drop them unless the user asked to keep artifacts
  remove_path "$ROOT_PATH/linux-cross"
  # keep build.log: it's the record of the build, and --clean preserves it as build.log.old
fi

printf "${GRE}Done! \n${c0}Built Windows-hosted toolchain(s) at: \n"
for add_to_path in "${ADD_TO_PATH[@]}"; do
  printf "${bold}%s ${c0}\n" "$add_to_path"
done
printf "${c0}Copy the prefix to a Windows machine and add its ${bold}bin\\\\${c0} to PATH.\n"

exit 0
