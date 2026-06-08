# Patches

This directory contains patches for MinGW, GCC, Binutils, and LLVM to support legacy versions of Windows.

Modern MinGW/LLVM/GCC/MSVC only support Windows Vista+ (2006), and SSE2+ (CPU's made after 2003).
With these patches and compiler flag tuning, we are able to produce toolchains that support
Windows NT 4.0 (1996), 2000 (2000), XP(2001), and CPUs down to the original Pentium (1994).

The LLVM patches were taken and modified from [this repo](https://github.com/mon/llvm-mingw-xp).  
Some of the MinGW/GCC patches were taken and modified from [w64devkit](https://github.com/skeeto/w64devkit/tree/master).  
A notable exception is the rand_s-win2k.patch, which I made myself for MinGW's rand_s used in std::random.

## List of patches and their purpose

### MinGW

[gendef-no-comment.patch](./mingw/gendef-no-comment.patch) - Makes `gendef` not put annoying copyright lines in the top of your *.def* files.

[headers.patch](./mingw/headers.patch) - Modifies some WinSDK version header files to default to a lower sane target.

[rand_s-win2k.patch](./mingw/rand_s-win2k.patch) - Fixes MinGW CRT `rand_s` incompatibility with Windows NT 4.0/2000, by using [`CryptGenRandom`](https://en.wikipedia.org/wiki/CryptGenRandom) instead of
                                                   XP+ [`RtlGenRandom`](https://learn.microsoft.com/en-us/windows/win32/api/ntsecapi/nf-ntsecapi-rtlgenrandom) for cryptographically secure random number generation.

[sdkddkver.h](./mingw/sdkddkver.h) and [winsdkver.h](./mingw/winsdkver.h) - Custom written replacements for these MSVC's headers, with expanded macros and definitions for old Windows.

### GCC

[gcc-stdcall-align.patch](./gcc/gcc-stdcall-align.patch) - Aligns x86 [__stdcall](https://learn.microsoft.com/en-us/cpp/cpp/stdcall) 4 byte stacks with GCC's 16 byte stack alignment expectations, increasing performance slightly.

[gcc-trap-terminate.patch](./gcc/gcc-trap-terminate.patch) - Replaces `std::terminate`'s __std::abort__ function with a __&#95;&#95;builtin_trap__ trap instruction.

[gcc-tzdb-getdynamic.patch](./gcc/gcc-tzdb-getdynamic.patch) - Fixes C++20 compatability by using [GetTimeZoneInformation](https://learn.microsoft.com/en-us/windows/win32/api/timezoneapi/nf-timezoneapi-gettimezoneinformation) instead of
                                                               Vista+ [GetDynamicTimeZoneInformation](https://learn.microsoft.com/en-us/windows/win32/api/timezoneapi/nf-timezoneapi-getdynamictimezoneinformation).

### Binutils

[binutils-dlltool-zero-ordinals.patch](./binutils-gdb/binutils-dlltool-zero-ordinals.patch) - Prevents randomizing function ordinals in libraries, which is good for reproducible builds and making static libraries more compatible.

[gdb-alternate-main.patch](./binutils-gdb/gdb-alternate-main.patch) - Allows [GDB](https://sourceware.org/gdb/) to pick up Win32 specific entry point function names like __wWinMain__, __mainCRTStartup__, etc.

### LLVM

[compiler-rt-emutls-pre-vista.patch](./llvm/compiler-rt-emutls-pre-vista.patch) - Replaces Vista+ [InitOnceExecuteOnce](https://learn.microsoft.com/en-us/windows/win32/api/synchapi/nf-synchapi-initonceexecuteonce)
                                                                                with [InterlockedCompareExchange](https://learn.microsoft.com/en-us/windows/win32/api/winnt/nf-winnt-interlockedcompareexchange)
                                                                                for [TLS](https://learn.microsoft.com/en-us/windows/win32/procthread/thread-local-storage).

[libcxx-legacy-filesystem.patch](./llvm/libcxx-legacy-filesystem.patch) - Replaces the Vista+ filesystem APIs `libc++`'s `std::filesystem` relies on
                                                                          ([GetFileInformationByHandleEx](https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-getfileinformationbyhandleex),
                                                                          [SetFileInformationByHandle](https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-setfileinformationbyhandle),
                                                                          [CreateSymbolicLinkW](https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-createsymboliclinkw),
                                                                          [GetFinalPathNameByHandleW](https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-getfinalpathnamebyhandlew))
                                                                          with NT 4.0/2000/XP equivalents (`GetFileInformationByHandle` + `DeviceIoControl`); symlink creation, `canonical()` and `permissions()` degrade to "not supported" on those targets.

[libcxx-legacy-msvcrt-locale.patch](./llvm/libcxx-legacy-msvcrt-locale.patch) - Routes the per-locale `_l` functions `libc++` uses (`_toupper_l`/`_tolower_l`, the `_iswXXX_l`/`_towXXX_l` ctype/wctype set,
                                                                             `_strcoll_l`/`_strxfrm_l`/`_wcscoll_l`/`_wcsxfrm_l`, and `_mbtowc_l`) through a thread-locale guard around the plain functions. These `_l` symbols only exist in
                                                                             msvcr80+/UCRT - some fail to *compile* (mingw doesn't declare them), but others (e.g. `_mbtowc_l`) link as `msvcrt.dll` imports that the legacy system DLL doesn't export,
                                                                             so a C++ program fails to *load* on pre-Vista with "_mbtowc_l could not be located". After this patch `libc++` imports no `_l` symbols from `msvcrt.dll`. (mingw-w64 supplies `_configthreadlocale`.)

[libcxx-legacy-msvcrt-wcrtomb_s.patch](./llvm/libcxx-legacy-msvcrt-wcrtomb_s.patch) - Shims the bounds-checked [`wcrtomb_s`](https://learn.microsoft.com/en-us/cpp/c-runtime-library/reference/wcrtomb-s) (msvcr80+/UCRT only)
                                                                                   with a local lambda built on the always-available [`wcrtomb`](https://learn.microsoft.com/en-us/cpp/c-runtime-library/reference/wcrtomb-wcrtomb-l), for legacy `msvcrt.dll`.

[libunwind-rwmutex-pre-vista.patch](./llvm/libunwind-rwmutex-pre-vista.patch) - Replaces the Vista+ [SRWLOCK](https://learn.microsoft.com/en-us/windows/win32/sync/slim-reader-writer--srw--locks)
                                                                              `libunwind`'s reader/writer mutex uses with a [CRITICAL_SECTION](https://learn.microsoft.com/en-us/windows/win32/sync/critical-section-objects) fallback (available on all NT versions), keeping `libunwind` dependency-free (no winpthreads).

[libcxx-thread-getsysteminfo.patch](./llvm/libcxx-thread-getsysteminfo.patch) - Makes `std::thread::hardware_concurrency()` fall back from the Windows 7+
                                                                              [GetActiveProcessorCount](https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-getactiveprocessorcount) to [GetSystemInfo](https://learn.microsoft.com/en-us/windows/win32/api/sysinfoapi/nf-sysinfoapi-getsysteminfo) on NT 4.0/2000/XP. (Needed on LLVM 22.x; 20.x already used GetSystemInfo.)
