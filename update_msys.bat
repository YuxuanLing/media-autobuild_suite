@echo off
rem -----------------------------------------------------------------------------
rem LICENSE --------------------------------------------------------------------
rem -----------------------------------------------------------------------------
rem  This Windows Batchscript is for setup a compiler environment for building
rem  ffmpeg and other media tools under Windows.
rem
rem    Copyright (C) 2013  jb_alvarado
rem
rem    This program is free software: you can redistribute it and/or modify
rem    it under the terms of the GNU General Public License as published by
rem    the Free Software Foundation, either version 3 of the License, or
rem    (at your option) any later version.
rem
rem    This program is distributed in the hope that it will be useful,
rem    but WITHOUT ANY WARRANTY; without even the implied warranty of
rem    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
rem    GNU General Public License for more details.
rem
rem    You should have received a copy of the GNU General Public License
rem    along with this program.  If not, see <https://www.gnu.org/licenses/>.
rem -----------------------------------------------------------------------------

color 70
title update-msys

setlocal
chcp 65001 >nul 2>&1
cd /d "%~dp0"
set "TERM=xterm-256color"
setlocal
set instdir=%CD%

set build=%instdir%\build
if not exist %build% mkdir %build%

set build32=yes
set build64=yes
set updateSuite=y
set noMintty=y
set CC=gcc

set msyspackages=asciidoc autoconf automake-wrapper autogen base bison diffstat dos2unix filesystem help2man ^
intltool libtool patch python xmlto make zip unzip git subversion wget p7zip man-db ^
gperf winpty texinfo gyp-git doxygen autoconf-archive itstool ruby mintty flex

set mingwpackages=cmake dlfcn libpng gcc nasm pcre tools-git yasm ninja pkgconf meson ccache jq ^
clang

rem ------------------------------------------------------------------
rem download and install basic msys2 system:
rem ------------------------------------------------------------------
cd %build%
set scripts=media-suite_compile.sh media-suite_helper.sh media-suite_update.sh
for %%s in (%scripts%) do (
    if not exist "%build%\%%s" (
        powershell -Command (New-Object System.Net.WebClient^).DownloadFile('"https://github.com/m-ab-s/media-autobuild_suite/raw/master/build/%%s"', '"%%s"' ^)
    )
)

rem checkmsys2
if not exist "%instdir%\msys64\msys2_shell.cmd" (
    echo -------------------------------------------------------------------------------
    echo.
    echo.- Download and install msys2 basic system
    echo.
    echo -------------------------------------------------------------------------------
    if not exist %build%\msys2-base.sfx.exe (
    echo [System.Net.ServicePointManager]::SecurityProtocol = 'Tls12'; ^
        (New-Object System.Net.WebClient^).DownloadFile(^
        'https://github.com/msys2/msys2-installer/releases/download/nightly-x86_64/msys2-base-x86_64-latest.sfx.exe', ^
        "$PWD\msys2-base.sfx.exe"^) | powershell -NoProfile -Command - || goto :errorMsys
    )
    :unpack
    if exist %build%\msys2-base.sfx.exe (
        echo -------------------------------------------------------------------------------
        echo.
        echo.- unpacking msys2 basic system
        echo.
        echo -------------------------------------------------------------------------------
        .\msys2-base.sfx.exe x -y -o".."
        rem if exist msys2-base.sfx.exe del msys2-base.sfx.exe
    )

    if not exist %instdir%\msys64\usr\bin\msys-2.0.dll (
        :errorMsys
        echo -------------------------------------------------------------------------------
        echo.
        echo.- Download msys2 basic system failed,
        echo.- please download it manually from:
        echo.- http://repo.msys2.org/distrib/
        echo.- extract and put the msys2 folder into
        echo.- the root media-autobuid_suite folder
        echo.- and start the batch script again!
        echo.
        echo -------------------------------------------------------------------------------
        pause
        GOTO :unpack
    )
)

rem getMintty
set "bash=%instdir%\msys64\usr\bin\bash.exe"
set "PATH=%instdir%\msys64\opt\bin;%instdir%\msys64\usr\bin;%PATH%"
if not exist %instdir%\mintty.lnk (
    echo -------------------------------------------------------------------------------
    echo.- make a first run
    echo -------------------------------------------------------------------------------
    call :runBash firstrun.log exit

    sed -i "s/#Color/Color/;s/^^IgnorePkg.*/#&/" %instdir%\msys64\etc\pacman.conf

    echo.-------------------------------------------------------------------------------
    echo.first update
    echo.-------------------------------------------------------------------------------
    title first msys2 update
    call :runBash firstUpdate.log pacman --noconfirm -Sy --asdeps pacman-mirrors

    echo.-------------------------------------------------------------------------------
    echo.critical updates
    echo.-------------------------------------------------------------------------------
    pacman -S --needed --ask=20 --noconfirm --asdeps bash pacman msys2-runtime

    echo.-------------------------------------------------------------------------------
    echo.second update
    echo.-------------------------------------------------------------------------------
    title second msys2 update
    call :runBash secondUpdate.log pacman --noconfirm -Syu --asdeps

    (
        echo.Set Shell = CreateObject("WScript.Shell"^)
        echo.Set link = Shell.CreateShortcut("%instdir%\mintty.lnk"^)
        echo.link.Arguments = "-full-path -mingw -where .."
        echo.link.Description = "msys2 shell console"
        echo.link.TargetPath = "%instdir%\msys64\msys2_shell.cmd"
        echo.link.WindowStyle = 1
        echo.link.IconLocation = "%instdir%\msys64\msys2.ico"
        echo.link.WorkingDirectory = "%instdir%\msys64"
        echo.link.Save
    )>%build%\setlink.vbs
    cscript /B /Nologo %build%\setlink.vbs
    del %build%\setlink.vbs
)

rem createFolders
if %build32%==yes call :createBaseFolders local32
if %build64%==yes call :createBaseFolders local64

rem checkFstab
set "removefstab=no"
set "fstab=%instdir%\msys64\etc\fstab"
if exist %fstab%. (
    findstr build32 %fstab% >nul 2>&1 && set "removefstab=yes"
    findstr trunk %fstab% >nul 2>&1 || set "removefstab=yes"
    for /f "tokens=1 delims= " %%a in ('findstr trunk %fstab%') do if not [%%a]==[%instdir%\] set "removefstab=yes"
    findstr local32 %fstab% >nul 2>&1 && ( if [%build32%]==[no] set "removefstab=yes" ) || if [%build32%]==[yes] set "removefstab=yes"
    findstr local64 %fstab% >nul 2>&1 && ( if [%build64%]==[no] set "removefstab=yes" ) || if [%build64%]==[yes] set "removefstab=yes"
) else set removefstab=yes

if not [%removefstab%]==[no] (
    rem writeFstab
    echo -------------------------------------------------------------------------------
    echo.
    echo.- write fstab mount file
    echo.
    echo -------------------------------------------------------------------------------
    (
        echo.none / cygdrive binary,posix=0,noacl,user 0 0
        echo.
        echo.%instdir%\ /trunk ntfs binary,posix=0,noacl,user 0 0
        echo.%instdir%\build\ /build ntfs binary,posix=0,noacl,user 0 0
        echo.%instdir%\msys64\mingw32\ /mingw32 ntfs binary,posix=0,noacl,user 0 0
        echo.%instdir%\msys64\mingw64\ /mingw64 ntfs binary,posix=0,noacl,user 0 0
        if "%build32%"=="yes" echo.%instdir%\local32\ /local32 ntfs binary,posix=0,noacl,user 0 0
        if "%build64%"=="yes" echo.%instdir%\local64\ /local64 ntfs binary,posix=0,noacl,user 0 0
    )>"%instdir%\msys64\etc\fstab."
)

if not exist "%instdir%\msys64\home\%USERNAME%" mkdir "%instdir%\msys64\home\%USERNAME%"
set "TERM="
type nul >>"%instdir%\msys64\home\%USERNAME%\.minttyrc"
for /F "tokens=2 delims==" %%b in ('findstr /i TERM "%instdir%\msys64\home\%USERNAME%\.minttyrc"') do set TERM=%%b
if not defined TERM (
    printf %%s\n Locale=en_US Charset=UTF-8 Font=Consolas Columns=120 Rows=30 TERM=xterm-256color ^
    > "%instdir%\msys64\home\%USERNAME%\.minttyrc"
    set "TERM=xterm-256color"
)


rem gitsettings
if not exist "%instdir%\msys64\home\%USERNAME%\.gitconfig" (
    echo.[user]
    echo.name = %USERNAME%
    echo.email = %USERNAME%@%COMPUTERNAME%
    echo.
    echo.[color]
    echo.ui = true
    echo.
    echo.[core]
    echo.editor = vim
    echo.autocrlf =
    echo.
    echo.[merge]
    echo.tool = vimdiff
    echo.
    echo.[push]
    echo.default = simple
)>"%instdir%\msys64\home\%USERNAME%\.gitconfig"

rem installbase
if exist "%instdir%\msys64\etc\pac-base.pk" del "%instdir%\msys64\etc\pac-base.pk"
for %%i in (%msyspackages%) do echo.%%i>>%instdir%\msys64\etc\pac-base.pk

if not exist %instdir%\msys64\usr\bin\make.exe (
    echo.-------------------------------------------------------------------------------
    echo.install msys2 base system
    echo.-------------------------------------------------------------------------------
    if exist %build%\install_base_failed del %build%\install_base_failed
    title install base system
    (
        echo.echo -ne "\033]0;install base system\007"
        echo.msysbasesystem="$(cat /etc/pac-base.pk | tr '\n\r' '  ')"
        echo.[[ "$(uname)" = *6.1* ]] ^&^& nargs="-n 4"
        echo.echo $msysbasesystem ^| xargs $nargs pacman -Sw --noconfirm --ask=20 --needed
        echo.echo $msysbasesystem ^| xargs $nargs pacman -S --noconfirm --ask=20 --needed
        echo.echo $msysbasesystem ^| xargs $nargs pacman -D --asexplicit
        echo.sleep ^3
        echo.exit
    )>%build%\pacman.sh
    call :runBash pacman.log /build/pacman.sh
    del %build%\pacman.sh
)

for %%i in (%instdir%\msys64\usr\ssl\cert.pem) do if %%~zi==0 call :runBash cert.log update-ca-trust

rem installmingw
if exist "%instdir%\msys64\etc\pac-mingw.pk" del "%instdir%\msys64\etc\pac-mingw.pk"
for %%i in (%mingwpackages%) do echo.%%i>>%instdir%\msys64\etc\pac-mingw.pk
if %build32%==yes call :getmingw 32
if %build64%==yes call :getmingw 64
if exist "%build%\mingw.sh" del %build%\mingw.sh

rem updatebase
echo.-------------------------------------------------------------------------------
echo.update autobuild suite
echo.-------------------------------------------------------------------------------

cd %build%
if %updateSuite%==y (
    if not exist %instdir%\update_suite.sh (
        echo -------------------------------------------------------------------------------
        echo. Creating suite update file...
        echo.
        echo. Run this file by dragging it to mintty before the next time you run
        echo. the suite and before reporting an issue.
        echo.
        echo. It needs to be run separately and with the suite not running!
        echo -------------------------------------------------------------------------------
    )
    (
        echo.#!/bin/bash
        echo.
        echo.# Run this file by dragging it to mintty shortcut.
        echo.# Be sure the suite is not running before using it!
        echo.
        echo.update=yes
        %instdir%\msys64\usr\bin\sed -n '/start suite update/,/end suite update/p' ^
            %build%/media-suite_update.sh
    )>%instdir%\update_suite.sh
)

rem update
call :runBash update.log /build/media-suite_update.sh --build32=%build32% --build64=%build64%

if exist "%build%\update_core" (
    echo.-------------------------------------------------------------------------------
    echo.critical updates
    echo.-------------------------------------------------------------------------------
    pacman -S --needed --noconfirm --ask=20 --asdeps bash pacman msys2-runtime
    del "%build%\update_core"
)


rem ------------------------------------------------------------------
rem write config profiles:
rem ------------------------------------------------------------------

echo.-------------------------------------------------------------------------------
echo.write config profiles
echo.-------------------------------------------------------------------------------

if %build32%==yes call :writeProfile 32
if %build64%==yes call :writeProfile 64

mkdir "%instdir%\msys64\home\%USERNAME%\.gnupg" > nul 2>&1
findstr hkps://keys.openpgp.org "%instdir%\msys64\home\%USERNAME%\.gnupg\gpg.conf" >nul 2>&1 || echo keyserver hkps://keys.openpgp.org >> "%instdir%\msys64\home\%USERNAME%\.gnupg\gpg.conf"

rem loginProfile
echo.-------------------------------------------------------------------------------
echo.loginProfile
echo.-------------------------------------------------------------------------------
if exist %instdir%\msys64\etc\profile.pacnew ^
    move /y %instdir%\msys64\etc\profile.pacnew %instdir%\msys64\etc\profile
findstr /C:"profile2.local" %instdir%\msys64\etc\profile.d\Zab-suite.sh >nul 2>&1 || (
    echo.if [[ -z "$MSYSTEM" ^|^| "$MSYSTEM" = MINGW64 ]]; then
    echo.   source /local64/etc/profile2.local
    echo.elif [[ -z "$MSYSTEM" ^|^| "$MSYSTEM" = MINGW32 ]]; then
    echo.   source /local32/etc/profile2.local
    echo.fi
)>%instdir%\msys64\etc\profile.d\Zab-suite.sh

echo.-------------------------------------------------------------------------------
echo.loginProfile2
echo.-------------------------------------------------------------------------------
findstr /C:"LANG" %instdir%\msys64\etc\profile.d\Zab-suite.sh >nul 2>&1 || (
    echo.case $- in
    echo.*i*^) ;;
    echo.*^) export LANG=en_US.UTF-8 ;;
    echo.esac
)>>%instdir%\msys64\etc\profile.d\Zab-suite.sh

rem compileLocals
cd %instdir%

title MABSbat
goto :EOF

:runBash
setlocal enabledelayedexpansion
set "log=%1"
shift
set "command=%1"
shift
set args=%*
set arg=!args:%log% %command%=!
if %noMintty%==y (
    start "bash" /B /LOW /WAIT bash %build%\bash.sh "%build%\%log%" "%command%" "%arg%"
) else (
    if exist %build%\%log% del %build%\%log%
    start /I /LOW /WAIT %instdir%\msys64\usr\bin\mintty.exe -d -i /msys2.ico ^
    -t "media-autobuild_suite" --log 2>&1 %build%\%log% /usr/bin/bash -lc ^
    "%command% %arg%"
)
endlocal
goto :EOF

:createBaseFolders
if not exist %instdir%\%1\share (
    echo.-------------------------------------------------------------------------------
    echo.creating %1-bit install folders
    echo.-------------------------------------------------------------------------------
    mkdir %instdir%\%1 2>NUL
    mkdir %instdir%\%1\bin 2>NUL
    mkdir %instdir%\%1\bin-audio 2>NUL
    mkdir %instdir%\%1\bin-global 2>NUL
    mkdir %instdir%\%1\bin-video 2>NUL
    mkdir %instdir%\%1\etc 2>NUL
    mkdir %instdir%\%1\include 2>NUL
    mkdir %instdir%\%1\lib 2>NUL
    mkdir %instdir%\%1\lib\pkgconfig 2>NUL
    mkdir %instdir%\%1\share 2>NUL
)
goto :EOF

:writeProfile
(
    echo.MSYSTEM=MINGW%1
    echo.source /etc/msystem
    echo.
    echo.# package build directory
    echo.LOCALBUILDDIR=/build
    echo.# package installation prefix
    echo.LOCALDESTDIR=/local%1
    echo.export LOCALBUILDDIR LOCALDESTDIR
    echo.
    echo.bits='%1bit'
    echo.
    echo.export CONFIG_SITE=/etc/config.site
    echo.alias dir='ls -la --color=auto'
    echo.alias ls='ls --color=auto'
    if %CC%==clang (
        echo.export CC="ccache clang"
        echo.export CXX="ccache clang++"
    ) else (
        echo.export CC="ccache gcc"
        echo.export CXX="ccache g++"
    )
    echo.
    echo.CARCH="${MINGW_CHOST%%%%-*}"
    echo.CPATH="$(cygpath -pm $LOCALDESTDIR/include:$MINGW_PREFIX/include)"
    echo.LIBRARY_PATH="$(cygpath -pm $LOCALDESTDIR/lib:$MINGW_PREFIX/lib)"
    echo.export CPATH LIBRARY_PATH
    echo.
    echo.MANPATH="${LOCALDESTDIR}/share/man:${MINGW_PREFIX}/share/man:/usr/share/man"
    echo.INFOPATH="${LOCALDESTDIR}/share/info:${MINGW_PREFIX}/share/info:/usr/share/info"
    echo.
    echo.DXSDK_DIR="${MINGW_PREFIX}/${MINGW_CHOST}"
    echo.ACLOCAL_PATH="${LOCALDESTDIR}/share/aclocal:${MINGW_PREFIX}/share/aclocal:/usr/share/aclocal"
    echo.PKG_CONFIG="${MINGW_PREFIX}/bin/pkgconf --keep-system-libs --keep-system-cflags --static"
    echo.PKG_CONFIG_PATH="${LOCALDESTDIR}/lib/pkgconfig:${MINGW_PREFIX}/lib/pkgconfig"
    echo.CPPFLAGS="-D_FORTIFY_SOURCE=0 -D__USE_MINGW_ANSI_STDIO=1"
    if %CC%==clang (
        echo.CFLAGS="-mtune=generic -O2 -pipe"
    ) else (
        echo.CFLAGS="-mthreads -mtune=generic -O2 -pipe"
    )
    echo.CXXFLAGS="${CFLAGS}"
    echo.LDFLAGS="-pipe -static-libgcc -static-libstdc++"
    echo.export DXSDK_DIR ACLOCAL_PATH PKG_CONFIG PKG_CONFIG_PATH CPPFLAGS CFLAGS CXXFLAGS LDFLAGS MSYSTEM
    echo.
    echo.export CARGO_HOME="/opt/cargo" RUSTUP_HOME="/opt/cargo"
    echo.export CCACHE_DIR="$HOME/.ccache"
    echo.
    echo.export PYTHONPATH=
    echo.
    echo.LANG=en_US.UTF-8
    echo.PATH="${MINGW_PREFIX}/bin:${INFOPATH}:${MSYS2_PATH}:${ORIGINAL_PATH}"
    echo.PATH="${LOCALDESTDIR}/bin-audio:${LOCALDESTDIR}/bin-global:${LOCALDESTDIR}/bin-video:${LOCALDESTDIR}/bin:${PATH}"
    echo.PATH="/opt/cargo/bin:/opt/bin:${PATH}"
    echo.source '/etc/profile.d/perlbin.sh'
    echo.PS1='\[\033[32m\]\u@\h \[\e[33m\]\w\[\e[0m\]\n\$ '
    echo.HOME="/home/${USERNAME}"
    echo.GIT_GUI_LIB_DIR=`cygpath -w /usr/share/git-gui/lib`
    echo.export LANG PATH PS1 HOME GIT_GUI_LIB_DIR
    echo.stty susp undef
    echo.test -f "$LOCALDESTDIR/etc/custom_profile" ^&^& source "$LOCALDESTDIR/etc/custom_profile"
)>%instdir%\local%1\etc\profile2.local
%instdir%\msys64\usr\bin\dos2unix -q %instdir%\local%1\etc\profile2.local
goto :EOF

