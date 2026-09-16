@echo off
rem ===========================================================================
rem  DSH newbie one-click installer / updater  (Windows)
rem  This file is intentionally pure ASCII: cmd.exe parses it in the OEM code
rem  page, so all Chinese text lives in tools\install.ps1 (saved as UTF-8 BOM).
rem
rem  DO NOT add "chcp 65001" here. With the console at code page 65001,
rem  Windows PowerShell 5.1 prefixes a UTF-8 BOM to whatever it pipes into a
rem  native command's stdin, and the kb-rag engine then fails with
rem  "Unexpected UTF-8 BOM". Chinese renders fine on a Chinese Windows console
rem  (code page 936) without touching it; install.ps1 switches to UTF-8 itself
rem  only when the console code page cannot show Chinese at all.
rem
rem  WHY THE LONG -EncodedCommand LINE FURTHER DOWN:
rem  The most common newbie mistake is double-clicking install.cmd *inside* the
rem  .zip -- Explorer opens archives like folders, so nothing is extracted and
rem  tools\ is missing. The old message here was English-only, which leaves a
rem  Chinese newbie stuck. We cannot put Chinese in this file (see above), so
rem  the explanation ships as a base64 UTF-16LE -EncodedCommand blob: code-page
rem  independent, still pure ASCII on disk.
rem  Regenerate with:
rem    [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($script))
rem
rem  NOTE: labels are used instead of "( ... )" blocks on purpose -- inside a
rem  parenthesised block cmd expands %VAR% when the block is parsed, so a
rem  variable set in the same block would still be empty.
rem ===========================================================================
title DSH Setup
setlocal

if exist "%~dp0tools\install.ps1" goto run

set "DSH_HERE=%~dp0"
set "DSH_INZIP="
if /i not "%DSH_HERE:.zip\=%"=="%DSH_HERE%" set "DSH_INZIP=1"
if /i not "%DSH_HERE:Temp1_=%"=="%DSH_HERE%" set "DSH_INZIP=1"
powershell -NoProfile -ExecutionPolicy Bypass -EncodedCommand JABoAGUAcgBlACAAPQAgACQAZQBuAHYAOgBEAFMASABfAEgARQBSAEUACgBXAHIAaQB0AGUALQBIAG8AcwB0ACAAJwAnAAoAaQBmACAAKAAkAGUAbgB2ADoARABTAEgAXwBJAE4AWgBJAFAAKQAgAHsACgAgACAAVwByAGkAdABlAC0ASABvAHMAdAAgACcAIAAgAFsAIQBdACAAYE8vZihXDDCLUyl/BVPMkWKXDTD0dqVjzFP7UdCPTIiEdgIwJwAgAC0ARgBvAHIAZQBnAHIAbwB1AG4AZABDAG8AbABvAHIAIABZAGUAbABsAG8AdwAKACAAIABXAHIAaQB0AGUALQBIAG8AcwB0ACAAJwAgACAAIAAgACAAIABXAGkAbgBkAG8AdwBzACAAGk+KYiAAegBpAHAAIABTX4dl9k45WQBON2hTYgBfDP9GT8xT+1HMkWKXhHaHZfZOdl6hbAlnH3eEduOJi1MM/ycACgAgACAAVwByAGkAdABlAC0ASABvAHMAdAAgACcAIAAgACAAIAAgACAAQGLlTn5iDU4wUiAAdABvAG8AbABzAFwAaQBuAHMAdABhAGwAbAAuAHAAcwAxAAz/GoEsZ9GNDU53jWVnAjAnAAoAfQAgAGUAbABzAGUAIAB7AAoAIAAgAFcAcgBpAHQAZQAtAEgAbwBzAHQAIAAnACAAIABbACEAXQAgAKFsfmIwUiAAdABvAG8AbABzAFwAaQBuAHMAdABhAGwAbAAuAHAAcwAxACAAFCAUICAA2Y8qTolbxYgFUw1OjFt0ZQIwJwAgAC0ARgBvAHIAZQBnAHIAbwB1AG4AZABDAG8AbABvAHIAIABZAGUAbABsAG8AdwAKACAAIABXAHIAaQB0AGUALQBIAG8AcwB0ACAAJwAgACAAIAAgACAAIAA4XsGJn1PgVhr/6lOKYiAAaQBuAHMAdABhAGwAbAAuAGMAbQBkACAA1mKGTvpRZWcBMOOJi1MwUgBOSlMtTq1lhk4BMBZih2X2TquIQGdvjyBSiWMCMCcACgB9AAoAVwByAGkAdABlAC0ASABvAHMAdAAgACcAJwAKAFcAcgBpAHQAZQAtAEgAbwBzAHQAIAAnACAAIABja254hHZaUNVsCP8JTmVrCf8a/ycAIAAtAEYAbwByAGUAZwByAG8AdQBuAGQAQwBvAGwAbwByACAAQwB5AGEAbgAKAFcAcgBpAHQAZQAtAEgAbwBzAHQAIAAnACAAIAAgACAAMQAuACAA81MulaOQKk4gAC4AegBpAHAAIACLUyl/BVMgAJIhIAAJkAwwaFHokOOJi1MpfyYgDTAnAAoAVwByAGkAdABlAC0ASABvAHMAdAAgACcAIAAgACAAIAAgACAAIAAI/w1OgYnMU/tR24+LUyl/BVMBMF9ODU6BiepT1mIATipOh2X2TvpRZWcJ/ycACgBXAHIAaQB0AGUALQBIAG8AcwB0ACAAJwAgACAAIAAgADIALgAgAOOJi1MwUgBOKk56evSVRVGzjYR2h2X2TjlZDP+LT4JZIABEADoAXABkAHMAaAAtAG8AbgBlAGMAbABpAGMAawAnAAoAVwByAGkAdABlAC0ASABvAHMAdAAgACcAIAAgACAAIAAzAC4AIADbjzBS44mLU/pRZWeEdodl9k45WcyRDP/MU/tRIABpAG4AcwB0AGEAbABsAC4AYwBtAGQAJwAKAFcAcgBpAHQAZQAtAEgAbwBzAHQAIAAnACcACgBpAGYAIAAoACQAaABlAHIAZQApACAAewAgAFcAcgBpAHQAZQAtAEgAbwBzAHQAIAAoACcAIAAgAGBP2Y8ha9CPTIiEdk1Pbn8a/ycAIAArACAAJABoAGUAcgBlACkAIAAtAEYAbwByAGUAZwByAG8AdQBuAGQAQwBvAGwAbwByACAARABhAHIAawBHAHIAYQB5ACAAfQAKAFcAcgBpAHQAZQAtAEgAbwBzAHQAIAAnACAAIABFAG4AZwBsAGkAcwBoADoAIABlAHgAdAByAGEAYwB0ACAAdABoAGUAIABXAEgATwBMAEUAIAB6AGkAcAAgAHQAbwAgAGEAIABmAG8AbABkAGUAcgAgAGYAaQByAHMAdAAsACAAdABoAGUAbgAgAHIAdQBuACAAaQBuAHMAdABhAGwAbAAuAGMAbQBkACAAaQBuAHMAaQBkAGUAIABpAHQALgAnACAALQBGAG8AcgBlAGcAcgBvAHUAbgBkAEMAbwBsAG8AcgAgAEQAYQByAGsARwByAGEAeQAKAFcAcgBpAHQAZQAtAEgAbwBzAHQAIAAnACcA
if errorlevel 1 (
  echo.
  echo   [!] tools\install.ps1 not found.
  echo       Extract the WHOLE zip to a folder first, then run install.cmd inside it.
  echo.
)
pause
exit /b 1

:run
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\install.ps1" %*
set RC=%ERRORLEVEL%

if not "%RC%"=="0" (
  echo.
  echo   [!] Setup exited with code %RC%.
  echo       Read the messages above; the installer also printed the exact
  echo       log file path on its last line.
  echo.
  pause
)

endlocal
exit /b %RC%