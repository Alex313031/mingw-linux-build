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
#
# LLVM/Clang variant of mingw_gcc_linux.sh. Instead of GCC + binutils this
# builds a self-contained MinGW-w64 toolchain around LLVM: clang (compiler),
# lld (linker), the LLVM binutils-style tools, compiler-rt (builtins, replaces
# libgcc), libunwind + libc++abi + libc++ (replaces libstdc++), and the unchanged
# MinGW-w64 headers/CRT/winpthreads/gendef. Modelled on mstorsjo/llvm-mingw.
#
# EXPERIMENTAL: this is a first cut. The legacy floor (no-SSE i586, NT 4.0/2000)
# matches the GCC script's intent but is far less travelled with clang; the most
# likely places to need tuning are the i586/no-SSE runtime builds and the libc++
# CMake flags. Raise the SIMD level or _WIN32_WINNT if a runtime won't build.

SCRIPTNAME=$(basename "$0")
SCRIPTVER="2.2.1"

export HERE=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
ROOT_PATH="$HERE/build/linux_llvm"
SRC_PATH="$ROOT_PATH/src"
BLD_PATH="$ROOT_PATH/bld"
LOG_FILE="$ROOT_PATH/build.log"

# Source URLs, using GitHub instead of originals for cloning speed
MINGW_W64_URL="https://github.com/mingw-w64/mingw-w64" # https://git.code.sf.net/p/mingw-w64/mingw-w64
LLVM_URL="https://github.com/llvm/llvm-project"
# What branches to checkout
MINGW_W64_BRANCH="v14.x"
LLVM_BRANCH="release/22.x"

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
  -j <count>, --jobs <count>  Override make/ninja job count. (default: $JOB_COUNT)
  --package                   After a successful build, zip each built arch into <root>/<arch>.zip (x86_64 becomes x64.zip).
  --prefix <path>             Change install location. (default: $ROOT_PATH/<arch>)
  --root <path>               Location for sources, build artifacts and the resulting compiler. (default: $ROOT_PATH)
  --keep-artifacts            Don't remove source and build files after a successful build.
  --disable-threads           Disable pthreads and STL <thread>.
  -c, --cached-sources        Use existing sources instead of downloading new ones and patching them.
  -d, --download-sources      Only download sources, then exit; for making local modifications.
  -p, --patch                 Only apply patches to already-downloaded sources, then exit; needs no arch.
  --clang-format              Build only clang-format (no full toolchain) and copy it into <prefix>/bin; for adding/refreshing it on an existing build.
  --clean                     Removes all sources and build artifacts, and output (keeps the previous build.log as build.log.old).
  --keep-src                  Like --clean but keeps the src/ tree (downloaded + patched sources), so a later build with -c skips re-downloading and re-patching.
  --llvm-url <url>            Set LLVM source URL, (default: $LLVM_URL)
  --llvm-branch <branch>      Set LLVM branch, (default: $LLVM_BRANCH)
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

  # The LLVM monorepo is large; --depth 1 keeps the clone manageable. It carries
  # clang, lld, compiler-rt, libunwind, libcxx and libcxxabi - everything that
  # replaces GCC + binutils + libgcc + libstdc++.
  execute "Cloning LLVM source..." "Unable to clone LLVM" \
      git clone $git_progress --depth 1 -b "$LLVM_BRANCH" \
      "$LLVM_URL" llvm-project

  execute "Copying config.guess..." "" \
      cp -fv ${HERE}/assets/config.guess ./
  printf "${GRE}Done downloading sources!${c0}\n"
}

apply_patches() {
  log "${GRE}Applying patches...${c0}\n"
  create_dir "$SRC_PATH/patches"
  execute "" "Unable to copy patches" \
      cp -fv "$HERE"/patches/*/*.patch "$SRC_PATH/patches/"
  # NOTE: the GCC/binutils patches (gcc-stdcall-align, gcc-trap-terminate,
  # gcc-tzdb-getdynamic, binutils-dlltool-zero-ordinals) do not apply to an
  # LLVM toolchain and are intentionally skipped. Only the MinGW-w64 patches,
  # which patch sources still used here, are applied (plus an LLVM patch below).
  printf "${YEL}  Patching LLVM...${c0}\n"
  change_dir "$SRC_PATH/llvm-project"
  # compiler-rt's emutls.c calls InitOnceExecuteOnce(), a Vista+ API. The patch
  # is self-guarding (#if _WIN32_WINNT >= 0x0600) so it is a no-op on modern
  # targets and provides a pre-Vista fallback for NT 4.0/2000/XP builds.
  execute "" "Failed to apply compiler-rt-emutls-pre-vista.patch" \
      git apply --reject ../patches/compiler-rt-emutls-pre-vista.patch
  # libc++'s Windows locale shim uses the per-locale "_l" ctype helpers that the
  # legacy msvcrt.dll (NT 4.0/2000/XP target) lacks. The patch is self-guarding
  # (only active for non-UCRT msvcrt < 0x0800) so it is a no-op on UCRT builds.
  execute "" "Failed to apply libcxx-legacy-msvcrt-locale.patch" \
      git apply --reject ../patches/libcxx-legacy-msvcrt-locale.patch
  # libc++ calls the bounds-checked wcrtomb_s(), which the legacy msvcrt.dll
  # lacks; the patch supplies a local shim (self-guarding, no-op on UCRT).
  execute "" "Failed to apply libcxx-legacy-msvcrt-wcrtomb_s.patch" \
      git apply --reject ../patches/libcxx-legacy-msvcrt-wcrtomb_s.patch
  # libunwind's Win32 RWMutex uses SRWLOCK (Vista+). The patch adds a pre-Vista
  # CRITICAL_SECTION fallback (self-guarding on _WIN32_WINNT < 0x0600), avoiding
  # a winpthreads dependency in libunwind.
  execute "" "Failed to apply libunwind-rwmutex-pre-vista.patch" \
      git apply --reject ../patches/libunwind-rwmutex-pre-vista.patch
  # libc++'s std::filesystem uses Vista+ APIs (GetFileInformationByHandleEx,
  # CreateSymbolicLinkW, GetFinalPathNameByHandleW, SetFileInformationByHandle).
  # The patch adds NT 4.0/2000/XP fallbacks (self-guarding on _WIN32_WINNT <
  # 0x0600); symlink/realpath/fchmod degrade to "not supported" on those targets.
  execute "" "Failed to apply libcxx-legacy-filesystem.patch" \
      git apply --reject ../patches/libcxx-legacy-filesystem.patch
  # libc++ std::thread::hardware_concurrency() uses GetActiveProcessorCount
  # (Windows 7+); the patch falls back to GetSystemInfo() on older targets
  # (self-guarding on _WIN32_WINNT < 0x0601). Needed on LLVM 22.x (20.x already
  # used GetSystemInfo).
  execute "" "Failed to apply libcxx-thread-getsysteminfo.patch" \
      git apply --reject ../patches/libcxx-thread-getsysteminfo.patch
  printf "${YEL}  Patching MinGW...${c0}\n"
  change_dir "$SRC_PATH/mingw-w64"
  execute "" "Failed to apply gendef-silent.patch" \
      git apply --reject ../patches/gendef-silent.patch
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
  local mingw_ref llvm_ref config_guess_ver

  mingw_ref=$(git_ref "$SRC_PATH/mingw-w64" "$MINGW_W64_BRANCH")
  llvm_ref=$(git_ref "$SRC_PATH/llvm-project" "$LLVM_BRANCH")
  config_guess_ver=$(grep -m1 '^timestamp=' "$SRC_PATH/config.guess" | cut -d"'" -f2)

  cat > "$prefix/VERSION.txt" <<EOF
---- Versions ----

MinGW Version: $mingw_ref

LLVM Version: $llvm_ref

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

copy_extra_files() {
  local triple="$1" prefix="$2"
  local outpath="$prefix/$triple/include"
  log "${GRE}Copying extra headers to $outpath${c0}\n"
  execute "" "Failed to copy sdkddkver.h" cp -fv ${HERE}/patches/mingw/sdkddkver.h $outpath
  execute "" "Failed to copy winsdkver.h" cp -fv ${HERE}/patches/mingw/winsdkver.h $outpath
  log "${GRE}Copying logo SVG to $prefix${c0}\n"
  execute "" "Failed to copy mingw.svg" cp -fv ${HERE}/assets/mingw-w64.svg $prefix/mingw.svg
}

# Generate the familiar <arch>-w64-mingw32-* toolchain entry points in the
# prefix's bin dir. The clang driver infers C vs C++ mode from "++" in argv[0];
# we bake in --target and --sysroot only. Deliberately NO -march/SIMD flags: the
# arch CPU baseline is a build-time property of the runtimes, not something the
# driver should impose on user code (that would override flags a user passes for
# testing). The triple's own default CPU keeps 32-bit conservative (no SSE);
# users opt into SIMD with their own -march/-msse* like any other toolchain.
# $1 = arch (wrapper name), $2 = clang target triple, $3 = prefix, $4 = link-time extra flags
generate_wrappers() {
  local arch="$1" triple="$2" prefix="$3" ldextra="$4"
  local wrap="$arch-w64-mingw32"
  local bindir="$prefix/bin"
  log "${GRE}Generating toolchain wrappers for ${bold}$wrap${c0}${GRE} (target $triple)${c0}\n"

  # $ldextra carries link-time defaults (PE subsystem/OS version) only. They are
  # unused when only compiling (-c), so -Wno-unused-command-line-argument keeps
  # those invocations quiet.
  local entry name mode
  for entry in "clang:--driver-mode=gcc" "clang++:--driver-mode=g++" \
               "gcc:--driver-mode=gcc"   "g++:--driver-mode=g++" \
               "cc:--driver-mode=gcc"    "c++:--driver-mode=g++"; do
    name="${entry%%:*}"; mode="${entry#*:}"
    cat > "$bindir/$wrap-$name" <<EOF
#!/bin/sh
# Auto-generated by $SCRIPTNAME for $wrap
# Resolve clang + sysroot relative to this wrapper so the toolchain is portable.
dir=\$(CDPATH= cd -- "\$(dirname -- "\$0")" && pwd)
exec "\$dir/clang" $mode --target=$triple --sysroot="\$dir/../$triple" $ldextra -Wno-unused-command-line-argument "\$@"
EOF
    chmod +x "$bindir/$wrap-$name"
  done

  # binutils-style tools -> LLVM equivalents (relative symlinks in the same dir)
  local tool
  for tool in ar:llvm-ar ranlib:llvm-ranlib nm:llvm-nm strip:llvm-strip \
              objcopy:llvm-objcopy objdump:llvm-objdump dlltool:llvm-dlltool \
              windres:llvm-windres strings:llvm-strings addr2line:llvm-addr2line; do
    ln -sf "${tool#*:}" "$bindir/$wrap-${tool%%:*}"
  done
  # ld -> lld (PE/COFF flavor installs as ld.lld)
  ln -sf "ld.lld" "$bindir/$wrap-ld"
}

build() {
  if [ "$WIN32_WINNT" != "0" ]; then
    export _WIN32_WINNT=$WIN32_WINNT
  else
    error_exit "WIN32_WINNT should not be 0!"
  fi

  if [[ -f "$SRC_PATH/patches/applied_patches" ]]; then
    printf "${bold}Already applied patches.${c0}\n"
  else
    apply_patches || error_exit "Failed to apply patches"
  fi

  log "${GRE}Starting build using $JOB_COUNT jobs.${c0}\n"

  local arch="$1"
  local prefix="$2"
  shift 2

  local bld_path="$BLD_PATH/$arch"

  # Each arch uses its own $arch-w64-mingw32 triple, keeping the sysroot dir,
  # tool names and --host consistent across all four scripts. clang/LLVM treat
  # i386/i486/i586/i686 all as 32-bit x86 (Triple::x86), so i586-w64-mingw32 is a
  # valid target; the CPU floor is pinned by the -march/SIMD flags, not the triple
  # (builtins are named by arch, libclang_rt.builtins-i386.a, either way).
  local triple="$arch-w64-mingw32"
  local wrap="$arch-w64-mingw32"

  export PATH="$prefix/bin:$PATH"

  # --clang-format reuses the existing build tree + prefix (it just drops a fresh
  # clang-format into bin/), so don't wipe them in that mode.
  if [ ! "$CLANG_FORMAT_ONLY" ]; then
    remove_path "$bld_path"
    # don't remove a user defined prefix (could be /usr/local)
    if [ ! "$PREFIX" ]; then
      remove_path "$prefix"
    fi
  fi

  # TARGET_CFLAGS are used to build code that runs on the Windows target
  # (compiler-rt, libc++, the CRT, winpthreads). These can safely restrict the
  # instruction set to the oldest supported CPU.
  #
  # OPT_FLAGS / STRIP_FLAG are controlled by IS_DEBUG. The test is
  # [ "$IS_DEBUG" = true ], NOT [ "$IS_DEBUG" ]: IS_DEBUG defaults to the
  # string "false", which a plain non-empty test would wrongly treat as true.
  # Baseline flags that everything needs. -Wno-unknown-warning-option keeps
  # clang quiet about GCC-style warning names that leak in from MinGW configs.
  local BASE_FLAGS="-Wno-unused-parameter -Wno-unknown-warning-option -Wno-unused-command-line-argument -Wno-error"
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
      SIMD_FLAGS+=" -mavx2 -mfma -mrdrnd -mf16c -mbmi -mbmi2 -ffp-contract=fast"
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
  # -march pins the CPU baseline; SIMD_FLAGS enable/disable the instruction sets.
  SIMD_FLAGS="-march=$MARCH $SIMD_FLAGS"

  # PE image OS/subsystem version. _WIN32_WINNT is encoded as 0xMMmm (major.minor),
  # so derive the version straight from it: i586 -> 4.0 (NT 4.0), i686 -> 5.0
  # (Windows 2000), x86_64 -> 5.2. lld otherwise stamps 6.0 (Vista), which makes
  # the binary refuse to load on older Windows. Tracks --win32-winnt overrides.
  local winver_major=$(( (WIN32_WINNT >> 8) & 0xff ))
  local winver_minor=$(( WIN32_WINNT & 0xff ))
  local SUBSYS_LDFLAGS="-Wl,--major-os-version=$winver_major,--minor-os-version=$winver_minor"
  SUBSYS_LDFLAGS+=" -Wl,--major-subsystem-version=$winver_major,--minor-subsystem-version=$winver_minor"
  # The wrappers no longer bake SIMD, so the autotools runtime builds (CRT,
  # winpthreads, gendef) must carry the arch baseline themselves -- same full
  # OPT+SIMD set the CMake runtime builds use.
  local TARGET_CFLAGS="$OPT_FLAGS $SIMD_FLAGS -pipe"
  local AUTOTOOLS_CFLAGS="$TARGET_CFLAGS"
  local TARGET_CXXFLAGS="$TARGET_CFLAGS"

  # HOST_CFLAGS are used to build the LLVM host tools that run on the build
  # machine (clang, lld, llvm-*).
  local HOST_CFLAGS="$OPT_FLAGS -mfpmath=sse -msse2 -pipe"
  local HOST_CXXFLAGS="$HOST_CFLAGS"

  if [ "$arch" = "i586" ] || [ "$arch" = "i686" ]; then
    local crt_lib="--enable-lib32 --disable-lib64"
  elif [ "$arch" = "x86_64" ]; then
    local crt_lib="--enable-lib64 --disable-lib32"
  else
    error_exit "No matching arch: '$arch'"
  fi
  local VFLAGS=""
  if [ "$VERBOSE" == "1" ]; then
    VFLAGS+=" VERBOSE=1 V=1"
  fi

  # CMAKE flags for runtime (target) builds: drive clang as a cross compiler.
  local CMAKE_TARGET_ARGS=(
    -DCMAKE_SYSTEM_NAME=Windows
    -DCMAKE_C_COMPILER="$prefix/bin/clang"
    -DCMAKE_CXX_COMPILER="$prefix/bin/clang++"
    -DCMAKE_ASM_COMPILER="$prefix/bin/clang"
    -DCMAKE_C_COMPILER_TARGET="$triple"
    -DCMAKE_CXX_COMPILER_TARGET="$triple"
    -DCMAKE_ASM_COMPILER_TARGET="$triple"
    -DCMAKE_SYSROOT="$prefix/$triple"
    -DCMAKE_AR="$prefix/bin/llvm-ar"
    -DCMAKE_RANLIB="$prefix/bin/llvm-ranlib"
    -DCMAKE_C_FLAGS="$TARGET_CFLAGS"
    -DCMAKE_CXX_FLAGS="$TARGET_CXXFLAGS"
    -DCMAKE_ASM_FLAGS="$TARGET_CFLAGS"
    -DLLVM_ENABLE_PER_TARGET_RUNTIME_DIR=OFF
  )

  log "${CYA}HOST_CFLAGS    = ${bold}$HOST_CFLAGS ${c0}\n"
  log "${CYA}TARGET_CFLAGS  = ${bold}$TARGET_CFLAGS ${c0}\n"
  log "${CYA}TARGET_LDFLAGS = ${bold}$TARGET_LDFLAGS ${c0}\n"
  log "${CYA}TRIPLE         = ${bold}$triple ${c0}\n"
  log "${CYA}_WIN32_WINNT   = ${bold}${_WIN32_WINNT} ${c0}\n"
  log "${CYA}PE OS/SUBSYS   = ${bold}${winver_major}.${winver_minor} ${c0}\n"
  sleep 1

  ##############################################################################
  # 1. LLVM: clang + lld + the LLVM binutils-style tools (host compiler)
  ##############################################################################
  create_dir "$bld_path/llvm"
  change_dir "$bld_path/llvm"

  execute "($arch): Configuring LLVM (clang + lld)" "Configuring LLVM failed" \
      cmake -G Ninja "$SRC_PATH/llvm-project/llvm" \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX="$prefix" \
      -DLLVM_ENABLE_PROJECTS="clang;lld" \
      -DLLVM_TARGETS_TO_BUILD="X86" \
      -DLLVM_ENABLE_ASSERTIONS=OFF \
      -DLLVM_STATIC_LINK_CXX_STDLIB=ON \
      -DLLVM_INCLUDE_TESTS=OFF \
      -DLLVM_INCLUDE_BENCHMARKS=OFF \
      -DLLVM_INCLUDE_EXAMPLES=OFF \
      -DLLVM_ENABLE_ZSTD=OFF \
      -DLLVM_DEFAULT_TARGET_TRIPLE="$triple" \
      -DCLANG_DEFAULT_LINKER=lld \
      -DCLANG_DEFAULT_RTLIB=compiler-rt \
      -DCLANG_DEFAULT_UNWINDLIB=libunwind \
      -DCLANG_DEFAULT_CXX_STDLIB=libc++ \
      -DCMAKE_C_FLAGS="$HOST_CFLAGS" \
      -DCMAKE_CXX_FLAGS="$HOST_CXXFLAGS"

  # --clang-format: build ONLY clang-format (a small subset of LLVM/clang -- no
  # backend codegen) and drop it straight into the prefix's bin/, then stop. Lets
  # you add/refresh clang-format on an existing toolchain without a full rebuild.
  if [ "$CLANG_FORMAT_ONLY" ]; then
    execute "($arch): Building clang-format" "Building clang-format failed" \
        ninja -j $JOB_COUNT clang-format
    create_dir "$prefix/bin"
    execute "($arch): Installing clang-format" "Installing clang-format failed" \
        cp -fv "$bld_path/llvm/bin/clang-format" "$prefix/bin"
    log "${GRE}Done building clang-format for arch ${CYA}$arch ${c0}\n"
    return 0
  fi

  execute "($arch): Building LLVM" "Building LLVM failed" \
      ninja -j $JOB_COUNT
  execute "($arch): Installing LLVM" "Installing LLVM failed" \
      ninja install

  # clang-format ships in the toolchain bin/ (next to gendef) so the toolchain can
  # also lint C++ projects; `ninja` above already built it -- just copy it in.
  execute "($arch): Installing clang-format" "Installing clang-format failed" \
      cp -fv "$bld_path/llvm/bin/clang-format" "$prefix/bin"

  # Toolchain entry points must exist before the autotools runtimes configure,
  # since those use <wrap>-cc / <wrap>-ar etc.
  generate_wrappers "$arch" "$triple" "$prefix" "$SUBSYS_LDFLAGS"

  local CC_WRAP="$prefix/bin/$wrap-cc"
  local CXX_WRAP="$prefix/bin/$wrap-c++"
  local AUTOTOOLS_TOOLS=(
    "CC=$CC_WRAP" "CXX=$CXX_WRAP"
    "AR=$prefix/bin/llvm-ar" "RANLIB=$prefix/bin/llvm-ranlib"
    "STRIP=$prefix/bin/llvm-strip" "NM=$prefix/bin/llvm-nm"
    "DLLTOOL=$prefix/bin/llvm-dlltool" "RC=$prefix/bin/llvm-windres"
    "OBJDUMP=$prefix/bin/llvm-objdump"
  )

  ##############################################################################
  # 2. MinGW-w64 headers
  ##############################################################################
  create_dir "$bld_path/mingw-w64-headers"
  change_dir "$bld_path/mingw-w64-headers"

  execute "($arch): Configuring MinGW headers" "Configuring MinGW headers failed" \
      "$SRC_PATH/mingw-w64/mingw-w64-headers/configure" --build="$BUILD" \
      --host="$triple" --prefix="$prefix/$triple" \
      --with-default-win32-winnt=$WIN32_WINNT \
      --with-default-msvcrt=$LINKED_RUNTIME \
      "${AUTOTOOLS_TOOLS[@]}" CFLAGS="$AUTOTOOLS_CFLAGS"

  execute "($arch): Installing MinGW headers" "Installing MinGW headers failed" \
      make install $VFLAGS

  ##############################################################################
  # 3. MinGW-w64 CRT (built with clang; static archives need no builtins yet)
  ##############################################################################
  create_dir "$bld_path/mingw-w64-crt"
  change_dir "$bld_path/mingw-w64-crt"

  execute "($arch): Configuring MinGW CRT" "Configuring MinGW CRT failed" \
      "$SRC_PATH/mingw-w64/mingw-w64-crt/configure" --build="$BUILD" \
      --host="$triple" --prefix="$prefix/$triple" \
      --with-default-msvcrt=$LINKED_RUNTIME \
      --with-default-win32-winnt=$WIN32_WINNT \
      --with-sysroot="$prefix/$triple" $crt_lib \
      "${AUTOTOOLS_TOOLS[@]}" CFLAGS="$AUTOTOOLS_CFLAGS"

  execute "($arch): Building MinGW CRT" "Building MinGW CRT failed" \
      make -j $JOB_COUNT $VFLAGS
  execute "($arch): Installing MinGW CRT" "Installing MinGW CRT failed" \
      make install $VFLAGS

  ##############################################################################
  # 4. compiler-rt builtins (replaces libgcc). Installs into clang's resource
  #    dir so the bare clang picks it up automatically.
  ##############################################################################
  local resource_dir
  resource_dir="$("$prefix/bin/clang" -print-resource-dir)"
  create_dir "$bld_path/compiler-rt"
  change_dir "$bld_path/compiler-rt"

  execute "($arch): Configuring compiler-rt" "Configuring compiler-rt failed" \
      cmake -G Ninja "$SRC_PATH/llvm-project/compiler-rt" \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX="$resource_dir" \
      -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
      "${CMAKE_TARGET_ARGS[@]}" \
      -DCOMPILER_RT_DEFAULT_TARGET_ONLY=ON \
      -DCOMPILER_RT_USE_BUILTINS_LIBRARY=ON \
      -DCOMPILER_RT_BUILD_BUILTINS=ON \
      -DCOMPILER_RT_BUILD_SANITIZERS=OFF \
      -DCOMPILER_RT_BUILD_XRAY=OFF \
      -DCOMPILER_RT_BUILD_LIBFUZZER=OFF \
      -DCOMPILER_RT_BUILD_PROFILE=OFF \
      -DCOMPILER_RT_BUILD_MEMPROF=OFF \
      -DCOMPILER_RT_BUILD_ORC=OFF

  execute "($arch): Building compiler-rt" "Building compiler-rt failed" \
      ninja -j $JOB_COUNT
  execute "($arch): Installing compiler-rt" "Installing compiler-rt failed" \
      ninja install

  ##############################################################################
  # 5. winpthreads (POSIX thread model)
  ##############################################################################
  if [ "$ENABLE_THREADS" ]; then
    create_dir "$bld_path/mingw-w64-winpthreads"
    change_dir "$bld_path/mingw-w64-winpthreads"

    execute "($arch): Configuring winpthreads" "Configuring winpthreads failed" \
        "$SRC_PATH/mingw-w64/mingw-w64-libraries/winpthreads/configure" \
        --build="$BUILD" --host="$triple" --disable-shared \
        --enable-static --prefix="$prefix/$triple" \
        "${AUTOTOOLS_TOOLS[@]}" CFLAGS="$AUTOTOOLS_CFLAGS"

    execute "($arch): Building winpthreads" "Building winpthreads failed" \
        make -j $JOB_COUNT $VFLAGS
    execute "($arch): Installing winpthreads" "Installing winpthreads failed" \
        make install $VFLAGS
  fi

  ##############################################################################
  # 6. LLVM runtimes: libunwind + libc++abi + libc++ (replaces libstdc++).
  #    These are the flags most likely to need iteration for the legacy floor.
  ##############################################################################
  local LIBCXX_THREADS
  if [ "$ENABLE_THREADS" ]; then
    LIBCXX_THREADS="-DLIBCXX_ENABLE_THREADS=ON -DLIBCXXABI_ENABLE_THREADS=ON -DLIBUNWIND_ENABLE_THREADS=ON -DLIBCXX_HAS_PTHREAD_API=ON"
  else
    LIBCXX_THREADS="-DLIBCXX_ENABLE_THREADS=OFF -DLIBCXXABI_ENABLE_THREADS=OFF -DLIBUNWIND_ENABLE_THREADS=OFF"
  fi
  create_dir "$bld_path/runtimes"
  change_dir "$bld_path/runtimes"

  execute "($arch): Configuring libunwind/libc++abi/libc++" "Configuring runtimes failed" \
      cmake -G Ninja "$SRC_PATH/llvm-project/runtimes" \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX="$prefix/$triple" \
      -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
      "${CMAKE_TARGET_ARGS[@]}" \
      -DLLVM_ENABLE_RUNTIMES="libunwind;libcxxabi;libcxx" \
      -DLLVM_INCLUDE_TESTS=OFF \
      -DLIBUNWIND_INCLUDE_TESTS=OFF \
      -DLIBCXXABI_INCLUDE_TESTS=OFF \
      -DLIBCXX_INCLUDE_TESTS=OFF \
      -DLIBCXX_INCLUDE_BENCHMARKS=OFF \
      -DLIBUNWIND_USE_COMPILER_RT=ON \
      -DLIBUNWIND_ENABLE_SHARED=OFF \
      -DLIBUNWIND_ENABLE_STATIC=ON \
      -DLIBCXXABI_USE_COMPILER_RT=ON \
      -DLIBCXXABI_USE_LLVM_UNWINDER=ON \
      -DLIBCXXABI_ENABLE_STATIC_UNWINDER=ON \
      -DLIBCXXABI_ENABLE_SHARED=OFF \
      -DLIBCXXABI_ENABLE_STATIC=ON \
      -DLIBCXX_USE_COMPILER_RT=ON \
      -DLIBCXX_CXX_ABI=libcxxabi \
      -DLIBCXX_ENABLE_STATIC_ABI_LIBRARY=ON \
      -DLIBCXX_ENABLE_SHARED=OFF \
      -DLIBCXX_ENABLE_STATIC=ON \
      -DLIBCXX_ENABLE_EXCEPTIONS=ON \
      $LIBCXX_THREADS

  execute "($arch): Building libunwind/libc++abi/libc++" "Building runtimes failed" \
      ninja -j $JOB_COUNT
  execute "($arch): Installing libunwind/libc++abi/libc++" "Installing runtimes failed" \
      ninja install

  ##############################################################################
  # 7. gendef (host tool from the MinGW-w64 tree)
  ##############################################################################
  create_dir "$bld_path/mingw-w64-gendef"
  change_dir "$bld_path/mingw-w64-gendef"

  execute "($arch): Configuring MinGW gendef" "Configuring gendef failed" \
      "$SRC_PATH/mingw-w64/mingw-w64-tools/gendef/configure" --build="$BUILD" \
      --prefix="$prefix/$triple" CFLAGS="$HOST_CFLAGS"

  execute "($arch): Building MinGW gendef" "Building gendef failed" \
      make -j $JOB_COUNT $VFLAGS
  execute "($arch): Installing MinGW gendef" "Installing gendef failed" \
      cp -v gendef $prefix/bin

  # Host-side utilities from assets/src, dropped in bin/ like gendef and built
  # LAST. Native (Linux-hosted) binaries; capped at C17 (-std=gnu17) so they build
  # on Ubuntu 22.04 / gcc 11. pkg-config is Windows-only (every Linux distro ships
  # one), so it is omitted from the Linux toolchains.
  local _t _n _src _xf
  for _t in "peports:peports.c" "xxd:rexxd.c" "uuidgen:uuidgen.c"; do
    _n=${_t%%:*}; _src=${_t#*:}; _xf=""; [ "$_n" = xxd ] && _xf="-funroll-loops"
    execute "($arch): Building host tool $_n" "Building $_n failed" \
        cc -std=gnu17 $OPT_FLAGS $_xf -s "$HERE/assets/src/$_src" -o "$prefix/bin/$_n"
  done

  copy_extra_files "$triple" "$prefix"
  write_version_file "$arch" "$prefix" "$VERSION_FLAGS"
  log "${GRE}Done building for arch ${CYA}$arch ${c0}\n"
}

# Zip an arch's install prefix into <root>/<pkgname>.zip. pkgname matches the
# prefix dir name, so the archive carries a matching top-level folder. -y stores
# symlinks AS symlinks instead of dereferencing each into a full duplicate copy,
# keeping the archive compact (important here: the LLVM wrappers + llvm-* tools
# are symlinks); the Linux-hosted toolchain's symlinks are recreated by unzip on
# Linux. (The Windows-hosted build omits -y - Windows can't use symlinks, so there
# they must be materialized into real copies.)
package_arch() {
  local arch="$1" pkgname="$2"
  local dir="$ROOT_PATH/$arch"
  [ -d "$dir" ] || error_exit "Cannot package '$arch': '$dir' not found"

  change_dir "$ROOT_PATH"
  rm -f "$pkgname.zip"
  if [ "$arch" = "$pkgname" ]; then
    execute "Packaging ${pkgname}.zip..." "Failed to create ${pkgname}.zip" \
        zip -r -q -y "$pkgname.zip" "$arch"
  else
    remove_path "$pkgname"
    execute "Running cp -al" "Failed to stage '$pkgname'" \
        cp -al "$arch" "$pkgname"
    execute "Packaging ${pkgname}.zip..." "Failed to create ${pkgname}.zip" \
        zip -r -q -y "$pkgname.zip" "$pkgname"
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
  # build-essential + cmake + ninja build LLVM; python3 is required by the LLVM
  # build; the rest provide the tools the missing-executable check requires,
  # plus zip for --package. clang/lld can bootstrap LLVM faster than g++ but
  # build-essential's g++ is sufficient.
  $sudo apt-get update || error_exit "apt-get update failed"
  $sudo apt-get install -y \
      build-essential cmake ninja-build python3 git curl zip bzip2 diffutils \
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
    --clang-format)
        CLANG_FORMAT_ONLY=1
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
    --llvm-url)
        if [ "$2" ]; then
          LLVM_URL="$2"
          shift
        else
          arg_error "'--llvm-url' requires a non-empty option argument"
        fi
        ;;
    --llvm-url=?*)
        LLVM_URL=${1#*=}
        ;;
    --llvm-url=)
        arg_error "'--llvm-url' requires a non-empty option argument"
        ;;
    --llvm-branch)
        if [ "$2" ]; then
          LLVM_BRANCH="$2"
          shift
        else
          arg_error "'--llvm-branch' requires a non-empty option argument"
        fi
        ;;
    --llvm-branch=?*)
        LLVM_BRANCH=${1#*=}
        ;;
    --llvm-branch=)
        arg_error "'--llvm-branch' requires a non-empty option argument"
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
  if [ ! -d "$SRC_PATH/llvm-project" ] || [ ! -d "$SRC_PATH/mingw-w64" ]; then
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
for exec in g++ cmake ninja git make python3 bzip2 curl diff; do
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

# source download: 2 clones + config.guess copy
if [ ! "$CACHED_SOURCES" ]; then
  TOTAL_STEPS=$((TOTAL_STEPS + 3))
fi

if [ "$ENABLE_THREADS" ]; then
  THREADS_STEPS=3
else
  THREADS_STEPS=0
fi

THREADS_STEPS=$((THREADS_STEPS * NUM_BUILDS))
# per arch: LLVM(3) + clang-format(1) + headers(2) + crt(3) + compiler-rt(3) + runtimes(3) + gendef(3)
BUILD_STEPS=$((21 * NUM_BUILDS))

# one packaging step (the zip) per built arch
if [ "$PACKAGE" ]; then
  PACKAGE_STEPS=$NUM_BUILDS
else
  PACKAGE_STEPS=0
fi

if [ "$JUST_SOURCES" ]; then
  TOTAL_STEPS=3
elif [ "$CLANG_FORMAT_ONLY" ]; then
  # per arch: configure LLVM(1) + build clang-format(1) + install(1)
  TOTAL_STEPS=$((TOTAL_STEPS + 3 * NUM_BUILDS))
else
  TOTAL_STEPS=$((TOTAL_STEPS + THREADS_STEPS + BUILD_STEPS + PACKAGE_STEPS))
fi

if [ "$PREFIX" ]; then
  I586_PREFIX="$PREFIX"
  I686_PREFIX="$PREFIX"
  X86_64_PREFIX="$PREFIX"
else
  I586_PREFIX="$ROOT_PATH/i586_llvm"
  I686_PREFIX="$ROOT_PATH/i686_llvm"
  X86_64_PREFIX="$ROOT_PATH/x64_llvm"
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
  [ "$BUILD_I586" ]   && package_arch i586_llvm i586_llvm
  [ "$BUILD_I686" ]   && package_arch i686_llvm i686_llvm
  [ "$BUILD_X86_64" ] && package_arch x64_llvm x64_llvm
fi

if [ ! "$KEEP_ARTIFACTS" ]; then
  if [ ! "$CACHED_SOURCES" ]; then
    remove_path "$SRC_PATH"
  fi
  remove_path "$BLD_PATH"
  # keep build.log: it's the record of the build, and --clean preserves it as build.log.old
fi

printf "${GRE}Done! \n${c0}To use this LLVM MinGW-w64 toolchain everywhere add these to your \$PATH: \n"
for add_to_path in "${ADD_TO_PATH[@]}"; do
  printf "${bold}%s ${c0}\n" "$add_to_path"
done

exit 0
