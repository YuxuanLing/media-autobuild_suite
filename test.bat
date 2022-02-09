@echo off
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
set CC=gcc
if %build32%==yes call :writeProfile 32
if %build64%==yes call :writeProfile 64

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
)>%instdir%\local%1\etc\profile2.local >nul 2>&1
rem %instdir%\msys64\usr\bin\dos2unix -q %instdir%\local%1\etc\profile2.local
goto :EOF