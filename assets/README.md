# Assets

This directory contains assets used for .md files (like images), and the source
for extra programs bundled into the MinGW build's `bin` dir.

In [./src/](./src) we have:

1. [peports.c](./src/peports.c) - PE export/import table listing cmdline program.  
2. [pkg-config.c](./src/pkg-config.c) - Single file minimal pkg-config replacement.  
3. [rexxd.c](./src/rexxd.c) - Replacement for xxd from w64devkit. This can do hex dumps.  
4. [uuidgen.c](./src/uuidgen.c) - Fast uuidgen replacement, can be used in widl.  
5. [clang-target-wrapper.c](./src/clang-target-wrapper.c) - LLVM toolchain entry-point wrapper; compiled once and stamped out as every `<triple>-<tool>.exe`.

-----

We also have the lovely classic Windows logos/banners:

#### Windows NT 4.0
<img src="./WinNT4Workstation_Logo.svg" height="200">

#### Windows 2000
<img src="./Win2000_Logo.svg" height="200">

#### Windows XP
<img src="./WinXP_Logo.svg" height="200">

#### Windows Vista Orb
<img src="./WinVista_Orb.svg" height="200">

<!--
#### Windows 7
<img src="./Win7_Orb.svg" height="200">

-->
