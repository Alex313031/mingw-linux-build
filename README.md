# MinGW Build Scripts  <img src="./assets/mingw-w64.svg" width="38">

This is a collection of bash scripts to build a portable [MinGW-w64](https://mingw-w64.org) toolchain
using either the [GCC](https://gcc.gnu.org/) or [LLVM](https://llvm.org/) compiler.
It includes toolchains for i586 (Win32), i686 (Win32) and x86_64 (Win64).  
It primarily targets legacy Windows like Windows NT 4.0, Windows 2000, and XP, since latest upstream MinGW targets Vista+.  

It currently contains two bash scripts, that can be run on Ubuntu or Debian.

`mingw_gcc_linux.sh`:  Creates a MinGW/GCC build that runs on Linux.
`mingw_gcc_win.sh`:    Creates a MinGW/GCC build that runs on Windows.
`mingw_llvm_linux.sh`: Creates a MinGW/LLVM build that runs on Linux.
`mingw_llvm_win.sh`:   Creates a MinGW/LLVM build that runs on Windows.

I use it with [GN-Legacy](https://github.com/Alex313031/gn-legacy#readme) on Linux to compile many of my Win32 projects, that I specifically code to be compatible with legacy Windows for fun.

## Patches

This is a fork of [Zeranoe's mingw-w64-build repo](https://github.com/Zeranoe/mingw-w64-build#readme), and is specifically designed to support very old
versions of Windows (via patching), and provide much more customizability including many [SIMD](https://en.wikipedia.org/wiki/Single_instruction,_multiple_data) optimization options.  
See the [./patches](./patches#readme) subdirectory for more info.  

## Default Branches
* [MinGW-w64](https://mingw-w64.org) __14.x__
* [Binutils](https://www.gnu.org/software/binutils/) __2.46__
* [GCC](https://gcc.gnu.org/) __16.x__
* [LLVM](https://llvm.org/) __20.x__

## Target Platforms

The i586 build targets Pentium and Windows NT 4.0. It lacks MMX and SSE instructions.  
The i686 build targets Pentium III and Windows 2000 by default. It has SSE instructions by default.  
The x86_64 (x64) build targets Windows Server 2003 by default. It has SSE2 instructions by default.  

 - There are flags to control the minimum Windows target, and to adjust SIMD options, all the way from SSE to SSE4 to AVX and AVX2

## Usage
`mingw_*.sh` __&lt;arch&gt; [options]__

To install prerequisites the script(s) needs to run, use the `--deps` flag.  

Some common options are:  

`--all` - Build for all architectures.  
`--package` - Package the build(s) into .zip files, ready for distribution.  
`--deps` - Install build deps like zip, make, autoconf, curl, etc.  
`--clean` - Nuke all sources and build output.  
`--debug` - Make a debug build instead of a release build, for debugging issues in the CRT itself.  
`--verbose` - Verbose logging output  
`--jobs` - Adjust number of concurrent build jobs (default is num. CPUs)  

&nbsp;&ndash;&nbsp;See `--help` for all build options.  

### Host Platforms
The scripts should run on Ubuntu, Debian, Cygwin, MSYS2, macOS (with Homebrew), and other __bash__ based shells.  
The host tools compile with SSE3 by default: Any reasonably modern OS/Machine should handle it.  

It uses `config.guess` in [./assets](./assets/config.guess) to auto-configure for your platform.

### Default Prefix
Run --help to see the current install prefix for a given script.  

It does not need to be "installed", the prefix simply chooses where to put built files: the toolchain is fully portable.  
One can run --package, and simply copy the .zip somewhere, and unpack it.
Then, add the dir `<where_you_extracted_it>/bin` to your `$PATH`. And add/update the `$MINGW_HOME` environment variable to point to `<where_you_extracted_it>`.

## License
This repo is licensed under the GNU GPL 3.0 or later.  
A copy of the license can be found in the [LICENSE.md](./LICENSE.md) file.
