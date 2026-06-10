# Assets

This directory contains assets like `config.guess`, images, and the sources
for extra programs bundled into the MinGW build's `bin` dir.

[`config.guess`](./config.guess) - Used by the build scripts to detect the host configuration.

In [./src/](./src) we have utilities adapted from [w64devkit](https://github.com/skeeto/w64devkit/tree/master/src):

1. [peports.c](./src/peports.c) - PE export/import table listing cmdline program.  
2. [pkg-config.c](./src/pkg-config.c) - Single file minimal pkg-config replacement.  
3. [rexxd.c](./src/rexxd.c) - Replacement for xxd from w64devkit. This can do hex dumps.  
4. [uuidgen.c](./src/uuidgen.c) - Fast uuidgen replacement, can be used in widl.  

And [clang-target-wrapper.c](./src/clang-target-wrapper.c) - LLVM toolchain entry-point wrapper; compiled once and stamped out as every `<triple>-<tool>.exe`.

-----

We also have the lovely classic Windows logos/banners:

__Windows NT 4.0__

<img src="./WinNT4Workstation_Logo.svg" height="128">

__Windows 2000__

<img src="./Win2000_Logo.svg" height="128">

__Windows XP__

<img src="./WinXP_Logo.svg" height="128">

__Windows Vista Orb__

<img src="./WinVista_Orb.svg" height="128">

<!--
__Windows 7 Orb__

<img src="./Win7_Orb.svg" height="128">

-->
