// Master include file for versioning content that ships in the Windows SDK.

// Sourced from WinSDK 10.1.26100.7175

// Cleaned up & expanded by Alex313031 2026

#ifndef _INC_WINSDKVER
#define _INC_WINSDKVER

#ifdef _MSC_VER
 #pragma once
#endif  // _MSC_VER

// This list contains the highest version constants supported by content in the Windows SDK.

#include <winapifamily.h>

#if WINAPI_FAMILY_PARTITION(WINAPI_PARTITION_DESKTOP)

// Legacy defines (_WIN32_WINDOWS / Win9x family tops out at WinME = 0x0490)
#define _WIN32_MAXVER           0x0490
#define _WIN32_WINDOWS_MAXVER   0x0490
// Standard defines
#define WINVER_MAXVER           0x0A00
#define _WIN32_WINNT_MAXVER     0x0A00
// NTDDI values are 32-bit, so this must be a full NTDDI constant (not 0x0A00)
#define NTDDI_MAXVER            0x0A000010 // NTDDI_WIN11_24H2, Build 26100
#define _WIN32_IE_MAXVER        0x0A00

#endif // _INC_WINSDKVER


