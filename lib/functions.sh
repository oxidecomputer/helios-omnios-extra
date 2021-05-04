#!/bin/bash
#
# {{{ CDDL HEADER START
#
# The contents of this file are subject to the terms of the
# Common Development and Distribution License, Version 1.0 only
# (the "License").  You may not use this file except in compliance
# with the License.
#
# You can obtain a copy of the license at usr/src/OPENSOLARIS.LICENSE
# or http://www.opensolaris.org/os/licensing.
# See the License for the specific language governing permissions
# and limitations under the License.
#
# When distributing Covered Code, include this CDDL HEADER in each
# file and include the License file at usr/src/OPENSOLARIS.LICENSE.
# If applicable, add the following below this CDDL HEADER, with the
# fields enclosed by brackets "[]" replaced with your own identifying
# information: Portions Copyright [yyyy] [name of copyright owner]
#
# CDDL HEADER END }}}
#
# Copyright (c) 2014 by Delphix. All rights reserved.
# Copyright 2015 OmniTI Computer Consulting, Inc.  All rights reserved.
# Copyright 2018 OmniOS Community Edition (OmniOSce) Association.
# Use is subject to license terms.
#

umask 022

#############################################################################
# functions.sh
#############################################################################
# Helper functions for building packages that should be common to all build
# scripts
#############################################################################

# Set a basic path - it will be modified once config.sh is loaded
PATH=/usr/bin:/usr/sbin:/usr/gnu/bin

#############################################################################
# Process command line options
#############################################################################
process_opts() {
    SCREENOUT=
    FLAVOR=
    OLDFLAVOR=
    BUILDARCH=both
    OLDBUILDARCH=
    BATCH=
    AUTOINSTALL=
    DEPVER=
    SKIP_PKGLINT=
    SKIP_HARDLINK=
    SKIP_PKG_DIFF=
    REBASE_PATCHES=
    SKIP_TESTSUITE=
    SKIP_CHECKSUM=
    EXTRACT_MODE=0
    while getopts "bciPptsf:ha:d:Llr:x" opt; do
        case $opt in
            h)
                show_usage
                exit
                ;;
            \?)
                show_usage
                exit 2
                ;;
            l)
                SKIP_PKGLINT=1
                ;;
            L)
                SKIP_HARDLINK=1
                ;;
            p)
                SCREENOUT=1
                ;;
            P)
                REBASE_PATCHES=1
                ;;
            b)
                BATCH=1 # Batch mode - exit on error
                SKIP_PKG_DIFF=1
                ;;
            c)
                USE_CCACHE=1
                ;;
            i)
                AUTOINSTALL=1
                ;;
            t)
                SKIP_TESTSUITE=1
                ;;
            s)
                SKIP_CHECKSUM=1
                ;;
            f)
                FLAVOR="$OPTARG"
                OLDFLAVOR="$OPTARG" # Used to see if the script overrides
                ;;
            r)
                PKGSRVR=$OPTARG
                ;;
            a)
                BUILDARCH=$OPTARG
                OLDBUILDARCH=$OPTARG # Used to see if the script overrides the
                                     # BUILDARCH variable
                if [[ ! "$BUILDARCH" =~ ^(32|64|both)$ ]]; then
                    echo "Invalid build architecture specified: $BUILDARCH"
                    show_usage
                    exit 2
                fi
                ;;
            d)
                DEPVER=$OPTARG
                ;;
            x)
                (( EXTRACT_MODE++ ))
                ;;
        esac
    done
}

#############################################################################
# Show usage information
#############################################################################
show_usage() {
cat << EOM

Usage: $0 [-blt] [-f FLAVOR] [-h] [-a 32|64|both] [-d DEPVER]
  -a ARCH   : build 32/64 bit only, or both (default: both)
  -b        : batch mode (exit on errors without asking)
  -c        : use 'ccache' to speed up (re-)compilation
  -d DEPVER : specify an extra dependency version (no default)
  -f FLAVOR : build a specific package flavor
  -h        : print this help text
  -i        : autoinstall mode (install build deps)
  -l        : skip pkglint check
  -L        : skip hardlink target check
  -p        : output all commands to the screen as well as log file
  -P        : re-base patches on latest source
  -r REPO   : specify the IPS repo to use
              (default: $PKGSRVR)
  -t        : skip test suite
  -s        : skip checksum comparison
  -x        : download and extract source only
  -xx       : as -x but also apply patches

EOM
}

print_config() {
    cat << EOM

MYDIR:                  $MYDIR
LIBDIR:                 $LIBDIR
ROOTDIR:                $ROOTDIR
TMPDIR:                 $TMPDIR
DTMPDIR:                $DTMPDIR

Mirror:                 $MIRROR
Publisher:              $PKGPUBLISHER
Production IPS Repo:    $IPS_REPO
Repository:             $PKGSRVR
Privilege Escalation:   $PFEXEC

EOM
}

#############################################################################
# Log output of a command to a file
#############################################################################
logcmd() {
    typeset preserve_stdout=0
    [ "$1" = "-p" ] && shift && preserve_stdout=1
    echo Running: "$@" >> $LOGFILE
    if [ -z "$SCREENOUT" ]; then
        if [ "$preserve_stdout" = 0 ]; then
            "$@" >> $LOGFILE 2>&1
        else
            "$@"
        fi
    else
        if [ "$preserve_stdout" = 0 ]; then
            echo Running: "$@"
            "$@" | tee -a $LOGFILE 2>&1
            return ${PIPESTATUS[0]}
        else
            "$@"
        fi
    fi
}

pipelog() {
    tee -a $LOGFILE 2>&1
}

c_highlight="`tput setaf 2`"
c_error="`tput setaf 1`"
c_note="`tput setaf 6`"
c_reset="`tput sgr0`"
logmsg() {
    typeset highlight=0
    [ "$1" = "-h" ] && shift && highlight=1
    [ "$1" = "-e" ] && shift && highlight=2
    [ "$1" = "-n" ] && shift && highlight=3

    echo "$logprefix$@" >> $LOGFILE
    case $highlight in
        1) echo "$c_highlight$logprefix$@$c_reset" ;;
        2) echo "$c_error$logprefix$@$c_reset" ;;
        3) echo "$c_note$logprefix$@$c_reset" ;;
        *) echo "$logprefix$@" ;;
    esac
}

logerr() {
    [ "$1" = "-b" ] && BATCH=1 && shift
    # Print an error message and ask the user if they wish to continue
    logmsg -e "$@"
    if [ -z "$BATCH" ]; then
        ask_to_continue "An Error occured in the build. "
    else
        exit 1
    fi
}

note() {
    typeset xarg=
    [ "$1" = "-h" ] && xarg=$1 && shift
    [ "$1" = "-e" ] && xarg=$1 && shift
    [ "$1" = "-n" ] && xarg=$1 && shift
    logmsg ""
    logmsg $xarg "***"
    logmsg $xarg "*** $@"
    logmsg $xarg "***"
}

ask_to_continue_() {
    MSG=$2
    STR=$3
    RE=$4
    # Ask the user if they want to continue or quit in the event of an error
    echo -n "${1}${MSG} ($STR) "
    read
    while [[ ! "$REPLY" =~ $RE ]]; do
        echo -n "continue? ($STR) "
        read
    done
}

ask_to_continue() {
    ask_to_continue_ "${1}" "Do you wish to continue anyway?" "y/n" "[yYnN]"
    if [[ "$REPLY" == "n" || "$REPLY" == "N" ]]; then
        logmsg -e "===== Build aborted ====="
        exit 1
    fi
    logmsg "===== User elected to continue after prompt. ====="
}

ask_to_install() {
    ati_PKG=$1
    MSG=$2
    if [ -n "$AUTOINSTALL" ]; then
        logmsg "Auto-installing $ati_PKG..."
        logcmd $PFEXEC pkg install $ati_PKG || \
            logerr "pkg install $ati_PKG failed"
        return
    fi
    if [ -n "$BATCH" ]; then
        logmsg -e "===== Build aborted ====="
        exit 1
    fi
    ask_to_continue_ "$MSG " "Install/Abort?" "i/a" "[iIaA]"
    if [[ "$REPLY" == "i" || "$REPLY" == "I" ]]; then
        logcmd $PFEXEC pkg install $ati_PKG || logerr "pkg install failed"
    else
        logmsg -e "===== Build aborted ====="
        exit 1
    fi
}

ask_to_pkglint() {
    ask_to_continue_ "" "Do you want to run pkglint?" \
        "y/n" "[yYnN]"
    [[ "$REPLY" == "y" || "$REPLY" == "Y" ]]
}

ask_to_testsuite() {
    ask_to_continue_ "" "Do you want to run the test-suite?" \
        "y/n" "[yYnN]"
    [[ "$REPLY" == "y" || "$REPLY" == "Y" ]]
}

#############################################################################
# URL encoding for package names, at least
#############################################################################
# This isn't real URL encoding, just a couple of common substitutions
url_encode() {
    [ $# -lt 1 ] && logerr "Not enough arguments to url_encode()"
    local encoded="$1";
    echo $* | sed -e '
        s!/!%2F!g
        s!+!%2B!g
        s/%../_/g
    '
}

#############################################################################
# ASCII character to number
#############################################################################

# Turn the letter component of the version into a number for IPS versioning
ord26() {
    local ASCII=$(printf '%d' "'$1")
    ASCII=$((ASCII - 64))
    [[ $ASCII -gt 32 ]] && ASCII=$((ASCII - 32))
    echo $ASCII
}

set_coredir() {
    # Change the core pattern so that core files contain all available
    # information and are stored centrally in the provided directory
    coreadm -P all -p $1/core.%f.%t
}

#############################################################################
# Some initialization
#############################################################################

# The dir where this file is located - used for sourcing further files
MYDIR=$PWD/`dirname $BASH_SOURCE[0]`
LIBDIR="`realpath $MYDIR`"
ROOTDIR="`dirname $LIBDIR`"
# The dir where this file was sourced from - this will be the directory of the
# build script
SRCDIR=$PWD/`dirname $0`

#############################################################################
# Load configuration options
#############################################################################
. $MYDIR/config.sh
[ -f $MYDIR/site.sh ] && . $MYDIR/site.sh
BASE_TMPDIR=$TMPDIR

set_coredir $TMPDIR

BASEPATH=/usr/ccs/bin:$USRBIN:/usr/sbin:$OOCEBIN:$GNUBIN:$SFWBIN
export PATH=$BASEPATH

# Platform information, e.g. 5.11
SUNOSVER=`uname -r`

MYSCRIPT=${BASH_SOURCE[1]##*/}
[[ $MYSCRIPT = build*.sh ]] && LOGFILE=$PWD/${MYSCRIPT/%.sh/.log}

[ -f "$LOGFILE" ] && mv $LOGFILE $LOGFILE.1

process_opts $@
shift $((OPTIND - 1))

#############################################################################
# Running as root is not safe
#############################################################################
if [ "$UID" = "0" ]; then
    if [ -n "$ROOT_OK" ]; then
        logmsg "--- Running as root, but ROOT_OK is set; continuing"
    else
        logerr "--- You should not run this as root"
    fi
fi

#############################################################################
# Utilities
#############################################################################

parallelise() {
    local num="${1:-1}"
    while [ "`jobs -rp | wc -l`" -ge "$num" ]; do
        sleep 1
    done
}

#############################################################################
# Set up tools area
#############################################################################

init_tools() {
    BASEPATH=$TMPDIR/tools:$BASEPATH
    [ -d $TMPDIR/tools ] && return
    logcmd mkdir -p $TMPDIR/tools || logerr "mkdir tools failed"
    # Disable any commands that should not be used for the build
    for cmd in cc CC; do
        logcmd ln -sf /bin/false $TMPDIR/tools/$cmd || logerr "ln $cmd failed"
    done
}

init_tools

#############################################################################
# Compiler version
#############################################################################

SSPFLAGS=
set_ssp() {
    case "$1" in
        none)   SSPFLAGS=; SKIP_SSP_CHECK=1 ;;
        strong) SSPFLAGS="-fstack-protector-strong" ;;
        basic)  SSPFLAGS="-fstack-protector" ;;
        all)    SSPFLAGS="-fstack-protector-all" ;;
        *)      logerr "Unknown stack protector variant ($1)" ;;
    esac
    local LCFLAGS=`echo $CFLAGS | sed 's/-fstack-protector[^ ]*//'`
    local LCXXFLAGS=`echo $CXXFLAGS | sed 's/-fstack-protector[^ ]*//'`
    CFLAGS="$LCFLAGS $SSPFLAGS"
    CXXFLAGS="$LCFLAGS $SSPFLAGS"
    [ -z "$2" ] && logmsg "-- Set stack protection to '$1'"
}

set_gccver() {
    GCCVER="$1"
    [ -z "$2" ] && logmsg "-- Setting GCC version to $GCCVER"
    GCCPATH="/opt/gcc-$GCCVER"
    GCC="$GCCPATH/bin/gcc"
    GXX="$GCCPATH/bin/g++"
    [ -x "$GCC" ] || logerr "Unknown compiler version $GCCVER"
    PATH="$GCCPATH/bin:$BASEPATH"
    if [ -n "$USE_CCACHE" ]; then
        [ -x $CCACHE_PATH/ccache ] || logerr "Ccache is not installed"
        PATH="$CCACHE_PATH:$PATH"
    fi
    export GCC GXX GCCVER GCCPATH PATH

    CFLAGS="${FCFLAGS[_]} ${FCFLAGS[$GCCVER]}"
    CXXFLAGS="${FCFLAGS[_]} ${FCFLAGS[$GCCVER]}"
    CTF_CFLAGS="${CTFCFLAGS[_]} ${CTFCFLAGS[$GCCVER]}"

    set_ssp strong $2
}

set_gccver $DEFAULT_GCC_VER -q

#############################################################################
# Go version
#############################################################################

set_gover() {
    GOVER="$1"
    logmsg "-- Setting Go version to $GOVER"
    GO_PATH="/opt/ooce/go-$GOVER"
    PATH="$GO_PATH/bin:$PATH"
    GOROOT_BOOTSTRAP="$GO_PATH"
    # go binaries contain BMI instructions even when built on an older CPU
    BMI_EXPECTED=1
    # skip rtime check for go builds
    SKIP_RTIME_CHECK=1
    export PATH GOROOT_BOOTSTRAP

    BUILD_DEPENDS_IPS+=" ooce/developer/go-${GOVER//./}"
}

#############################################################################
# node.js version
#############################################################################

set_nodever() {
    NODEVER="$1"
    logmsg "-- Setting node.js version to $NODEVER"
    NODEPATH="/opt/ooce/node-$NODEVER"
    PATH="$NODEPATH/bin:$PATH"
    export PATH

    BUILD_DEPENDS_IPS+=" ooce/runtime/node-$NODEVER"
}

#############################################################################
# Ruby version
#############################################################################

set_rubyver() {
    RUBYVER="$1"
    logmsg "-- Setting Ruby version to $RUBYVER"
    RUBYPATH="/opt/ooce/ruby-$RUBYVER"
    PATH="$RUBYPATH/bin:$PATH"
    export PATH

    BUILD_DEPENDS_IPS+=" ooce/runtime/ruby-${RUBYVER//./}"
}

#############################################################################
# Default configure options.
#############################################################################

reset_configure_opts() {
    # If it's the global default (/usr), we want sysconfdir to be /etc
    # otherwise put it under PREFIX
    [ $PREFIX = "/usr" ] && SYSCONFDIR=/etc || SYSCONFDIR=/etc$PREFIX

    CONFIGURE_OPTS_32="
        --prefix=$PREFIX
        --sysconfdir=$SYSCONFDIR
        --includedir=$PREFIX/include
    "
    CONFIGURE_OPTS_64="$CONFIGURE_OPTS_32"

    if [ -n "$FORGO_ISAEXEC" ]; then
        CONFIGURE_OPTS_32+="
            --bindir=$PREFIX/bin
            --sbindir=$PREFIX/sbin
            --libdir=$PREFIX/lib
            --libexecdir=$PREFIX/libexec
        "
        CONFIGURE_OPTS_64+="
            --bindir=$PREFIX/bin
            --sbindir=$PREFIX/sbin
            --libdir=$PREFIX/lib/$ISAPART64
            --libexecdir=$PREFIX/libexec/$ISAPART64
        "
    else
        CONFIGURE_OPTS_32+="
            --bindir=$PREFIX/bin/$ISAPART
            --sbindir=$PREFIX/sbin/$ISAPART
            --libdir=$PREFIX/lib
            --libexecdir=$PREFIX/libexec
        "
        CONFIGURE_OPTS_64+="
            --bindir=$PREFIX/bin/$ISAPART64
            --sbindir=$PREFIX/sbin/$ISAPART64
            --libdir=$PREFIX/lib/$ISAPART64
            --libexecdir=$PREFIX/libexec/$ISAPART64
        "
    fi
}
reset_configure_opts

set_standard() {
    typeset st="$1"
    typeset var="${2:-CPPFLAGS}"
    [ -n "${STANDARDS[$st]}" ] || logerr "Unknown standard $st"
    declare -n _var=$var
    _var+=" ${STANDARDS[$st]}"
}

forgo_isaexec() {
    FORGO_ISAEXEC=1
    reset_configure_opts
}

set_arch() {
    [[ $1 =~ ^(both|32|64)$ ]] || logerr "Bad argument to set_arch"
    BUILDARCH=$1
    forgo_isaexec
}

BasicRequirements() {
    local needed=""
    [ -x $GCCPATH/bin/gcc ] || needed+=" developer/gcc$GCCVER"
    [ -x /usr/bin/ar ] || needed+=" developer/object-file"
    [ -x /usr/bin/ld ] || needed+=" developer/linker"
    [ -x /usr/bin/gmake ] || needed+=" developer/build/gnu-make"
    [ -f /usr/include/sys/types.h ] || needed+=" system/header"
    [ -f /usr/include/math.h ] || needed+=" system/library/math"
    if [ -n "$needed" ]; then
        logmsg "You appear to be missing some basic build requirements."
        logmsg "To fix this run:"
        logmsg " "
        logmsg "  $PFEXEC pkg install$needed"
        if [ -n "$BATCH" ]; then
            logmsg -e "===== Build aborted ====="
            exit 1
        fi
        echo
        for i in "$needed"; do
           ask_to_install $i "--- Build-time dependency $i not found"
        done
    fi
}
BasicRequirements

#############################################################################
# Check the OpenSSL mediator
#############################################################################

opensslver=`pkg mediator -H openssl 2>/dev/null| awk '{print $3}'`
defsslver="1.1"
if [ -n "$opensslver" -a "$opensslver" != "$defsslver" ]; then
    if [ -n "$OPENSSL_TEST" ]; then
        logmsg -h "--- OpenSSL version $opensslver but OPENSSL_TEST is set"
    else
        logerr "--- OpenSSL version $opensslver should not be used for build"
    fi
fi

#############################################################################
# Print startup message
#############################################################################

logmsg "===== Build started at `date` ====="

print_elapsed() {
    typeset s=$1
    printf '%dh%dm%ds' $((s/3600)) $((s%3600/60)) $((s%60))
}

build_end() {
    rv=$?
    if [ -n "$PKG" -a -n "$build_start" ]; then
        logmsg "Time: $PKG - $(print_elapsed $((`date +%s` - build_start)))"
        build_start=
    fi
    exit $rv
}

build_start=`date +%s`
trap 'build_end' EXIT

#############################################################################
# Libtool -nostdlib hacking
# libtool doesn't put -nostdlib in the shared archive creation command
# we need it sometimes.
#############################################################################

libtool_nostdlib() {
    FILE="$1"
    EXTRAS="$2"
    logcmd perl -pi -e \
        's#(\$CC.*\$compiler_flags)#$1 -nostdlib '"$EXTRAS"'#g;' $FILE \
        || logerr "--- Patching libtool:$FILE for -nostdlib support failed"
}

#############################################################################
# Initialization function
#############################################################################

init_repo() {
    if [[ "$PKGSRVR" == file:/* ]]; then
        RPATH="`echo $PKGSRVR | sed 's^file:/*^/^'`"
        if [ ! -d "$RPATH" ]; then
            logmsg "-- Initialising local repo at $RPATH"
            pkgrepo create $RPATH || logerr "Could not create local repo"
            pkgrepo add-publisher -s $RPATH $PKGPUBLISHER || \
                logerr "Could not set publisher on local repo"
        fi
    fi
}

github_latest() {
    logmsg "-- Retrieving latest release version from github"

    [[ $MIRROR = $GITHUB/* ]] \
        || logerr "Cannot use github latest without github mirror"

    local repoprog=`echo $MIRROR | cut -d/ -f4-5`
    local ep=$GITHUBAPI/repos/$repoprog/releases

    local filter="map(select (.draft == false)"
    if [ "$VER" != github-latest-prerelease ]; then
        filter+=" | select (.prerelease == false)"
    fi
    filter+=") | first | .tag_name"

    local tag=`$CURL -s $ep | $JQ -r "$filter"`
    [ -n "$tag" -a "$tag" != "null" ] \
        || logerr "--- Could not retrieve latest version from github"

    VER="${tag#v}"
    logmsg "--- Github release $tag, set VER=$VER"
}

init() {
    # Print out current settings
    logmsg "Package name: $PKG"
    # Selected flavor
    if [ -z "$FLAVOR" ]; then
        logmsg "Selected flavor: None (use -f to specify a flavor)"
    else
        logmsg "Selected Flavor: $FLAVOR"
    fi
    if [ -n "$OLDFLAVOR" -a "$OLDFLAVOR" != "$FLAVOR" ]; then
        logmsg "NOTICE - The flavor was overridden by the build script."
        logmsg "The flavor specified on the command line was: $OLDFLAVOR"
    fi
    # Build arch
    logmsg "Selected build arch: $BUILDARCH"
    if [ -n "$OLDBUILDARCH" -a "$OLDBUILDARCH" != "$BUILDARCH" ]; then
        logmsg "NOTICE - The build arch was overridden by the build script."
        logmsg "The build arch specified on the command line was: $OLDFLAVOR"
    fi
    # Extra dependency version
    if [ -z "$DEPVER" ]; then
        logmsg "Extra dependency: None (use -d to specify a version)"
    else
        logmsg "Extra dependency: $DEPVER"
    fi
    # Ensure SUMMARY and DESC are non-empty
    if [ -z "$SUMMARY" ]; then
        logerr "SUMMARY may not be empty. Please update your build script"
    elif [ -z "$DESC" ]; then
        logerr "DESC may not be empty. Please update your build script"
    fi

    [[ "$VER" = github-latest* ]] && github_latest

    # Blank out the source code location
    _ARC_SOURCE=

    # BUILDDIR can be used to manually specify what directory the program is
    # built in (i.e. what the tarball extracts to). This defaults to the name
    # and version of the program, which works in most cases.
    [ -z "$BUILDDIR" ] && BUILDDIR=$PROG-$VER
    # Preserve the original BUILDDIR since this can be changed for an
    # out-of-tree build
    EXTRACTED_SRC=$BUILDDIR

    # Build each package in a sub-directory of the temporary area.
    # In addition to keeping everything related to a package together,
    # this also prevents problems with packages which have non-unique archive
    # names (1.2.3.tar.gz) or non-unique prog names.
    [ -n "$PROG" ] || logerr "\$PROG is not defined for this package."
    [ "$TMPDIR" = "$BASE_TMPDIR" ] && TMPDIR="$BASE_TMPDIR/$PROG-$VER"
    [ "$DTMPDIR" = "$BASE_TMPDIR" ] && DTMPDIR="$TMPDIR"

    # Update the core file directory
    set_coredir $TMPDIR

    init_repo
    pkgrepo get -s $PKGSRVR > /dev/null 2>&1 || \
        logerr "The PKGSRVR ($PKGSRVR) isn't available. All is doomed."
    verify_depends

    if [ -n "$FORCE_OPENSSL_VERSION" ]; then
        CFLAGS="-I/usr/ssl-$FORCE_OPENSSL_VERSION/include $CFLAGS"
        LDFLAGS32="-L/usr/ssl-$FORCE_OPENSSL_VERSION/lib $LDFLAGS32"
        LDFLAGS64="-L/usr/ssl-$FORCE_OPENSSL_VERSION/lib/amd64 $LDFLAGS64"
    fi

    # Create symbolic links to build area
    logcmd mkdir -p $TMPDIR
    [ -h $SRCDIR/tmp ] && rm -f $SRCDIR/tmp
    logcmd ln -sf $TMPDIR $SRCDIR/tmp
    [ -h $TMPDIR/src ] && rm -f $TMPDIR/src
    logcmd ln -sf $BUILDDIR $TMPDIR/src
}

set_builddir() {
    BUILDDIR="$1"
    EXTRACTED_SRC="$1"
}

#############################################################################
# Verify any dependencies
#############################################################################

verify_depends() {
    logmsg "Verifying dependencies"
    # Support old-style runtime deps
    if [ -n "$DEPENDS_IPS" -a -n "$RUN_DEPENDS_IPS" ]; then
        # Either old way or new, not both.
        logerr "DEPENDS_IPS is deprecated. Please list all runtime dependencies in RUN_DEPENDS_IPS."
    elif [ -n "$DEPENDS_IPS" -a -z "$RUN_DEPENDS_IPS" ]; then
        RUN_DEPENDS_IPS=$DEPENDS_IPS
    fi
    # If only DEPENDS_IPS is used, assume the deps are build-time as well
    if [ -z "$BUILD_DEPENDS_IPS" -a -n "$DEPENDS_IPS" ]; then
        BUILD_DEPENDS_IPS=$DEPENDS_IPS
    fi
    for i in $BUILD_DEPENDS_IPS; do
        logmsg "-- Checking for build dependency $i"
        # Trim indicators to get the true name (see make_package for details)
        case ${i:0:1} in
            \=|\?)
                i=${i:1}
                ;;
            \-)
                # If it's an exclude, we should error if it's installed rather
                # than missing
                i=${i:1}
                logcmd pkg info -q $i \
                    && logerr "--- $i should not be installed during build."
                continue
                ;;
        esac
        logcmd pkg info -q $i \
            || ask_to_install "$i" "--- Build-time dependency $i not found"
    done
}

#############################################################################
# People that need these should call them explicitly
#############################################################################

run_inbuild() {
    logmsg "Running $*"
    pushd $TMPDIR/$BUILDDIR > /dev/null
    logcmd "$@" || logerr "Failed to run $*"
    popd > /dev/null
}

run_autoheader() { run_inbuild autoheader "$@"; }
run_autoreconf() { run_inbuild autoreconf "$@"; }
run_autoconf() { run_inbuild autoconf "$@"; }
run_automake() { run_inbuild automake "$@"; }
run_aclocal() { run_inbuild aclocal "$@"; }

#############################################################################
# Stuff that needs to be done/set before we start building
#############################################################################

prep_build() {
    typeset style=${1:-autoconf}; shift

    for flag in "$@"; do
        case $flag in
            -oot)
                OUT_OF_TREE_BUILD=1
                ;;
            -keep)
                DONT_REMOVE_INSTALL_DIR=1
                ;;
            -autoreconf)
                [ $style = autoconf ] \
                    || logerr "-autoreconf is only valid for autoconf builds"
                RUN_AUTORECONF=1
                ;;
            -*)
                logerr "Unknown prep_build flag - $flag"
                ;;
        esac
    done

    logmsg "Preparing for $style build"

    # Get the current date/time for the package timestamp
    DATETIME=`TZ=UTC /usr/bin/date +"%Y%m%dT%H%M%SZ"`

    logmsg "--- Creating temporary install dir"
    # We might need to encode some special chars
    PKGE=$(url_encode $PKG)
    # For DESTDIR the '%' can cause problems for some install scripts
    PKGD=${PKGE//%/_}
    DESTDIR=$DTMPDIR/${PKGD}_pkg
    if [ -z "$DONT_REMOVE_INSTALL_DIR" ]; then
        logcmd chmod -R u+w $DESTDIR > /dev/null 2>&1
        logcmd rm -rf $DESTDIR || \
            logerr "Failed to remove old temporary install dir"
        logcmd mkdir -p $DESTDIR || \
            logerr "Failed to create temporary install dir"
    fi

    [ -n "$OUT_OF_TREE_BUILD" ] \
        && CONFIGURE_CMD=$TMPDIR/$BUILDDIR/$CONFIGURE_CMD

    case "$style" in
        cmake)
            OUT_OF_TREE_BUILD=1
            MULTI_BUILD=1
            CONFIGURE_CMD="$CMAKE $TMPDIR/$BUILDDIR"
            ;;
        meson)
            OUT_OF_TREE_BUILD=1
            MULTI_BUILD=1
            MAKE="$NINJA"
            TESTSUITE_MAKE="$NINJA"
            MAKE_TESTSUITE_ARGS=
            CONFIGURE_CMD="$PYTHONLIB/python$PYTHONVER/bin/meson setup"
            CONFIGURE_CMD+=" $TMPDIR/$BUILDDIR"
            ;;
    esac

    if [ -n "$OUT_OF_TREE_BUILD" ]; then
        logmsg "-- Setting up for out-of-tree build"
        BUILDDIR+=-build
        [ -d $TMPDIR/$BUILDDIR ] && logcmd rm -rf $TMPDIR/$BUILDDIR
        logcmd mkdir -p $TMPDIR/$BUILDDIR
    fi

    # Create symbolic links to build area
    [ -h $TMPDIR/build ] && rm -f $TMPDIR/build
    logcmd ln -sf $BUILDDIR $TMPDIR/build
    # ... and to DESTDIR
    [ -h $TMPDIR/pkg ] && rm -f $TMPDIR/pkg
    logcmd ln -sf ${DESTDIR##*/} $TMPDIR/pkg
}

#############################################################################
# Applies patches contained in $PATCHDIR (default patches/)
#############################################################################

check_for_patches() {
    if [ -z "$1" ]; then
        logmsg "Checking for patches in $PATCHDIR/"
    else
        logmsg "Checking for patches in $PATCHDIR/ ($1)"
    fi
    if [ ! -d "$SRCDIR/$PATCHDIR" ]; then
        logmsg "--- No patches directory found"
        return 1
    fi
    if [ ! -f "$SRCDIR/$PATCHDIR/series" ]; then
        logmsg "--- No series file (list of patches) found"
        return 1
    fi
    return 0
}

patch_file() {
    local FILENAME=$1
    shift
    ARGS=$@
    if [ ! -f $SRCDIR/$PATCHDIR/$FILENAME ]; then
        logmsg "--- Patch file $FILENAME not found. Skipping patch."
        return
    fi
    # Note - if -p is specified more than once, then the last one takes
    # precedence, so we can specify -p1 at the beginning to default to -p1.
    # -t - don't ask questions
    # -N - don't try to apply a reverse patch
    if ! logcmd $PATCH -p1 -t -N $ARGS < $SRCDIR/$PATCHDIR/$FILENAME; then
        logerr "--- Patch $FILENAME failed"
    else
        logmsg "--- Applied patch $FILENAME"
    fi
}

apply_patches() {
    if ! check_for_patches "in order to apply them"; then
        logmsg "--- Not applying any patches"
    else
        logmsg "Applying patches"
        # Read the series file for patch filenames
        exec 3<"$SRCDIR/$PATCHDIR/series" # Open the series file with handle 3
        pushd $TMPDIR/$BUILDDIR > /dev/null
        while read LINE <&3 ; do
            [[ $LINE = \#* ]] && continue
            # Split Line into filename+args
            patch_file $LINE
        done
        popd > /dev/null
        exec 3<&- # Close the file
    fi
}

rebase_patches() {
    if ! check_for_patches "in order to re-base them"; then
        logerr "--- No patches to re-base"
        return
    fi

    logmsg "Re-basing patches"
    # Read the series file for patch filenames
    exec 3<"$SRCDIR/$PATCHDIR/series"
    pushd $TMPDIR > /dev/null
    rsync -ac --delete $BUILDDIR/ $BUILDDIR.unpatched/
    while read LINE <&3 ; do
        [[ $LINE = \#* ]] && continue
        patchfile="$SRCDIR/$PATCHDIR/`echo $LINE | awk '{print $1}'`"
        rsync -ac --delete $BUILDDIR/ $BUILDDIR~/
        (
            cd $BUILDDIR
            patch_file $LINE
        )
        mv $patchfile $patchfile~
        # Extract the original patch header text
        sed -n '
            /^---/q
            /^diff -/q
            p
            ' < $patchfile~ > $patchfile
        # Generate new patch and normalise the header lines so that they do
        # not change with each run.
        gdiff -wpruN --exclude='*.orig' $BUILDDIR~ $BUILDDIR | sed '
            /^diff -wpruN/,/^\+\+\+ / {
                s% [^ ~/]*\(~*\)/% a\1/%g
                s%[0-9][0-9][0-9][0-9]-[0-9].*%1970-01-01 00:00:00%
            }
        ' >> $patchfile
        rm -f $patchfile~
    done
    rsync -ac --delete $BUILDDIR.unpatched/ $BUILDDIR/
    popd > /dev/null
    exec 3<&- # Close the file
    # Now the patches have been re-based, -pX is no longer required.
    sed -i 's/ -p.*//' "$SRCDIR/$PATCHDIR/series"
}

patch_source() {
    [ -n "$REBASE_PATCHES" ] && rebase_patches
    apply_patches
    [ $EXTRACT_MODE -ge 1 ] && exit 0
}

#############################################################################
# Attempt to download the given resource to the current directory.
#############################################################################
# Parameters
#   $1 - resource to get
#
get_resource() {
    local RESOURCE=$1
    case ${MIRROR:0:1} in
        /)
            logcmd cp $MIRROR/$RESOURCE .
            ;;
        *)
            URLPREFIX=$MIRROR
            $WGET -a $LOGFILE $URLPREFIX/$RESOURCE
            ;;
    esac
}

set_checksum() {
    typeset alg="$1"
    typeset sum="$2"

    if [ "$alg" = "none" ]; then
        SKIP_CHECKSUM=1
        return
    fi

    digest -l | $EGREP -s "^$alg$" || logerr "Unknown checksum algorithm $alg"

    CHECKSUM_VALUE="$alg:$sum"
}

verify_checksum() {
    typeset found=0

    logmsg "Verifying checksum of downloaded file."

    if [[ "$CHECKSUM_VALUE" = *:* ]]; then
        alg=${CHECKSUM_VALUE%:*}
        sum=${CHECKSUM_VALUE#*:}
        found=1
    else
        for alg in sha512 sha384 sha256; do
            [ -f "$FILENAME.$alg" ] || get_resource $DLDIR/$FILENAME.$alg
            [ -f "$FILENAME.$alg" ] || continue

            sum=`awk '{print $1}' "$FILENAME.$alg"`
            found=1
            break
        done
    fi

    if [ $found -eq 1 ]; then
        typeset filesum=`digest -a $alg $FILENAME`
        if [ "$sum" = "$filesum" ]; then
            logmsg "Checksum verified using $alg"
        else
            logerr "Checksum of downloaded file does not match."
        fi
    else
        logerr "Could not find checksum for download"
    fi
}

#############################################################################
# Download source tarball if needed and extract it
#############################################################################
# Parameters
#   $1 - directory name on the server
#   $2 - program name
#   $3 - program version
#   $4 - target directory
#   $5 - passed to extract_archive
#
# E.g.
#       download_source myprog myprog 1.2.3 will try:
#       http://mirrors.omnios.org/myprog/myprog-1.2.3.tar.gz
download_source() {
    local DLDIR="$1"; shift
    local PROG="$1"; shift
    local VER="$1"; shift
    local TARGETDIR="$1"; shift
    local EXTRACTARGS="$@"
    local FILENAME

    local ARCHIVEPREFIX="$PROG"
    [ -n "$VER" ] && ARCHIVEPREFIX+="-$VER"
    [ -z "$TARGETDIR" ] && TARGETDIR="$TMPDIR"

    # Create TARGETDIR if it doesn't exist
    if [ ! -d "$TARGETDIR" ]; then
        logmsg "Creating target directory $TARGETDIR"
        logcmd mkdir -p $TARGETDIR
    fi

    pushd $TARGETDIR >/dev/null

    logmsg "Checking for source directory"
    if [ -d "$BUILDDIR" ]; then
        logmsg "--- Source directory found, removing"
        logcmd rm -rf "$BUILDDIR" || logerr "Failed to remove source directory"
    else
        logmsg "--- Source directory not found"
    fi

    logmsg "Checking for $PROG source archive"
    find_archive $ARCHIVEPREFIX FILENAME
    if [ -z "$FILENAME" ]; then
        logmsg "--- Archive not found."
        logmsg "Downloading archive"
        for ext in $ARCHIVE_TYPES; do
            get_resource $DLDIR/$ARCHIVEPREFIX.$ext && break
        done
        find_archive $ARCHIVEPREFIX FILENAME
        [ -z "$FILENAME" ] && logerr "Unable to find downloaded file."
        logmsg "--- Downloaded $FILENAME"
    else
        logmsg "--- Found $FILENAME"
    fi
    _ARC_SOURCE+="${_ARC_SOURCE:+ }$SRCMIRROR/$DLDIR/$FILENAME"

    # Fetch and verify the archive checksum
    [ -z "$SKIP_CHECKSUM" ] && verify_checksum

    # Extract the archive
    logmsg "Extracting archive: $FILENAME"
    logcmd extract_archive $FILENAME $EXTRACTARGS \
        || logerr "--- Unable to extract archive."

    # Make sure the archive actually extracted some source where we expect
    if [ ! -d "$BUILDDIR" ]; then
        logerr "--- Extracted source is not in the expected location" \
            " ($BUILDDIR)"
    fi

    CLEAN_SOURCE=1

    popd >/dev/null

    [ $EXTRACT_MODE -eq 1 ] && exit 0
}

# Finds an existing archive and stores its value in a variable whose name
#   is passed as a second parameter
# Example: find_archive myprog-1.2.3 FILENAME
#   Stores myprog-1.2.3.tar.gz in $FILENAME
find_archive() {
    local base="$1"
    local var="$2"
    local ext
    for ext in $ARCHIVE_TYPES; do
        [ -f "$base.$ext" ] || continue
        eval "$var=\"$base.$ext\""
        break
    done
}

# Extracts various types of archive
extract_archive() {
    local file="$1"; shift
    case $file in
        *.tar.zst)          $ZSTD -dc $file | $TAR -xvf - $* ;;
        *.tar.xz)           $XZCAT $file | $TAR -xvf - $* ;;
        *.tar.bz2)          $BUNZIP2 -dc $file | $TAR -xvf - $* ;;
        *.tar.gz|*.tgz)     $GZIP -dc $file | $TAR -xvf - $* ;;
        *.zip)              $UNZIP $file $* ;;
        *.tar)              $TAR -xvf $file $* ;;
        # May as well try tar. It's GNU tar which does a fair job at detecting
        # the compression format.
        *)                  $TAR -xvf $file $* ;;
    esac
}

set_mirror() {
    MIRROR="$@"
    SRCMIRROR="$@"
}

#############################################################################
# Export source from github or local clone
#############################################################################

clone_github_source() {
    typeset prog="$1"
    typeset src="$2"
    typeset branch="$3"
    typeset local="$4"
    typeset depth="${5:-1}"
    typeset fresh=0

    logmsg "$prog -> $TMPDIR/$BUILDDIR/$prog"
    [ -d $TMPDIR/$BUILDDIR ] || logcmd mkdir -p $TMPDIR/$BUILDDIR
    pushd $TMPDIR/$BUILDDIR > /dev/null

    if [ -n "$local" -a -d "$local" ]; then
        logmsg "-- syncing $prog from local clone"
        logcmd rsync -ar $local/ $prog/ || logerr "rsync failed."
        logcmd $GIT -C $prog clean -fdx
        fresh=1
    elif [ ! -d $prog ]; then
        logcmd $GIT clone --no-single-branch --depth $depth $src $prog \
            || logerr "clone failed"
        fresh=1
    else
        logmsg "Using existing checkout"
    fi
    if [ -n "$branch" ]; then
        if ! logcmd $GIT -C $prog checkout $branch; then
            typeset _branch=$branch
            branch="`$GIT -C $prog rev-parse --abbrev-ref HEAD`"
            logmsg "No $_branch branch, using $branch."
        fi
    fi
    if [ "$fresh" -eq 0 ]; then
        if [ -n "$branch" ]; then
            logcmd $GIT -C $prog reset --hard $branch \
                || logerr "failed to reset branch"
            logcmd $GIT -C $prog pull --rebase origin $branch \
                || logerr "failed to pull"
        fi
        logcmd $GIT -C $prog clean -fdx
    fi

    $GIT -C $prog --no-pager show --shortstat

    _ARC_SOURCE+="${_ARC_SOURCE:+ }$src/tree/$branch"

    popd > /dev/null
}

#############################################################################
# Get go source from github
#############################################################################

clone_go_source() {
    typeset prog="$1"
    typeset src="$2"
    typeset branch="$3"
    typeset deps="${4-_deps}"

    clone_github_source $prog "$GITHUB/$src/$prog" $branch

    BUILDDIR+=/$prog

    pushd $TMPDIR/$BUILDDIR > /dev/null

    [ -z "$GOPATH" ] && GOPATH="$TMPDIR/$BUILDDIR/$deps"
    export GOPATH

    logmsg "Getting go dependencies"
    logcmd go get -d ./... || logerr "failed to get dependencies"

    logmsg "Fixing permissions on dependencies"
    logcmd chmod -R u+w $GOPATH

    popd > /dev/null
}

#############################################################################
# Make the package
#############################################################################

run_pkglint() {
    typeset repo="$1"
    typeset mf="$2"

    typeset _repo=
    if [ ! -f $BASE_TMPDIR/lint/pkglintrc ]; then
        logcmd mkdir $BASE_TMPDIR/lint
        (
            cat << EOM
[pkglint]
use_progress_tracker = True
log_level = INFO
do_pub_checks = True
pkglint.exclude = pkg.lint.opensolaris pkg.lint.pkglint_manifest.PkgManifestChecker.naming
version.pattern = *,5.11-0.
pkglint001.5.report-linted = True

EOM
            echo "pkglint.action005.1.missing-deps = \\c"
            for pkg in `nawk '
                $3 == "" {
                    printf("pkg:/%s ", $2)
                }' $ROOTDIR/doc/baseline`; do
                echo "$pkg \\c"
            done
            echo
        ) > $BASE_TMPDIR/lint/pkglintrc
        _repo="-r $repo -r $IPS_REPO -r $OB_IPS_REPO"
    fi
    echo $c_note
    logcmd -p $PKGLINT -f $BASE_TMPDIR/lint/pkglintrc \
        -c $BASE_TMPDIR/lint/cache $mf $_repo \
        || logerr "----- pkglint failed"
    echo $c_reset
}

pkgmeta() {
    typeset key="$1"
    typeset val="$2"

    [[ $key = info.source-url* && ! $val = *://* ]] \
        && val="$SRCMIRROR/$val"
    echo set name=$key value=\"$val\"
}

# Start building a partial manifest
#   manifest_start <filename>
manifest_start() {
    PARTMF="$1"
    SEEDMF=$TMPDIR/manifest.seed
    :>$PARTMF
    generate_manifest $SEEDMF
}

# Add a directory, and the files directly underneath, to a partial manifest.
# Optional arguments indicate sub-directories to recurse one level into.
#   manifest_add_dir <directory> [subdir]...
manifest_add_dir() {
    typeset dir=${1#/}; shift
    logmsg "---- Adding dir '$dir'"
    (
        $RIPGREP "^dir.* path=$dir(\$|\\s)" $SEEDMF
        $RIPGREP "^(file|link|hardlink).* path=$dir/[^/]+(\$|\\s)" $SEEDMF
    ) >> $PARTMF
    for d in "$@"; do
        manifest_add_dir "$dir/$d"
    done
}

# Add a file/link/hardlink to a partial manifest.
#   manifest_add <directory> <pattern> [pattern]...
manifest_add() {
    typeset dir=${1#/}; shift

    for f in "$@"; do
        $RIPGREP "^(file|link|hardlink).* path=$dir/$f(\$|\\s)" $SEEDMF
    done >> $PARTMF
}

# Finalise a partial manifest.
# Takes care of adding any necessary 'dir' actions to support files which
# have been added and sorts the result, removing duplicate lines. Only
# directories under one of the provided prefixes are included
#   manifest_finalise <prefix> [prefix]...
manifest_finalise() {
    typeset tf=`mktemp`
    logcmd cp $PARTMF $tf

    typeset prefix
    for prefix in "$@"; do
        prefix=${prefix#/}
        logmsg "--- determining implicit directories for $prefix"
        $RIPGREP "^dir.* path=$prefix(\$|\\s)" $SEEDMF >> $tf
        $RIPGREP "(file|link|hardlink).* path=$prefix/" $PARTMF \
            | sed "
                s^.*path=$prefix/^^
                s^/[^/]*$^^
        " | sort -u | while read dir; do
            logmsg "---- $dir"
            while :; do
                $RIPGREP "^dir.* path=$prefix/$dir(\$|\\s)" $SEEDMF >> $tf
                [[ $dir = */* ]] || break
                dir=`dirname $dir`
            done
        done
    done
    sort -u < $tf > $PARTMF
    rm -f $tf
}

# Create a manifest file containing all of the lines that are not present
# in the manifests given.
#   manifest_uniq <new manifest> <old manifest> [old manifest]...
manifest_uniq() {
    typeset dst="$1"; shift

    typeset tf=`mktemp`
    typeset mftmp=`mktemp`
    typeset seedtmp=`mktemp`
    sort -u < $SEEDMF > $seedtmp

    for mf in "$@"; do
        sort -u < $mf > $mftmp
        logcmd -p comm -13 $mftmp $seedtmp > $tf
        logcmd mv $tf $seedtmp
    done
    logcmd mv $seedtmp $dst
    rm -f $tf $mftmp
}

generate_manifest() {
    typeset outf="$1"

    [ -n "$DESTDIR" -a -d "$DESTDIR" ] || logerr "DESTDIR does not exist"

    check_symlinks "$DESTDIR"
    if [ -z "$BATCH" ]; then
        [ -z "$SKIP_RTIME_CHECK" ] && check_rtime
        [ -z "$SKIP_SSP_CHECK" ] && check_ssp
    fi
    check_bmi
    logmsg "--- Generating package manifest from $DESTDIR"
    typeset GENERATE_ARGS=
    if [ -n "$HARDLINK_TARGETS" ]; then
        for f in $HARDLINK_TARGETS; do
            GENERATE_ARGS+="--target $f "
        done
    fi
    logcmd -p $PKGSEND generate $GENERATE_ARGS $DESTDIR > $outf \
        || logerr "------ Failed to generate manifest"
}

make_package() {
    logmsg "-- building package $PKG"

    PKGE=`url_encode $PKG`

    typeset seed_manifest=
    typeset -i legacy=0
    while [[ "$1" = -* ]]; do
        case "$1" in
            -seed)  [ -n "$2" -a -f "$2" ] \
                        || logerr "Seed manifest '$2' not found"
                    seed_manifest=$2; shift
                    ;;
            -legacy) legacy=1 ;;
            *)      logerr "Unknown option to make_package - $1" ;;
        esac
        shift
    done

    [ -z "$LOCAL_MOG_FILE" -a -f $SRCDIR/local.mog ] && LOCAL_MOG_FILE=local.mog
    typeset EXTRA_MOG_FILE="$1"
    typeset FINAL_MOG_FILE="$2"
    [[ -n "$LOCAL_MOG_FILE" && ! "$LOCAL_MOG_FILE" = /* ]] \
        && LOCAL_MOG_FILE="$SRCDIR/$LOCAL_MOG_FILE"
    [[ -n "$EXTRA_MOG_FILE" && ! "$EXTRA_MOG_FILE" = /* ]] \
        && EXTRA_MOG_FILE="$SRCDIR/$EXTRA_MOG_FILE"
    [[ -n "$FINAL_MOG_FILE" && ! "$FINAL_MOG_FILE" = /* ]] \
        && FINAL_MOG_FILE="$SRCDIR/$FINAL_MOG_FILE"

    case $BUILDARCH in
        32) BUILDSTR="32bit-" ;;
        64) BUILDSTR="64bit-" ;;
        *) BUILDSTR="" ;;
    esac
    case $FLAVOR in
        ""|default) FLAVORSTR="" ;;
        *) FLAVORSTR="$FLAVOR-" ;;
    esac
    DESCSTR="$DESC"
    [ -n "$FLAVORSTR" ] && DESCSTR="$DESCSTR ($FLAVOR)"
    # Add the local dash-revision if specified.
    PVER=$RELVER.$DASHREV

    # Temporary file paths
    P5M_INT=$TMPDIR/${PKGE}.p5m.int
    P5M_INT2=$TMPDIR/${PKGE}.p5m.int.2
    P5M_INT3=$TMPDIR/${PKGE}.p5m.int.3
    P5M_FINAL=$TMPDIR/${PKGE}.p5m
    MANUAL_DEPS=$TMPDIR/${PKGE}.deps.mog
    GLOBAL_MOG_FILE=$MYDIR/mog/global-transforms.mog
    MY_MOG_FILE=$TMPDIR/${PKGE}.mog

    # Version cleanup

    [ -z "$VERHUMAN" ] && VERHUMAN="$VER"

    local _VER=$VER
    if [[ $VER =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T* ]]; then
        ## Convert ISO-formatted time
        VER=${VER%T*}
        VER=${VER//-/.}
    elif [[ $VER = *[a-z] ]]; then
        ## Convert single trailing alpha character
        VER="${VER:0: -1}.`ord26 ${VER: -1}`"
    fi

    ## Strip leading zeros in version components.
    VER=`echo $VER | sed -e 's/\.0*\([0-9]\)/.\1/g;'`

    [ "$VER" = "$_VER" ] || logmsg "--- Converted version '$_VER'  -> '$VER'"

    if [ -n "$FLAVOR" ]; then
        # We use FLAVOR instead of FLAVORSTR as we don't want the trailing dash
        FMRI="${PKG}-${FLAVOR}@${VER},${SUNOSVER}-${PVER}"
    else
        FMRI="${PKG}@${VER},${SUNOSVER}-${PVER}"
    fi

    if [ -n "$seed_manifest" ]; then
        logcmd cp $seed_manifest $P5M_INT || logerr "seed copy failed"
    elif [ -n "$DESTDIR" ]; then
        generate_manifest $P5M_INT
    else
        logmsg "--- Looks like a meta-package. Creating empty manifest"
        logcmd touch $P5M_INT || \
            logerr "------ Failed to create empty manifest"
    fi
    [ -z "$BATCH" ] && check_libabi "$PKG" "$P5M_INT"

    # Package metadata
    logmsg "--- Generating package metadata"
    if [ "$OVERRIDE_SOURCE_URL" = "none" ]; then
        _ARC_SOURCE=
    elif [ -n "$OVERRIDE_SOURCE_URL" ]; then
        _ARC_SOURCE="$OVERRIDE_SOURCE_URL"
    fi
    (
        pkgmeta pkg.fmri            "$FMRI"
        pkgmeta pkg.summary         "$SUMMARY"
        pkgmeta pkg.description     "$DESCSTR"
        pkgmeta publisher           "$PUBLISHER_EMAIL"
        pkgmeta pkg.human-version   "$VERHUMAN"
        [ $legacy -eq 1 ] \
            && pkgmeta pkg.legacy true
        if [[ $_ARC_SOURCE = *\ * ]]; then
            _asindex=0
            for _as in $_ARC_SOURCE; do
                pkgmeta "info.source-url.$_asindex" "$_as"
                ((_asindex++))
            done
        elif [ -n "$_ARC_SOURCE" ]; then
            pkgmeta info.source-url "$_ARC_SOURCE"
        fi
    ) > $MY_MOG_FILE

    # Transforms
    logmsg "--- Applying transforms"
    logcmd -p $PKGMOGRIFY -I $MYDIR/mog \
        $XFORM_ARGS \
        $P5M_INT \
        $MY_MOG_FILE \
        $GLOBAL_MOG_FILE \
        $LOCAL_MOG_FILE \
        $EXTRA_MOG_FILE \
        $NOTES_MOG_FILE \
        | $PKGFMT -u > $P5M_INT2

    if [ -n "$DESTDIR" ]; then
        check_licences
        [ -z "$SKIP_HARDLINK" -a -z "$BATCH" ] \
            && check_hardlinks "$P5M_INT2" "$HARDLINK_TARGETS"
    fi

    logmsg "--- Resolving dependencies"
    (
        set -e
        logcmd -p $PKGDEPEND generate -md $DESTDIR -d $SRCDIR $P5M_INT2 \
            > $P5M_INT3
        logcmd $PKGDEPEND resolve -m $P5M_INT3
    ) || logerr "--- Dependency resolution failed"
    logmsg "--- Detected dependencies"
    grep '^depend ' $P5M_INT3.res | while read line; do
        logmsg "$line"
    done
    echo > "$MANUAL_DEPS"
    if [ -n "$RUN_DEPENDS_IPS" ]; then
        logmsg "------ Adding manual dependencies"
        for i in $RUN_DEPENDS_IPS; do
            # IPS dependencies have multiple types, of which we care about four:
            #    require, optional, incorporate, exclude
            # For backward compatibility, assume no indicator means type=require
            # FMRI attributes are implicitly rooted so we don't have to prefix
            # 'pkg:/' or worry about ambiguities in names
            local DEPTYPE="require"
            local EXTRA=
            case ${i:0:1} in
                \=)
                    DEPTYPE="incorporate"
                    i=${i:1}
                    shopt -s extglob
                    typeset facet=${i##pkg:+(/)}
                    facet=${facet%@*}
                    EXTRA=" facet.version-lock.$facet=true"
                    ;;
                \?)
                    DEPTYPE="optional"
                    i=${i:1}
                    ;;
                \-)
                    DEPTYPE="exclude"
                    i=${i:1}
                    ;;
            esac
            case $i in
                *@)
                    depname=${i%@}
                    i=${i::-1}
                    explicit_ver=true
                    ;;
                *@*)
                    depname=${i%@*}
                    explicit_ver=true
                    ;;
                *)
                    depname=$i
                    explicit_ver=false
                    ;;
            esac
            # ugly grep, but pkgmogrify doesn't seem to provide any way to add
            # actions while avoiding duplicates (except maybe by running it
            # twice, using drop transform on the first run)
            if grep -q "^depend .*fmri=[^ ]*$depname" "${P5M_INT3}.res"; then
                autoresolved=true
            else
                autoresolved=false
            fi
            if $autoresolved && [ "$DEPTYPE" = "require" ]; then
                if $explicit_ver; then
                    escaped_depname="$(python -c "import re; print re.escape(r'$depname')")"
                    echo "<transform depend fmri=(.+/)?$escaped_depname -> set fmri $i>" >> $MANUAL_DEPS
                fi
            else
                echo "depend type=$DEPTYPE fmri=$i$EXTRA" >> $MANUAL_DEPS
            fi
        done
    fi
    logcmd -p $PKGMOGRIFY $XFORM_ARGS "${P5M_INT3}.res" \
        "$MANUAL_DEPS" $FINAL_MOG_FILE | $PKGFMT -u > $P5M_FINAL
    logmsg "--- Final dependencies"
    grep '^depend ' $P5M_FINAL | while read line; do
        logmsg "$line"
    done

    logmsg "--- Formatting manifest"
    logcmd $PKGFMT -s $P5M_FINAL

    fgrep -q '$(' $P5M_FINAL \
        && logerr "------ Manifest contains unresolved variables"

    if [ -z "$SKIP_PKGLINT" ] && ( [ -n "$BATCH" ] || ask_to_pkglint ); then
        run_pkglint $PKGSRVR $P5M_FINAL
    fi

    logmsg "--- Publishing package to $PKGSRVR"
    if [ -z "$BATCH" ]; then
        logmsg "Intentional pause:" \
            "Last chance to sanity-check before publication!"
        ask_to_continue
    fi
    if [ -n "$DESTDIR" ]; then
        logcmd $PKGSEND -s $PKGSRVR publish -d $DESTDIR \
            -d $TMPDIR/$EXTRACTED_SRC \
            -d $SRCDIR -T \*.py $P5M_FINAL || \
        logerr "------ Failed to publish package"
    else
        # If we're a metapackage (no DESTDIR) then there are no directories
        # to check
        logcmd $PKGSEND -s $PKGSRVR publish $P5M_FINAL || \
            logerr "------ Failed to publish package"
    fi
    logmsg "--- Published $FMRI"

    [ -z "$SKIP_PKG_DIFF" ] && diff_package $FMRI

    return 0
}

translate_manifest()
{
    local src=$1
    local dst=$2

    sed -e "
        s/@PKGPUBLISHER@/$PKGPUBLISHER/g
        s/@RELVER@/$RELVER/g
        s/@PVER@/$PVER/g
        s/@SUNOSVER@/$SUNOSVER/g
        " < $src > $dst
}

publish_manifest()
{
    local pkg=$1
    local pmf=$2
    local root=$3

    [ -n "$root" ] && root="-d $root"

    translate_manifest $pmf $pmf.final

    logmsg "Publishing from $pmf.final"

    if [ -z "$SKIP_PKGLINT" ] && ( [ -n "$BATCH" ] || ask_to_pkglint ); then
        run_pkglint $PKGSRVR $pmf.final
    fi

    logcmd pkgsend -s $PKGSRVR publish $root $pmf.final \
        || logerr "pkgsend failed"
    [ -n "$pkg" -a -z "$SKIP_PKG_DIFF" ] && diff_latest $pkg
}

build_xform_sed()
{
    XFORM_SED_CMD=

    for kv in $XFORM_ARGS; do
        typeset k=${kv%%=*}
        typeset v=${kv#*=}
        typeset _v

        # Escape special characters.
        # If $v contains wildcards like "*", then the following "echo"
        # causes them to get expanded into filenames in the current
        # directory. To avoid this, we temporarily disable globbing ...
        set -o noglob
        _v="`echo $v | sed '
            s/[&$^\\]/\\\&/g
        '`"
        set +o noglob

        XFORM_SED_CMD+="
            s^\$(${k:2})^$_v^g
        "
    done
}

# Transform a file using the translations defined in $XFORM_ARGS
xform() {
    local file="$1"

    [ -n "$XFORM_SED_CMD" ] || build_xform_sed

    sed "$XFORM_SED_CMD" < $file
}

# Create a list of the items contained within a package in a format suitable
# for comparing with previous versions. We don't care about changes in file
# content, just whether items have been added, removed or had their attributes
# such as ownership changed.
pkgitems() {
    pkg contents -m "$@" 2>&1 | pkgfmt -u | sed -E "
        # Remove signatures
        /^signature/d
        # Remove version numbers from the package FMRI
        /name=pkg.fmri/s/@.*//
        /human-version/d
        # Remove version numbers from dependencies
        /^depend/s/@[^ ]+//g
        # Remove file hashes
        s/^file [^ ]+/file/
        s/ chash=[^ ]+//
        s/ elfhash=[^ ]+//
        s/ pkg.content-hash=[^ ]+//g
        # Remove file sizes
        s/ pkg.[c]?size=[0-9]+//g
        # Remove timestamps
        s/ timestamp=[^ ]+//
        $PKGDIFF_HELPER
    "
}

diff_package() {
    local fmri="$1"
    xfmri=${fmri%@*}

    if [ -n "$BATCH" ]; then
        of=$TMPDIR/pkg.diff.$$
        echo "Package: $fmri" > $of
        if ! gdiff -u \
            <(pkgitems -g $IPS_REPO $xfmri) \
            <(pkgitems -g $PKGSRVR $fmri) \
            >> $of; then
                    logmsg -e "----- $fmri has changed"
                    cat $of >> $TMPDIR/pkg.diff
        fi
        rm -f $of
    else
        logmsg "--- Comparing old package with new"
        if ! gdiff -U0 --color=always --minimal \
            <(pkgitems -g $IPS_REPO $xfmri) \
            <(pkgitems -g $PKGSRVR $fmri) \
            > $TMPDIR/pkgdiff.$$; then
                echo
                # Not anchored due to colour codes in file
                $EGREP -v '(\-\-\-|\+\+\+|\@\@) ' $TMPDIR/pkgdiff.$$
                note "Differences found between old and new packages"
                ask_to_continue
        fi
        rm -f $TMPDIR/pkgdiff.$$
    fi
}

diff_latest() {
    typeset fmri="`pkg list -nvHg $PKGSRVR $1 | nawk 'NR==1{print $1}'`"
    logmsg "-- Generating diffs for $fmri"
    diff_package $fmri
}

#############################################################################
# Re-publish packages from one repository to another, changing the publisher
#############################################################################

republish_packages() {
    REPUBLISH_SRC="$1"
    logmsg "Republishing packages from $REPUBLISH_SRC"
    [ -d $TMPDIR/$BUILDDIR ] || mkdir $TMPDIR/$BUILDDIR
    mog=$TMPDIR/$BUILDDIR/pkgpublisher.mog
    cat << EOM > $mog
<transform set name=pkg.fmri -> edit value pkg://[^/]+/ pkg://$PKGPUBLISHER/>
EOM

    incoming=$TMPDIR/$BUILDDIR/incoming
    [ -d $incoming ] && rm -rf $incoming
    mkdir $incoming
    for pkg in `pkgrecv -s $REPUBLISH_SRC -d $incoming --newest`; do
        logmsg "    Receiving $pkg"
        logcmd pkgrecv -s $REPUBLISH_SRC -d $incoming --raw $pkg
    done

    for pdir in $incoming/*/*; do
        logmsg "    Processing $pdir"
        pkgmogrify $pdir/manifest $mog > $pdir/manifest.newpub
        logcmd pkgsend publish -s $PKGSRVR -d $pdir $pdir/manifest.newpub
    done
}

#############################################################################
# Add some release notes
#############################################################################

# Add some release notes that are displayed during installation/upgrade.
# Pass the name of the notes file (relative to files/) as the first argument
# and set the second argument to:
#   0       - display the notes on initial package installation only
#   <ver>   - display the notes when upgrading from before version <ver>
# If the second argument is omitted, it defaults to 0

add_notes() {
    local file="${1:?file}"
    local ver="${2:-0}"

    pushd $DESTDIR > /dev/null
    logmsg "-- Adding notes from $file"
    local tgt=${NOTES_LOCATION#/}
    logcmd mkdir -p $tgt
    logcmd cp $SRCDIR/files/$file $tgt/$PKGD || logerr "Cannot copy to $tgt"
    if [ -z "$NOTES_MOG_FILE" ]; then
        NOTES_MOG_FILE=$TMPDIR/notes.mog
        :>$NOTES_MOG_FILE
    fi
    cat << EOM >> $NOTES_MOG_FILE
<transform file path=$tgt/$PKGD\$ -> set release-note feature/pkg/self@$ver>
<transform file path=$tgt/$PKGD\$ -> set must-display true>
EOM
    popd >/dev/null
}

#############################################################################
# Install an SMF service
#############################################################################

install_smf() {
    typeset methodpath=lib/svc/method
    while [[ "$1" = -* ]]; do
        case "$1" in
            -oocemethod) methodpath+="/ooce" ;;
        esac
        shift
    done

    mtype="${1:?type}"
    manifest="${2:?manifest}"
    method="$3"

    pushd $DESTDIR > /dev/null
    logmsg "-- Installing SMF service ($mtype / $manifest / $method)"

    typeset manifestf; typeset methodf; typeset dir
    for dir in $SRCDIR/files $TMPDIR; do
        [ -f "$dir/$manifest" ] && manifestf="$dir/$manifest"
        [ -f "$dir/$method" ] && methodf="$dir/$method"
    done

    [ -z "$manifestf" ] && logerr "Could not locate $manifest"
    [ -n "$method" -a -z "$methodf" ] && logerr "Could not locate $method"

    logcmd svccfg validate $manifestf \
        || logerr "Manifest does not pass validation"

    # Manifest
    logcmd mkdir -p lib/svc/manifest/$mtype \
        || logerr "mkdir of $DESTDIR/lib/svc/manifest/$mtype failed"
    logcmd cp $manifestf lib/svc/manifest/$mtype/ \
        || logerr "Cannot copy SMF manifest"
    logcmd chmod 0444 lib/svc/manifest/$mtype/$manifest

    # Method
    if [ -n "$method" ]; then
        logcmd mkdir -p $methodpath \
            || logerr "mkdir of $DESTDIR/$methodpath failed"
        logcmd cp $methodf $methodpath/ \
            || logerr "Cannot install SMF method"
        logcmd chmod 0555 $methodpath/$method
    fi

    popd > /dev/null
}

#############################################################################
# Install an /etc/inet/services fragment
#############################################################################

install_inetservices() {
    typeset frag="${1:-services}"

    pushd $DESTDIR > /dev/null
    logmsg "-- Installing /etc/inet/services fragment - $frag"

    [ -f "$SRCDIR/files/$frag" ] || logerr "files/$frag not found"

    logcmd mkdir -p etc/inet/services.d || logerr "mkdir failed"

    logcmd cp $SRCDIR/files/$frag etc/inet/services.d/${PKG//\//:} \
        || logerr "copy failed"

    popd > /dev/null
}

#############################################################################
# Install a go binary
#############################################################################

install_go() {
    typeset src="${1:-$PROG}"
    typeset dst="${2:-$PROG}"
    typeset dstdir="${3:-$DESTDIR/$PREFIX/bin}"

    logcmd mkdir -p $dstdir \
        || logerr "Failed to create install dir"

    logcmd cp $TMPDIR/$BUILDDIR/$src $dstdir/$dst \
        || logerr "Failed to install binary"
}

#############################################################################
# Install a rust binary
#############################################################################

install_rust() {
    logmsg "Installing $PROG"

    logcmd mkdir -p "$DESTDIR/$PREFIX/bin" \
        || logerr "Failed to create install dir"
    logcmd cp $TMPDIR/$BUILDDIR/target/release/$PROG \
        $DESTDIR/$PREFIX/bin/$PROG || logerr "Failed to install binary"

    for f in `$FD "^$PROG\.1\$" $TMPDIR/$BUILDDIR`; do
        logmsg "Found man page at $f"

        logcmd mkdir -p "$DESTDIR/$PREFIX/share/man/man1" \
            || logerr "Failed to create man install dir"
        logcmd cp $f $DESTDIR/$PREFIX/share/man/man1/$PROG.1 \
            || logerr "Failed to install man page"
        break
    done
}

#############################################################################
# Make isaexec stub binaries
#############################################################################

make_isa_stub() {
    [ -n "$FORGO_ISAEXEC" ] \
        && logerr "-- Calling make_isa_stub after forgo_isaexec"
    logmsg "Making isaexec stub binaries"
    [ -z "$ISAEXEC_DIRS" ] && ISAEXEC_DIRS="bin sbin"
    for DIR in $ISAEXEC_DIRS; do
        if [ -d $DESTDIR$PREFIX/$DIR ]; then
            logmsg "--- $DIR"
            pushd $DESTDIR$PREFIX/$DIR > /dev/null
            make_isaexec_stub_arch $ISAPART $PREFIX/$DIR
            make_isaexec_stub_arch $ISAPART64 $PREFIX/$DIR
            popd > /dev/null
        fi
    done
}

make_isaexec_stub_arch() {
    typeset isa="$1"
    typeset dir="$2"

    for file in $isa/*; do
        [ -f "$file" ] || continue
        if [ -z "$STUBLINKS" -a -h "$file" ]; then
            # Symbolic link. If it's relative to within the same ARCH
            # directory, then replicate it at the ISAEXEC level.
            link=`readlink "$file"`
            [[ $link = */* ]] && continue
            base=`basename "$file"`
            [ -h "$base" ] && continue
            logmsg "------ Symbolic link: $file - replicating"
            logcmd ln -s $link $base || logerr "--- Link failed"
            continue
        fi
        # Check to make sure we don't have a script
        read -n 4 < $file
        file=`basename $file`
        # Only copy non-binaries if we set NOSCRIPTSTUB
        if [[ $REPLY != $'\177'ELF && -n "$NOSCRIPTSTUB" ]]; then
            logmsg "------ Non-binary file: $file - copying instead"
            logcmd cp $1/$file . && rm $1/$file || logerr "--- Copy failed"
            chmod +x $file
            continue
        fi
        # Skip if we already made a stub for this file
        [ -f "$file" ] && continue
        logmsg "---- Creating ISA stub for $file"
        logcmd $CC $CFLAGS $CFLAGS32 -o $file \
            -DFALLBACK_PATH="$dir/$file" $MYDIR/isastub.c \
            || logerr "--- Failed to make isaexec stub for $dir/$file"
        logcmd strip -x $file
    done
}

#############################################################################
# Build commands
#############################################################################
# Notes:
#   - These methods are designed to work in the general case.
#   - You can set CFLAGS/LDFLAGS (and CFLAGS32/CFLAGS64 for arch specific flags)
#   - Configure flags are set in CONFIGURE_OPTS_32 and CONFIGURE_OPTS_64 with
#     defaults set in config.sh. You can append to these variables or replace
#     them if the defaults don't work for you.
#   - In the normal case, where you just want to add --enable-feature, set
#     CONFIGURE_OPTS. This will be appended to the end of CONFIGURE_CMD
#     for both 32 and 64 bit builds.
#   - Any of these functions can be overridden in your build script, so if
#     anything here doesn't apply to the build process for your application,
#     just override that function with whatever code you need. The build
#     function itself can be overridden if the build process doesn't fit into a
#     configure, make, make install pattern.
#############################################################################

make_clean() {
    if [ -n "$CLEAN_SOURCE" ]; then
        CLEAN_SOURCE=
        return
    fi
    logmsg "--- make (dist)clean"
    (
        $MAKE distclean || $MAKE clean
    ) 2>&1 | sed 's/error: /errorclean: /' | pipelog >/dev/null
}

configure_autoreconf() {
    [ -f configure -a -f configure.ac ] \
        && [ ! configure.ac -nt configure ] && return
    run_autoreconf -fi
}

configure32() {
    logmsg "--- configure (32-bit)"
    eval set -- $CONFIGURE_OPTS_WS_32 $CONFIGURE_OPTS_WS
    [ -n "$RUN_AUTORECONF" ] && configure_autoreconf
    PCPATH=
    [ -n "$PKG_CONFIG_PATH" ] && addpath PCPATH "$PKG_CONFIG_PATH"
    [ -n "$PKG_CONFIG_PATH32" ] && addpath PCPATH "$PKG_CONFIG_PATH32"
    CFLAGS="$CFLAGS $CFLAGS32" \
        CXXFLAGS="$CXXFLAGS $CXXFLAGS32" \
        CPPFLAGS="$CPPFLAGS $CPPFLAGS32" \
        LDFLAGS="$LDFLAGS $LDFLAGS32" \
        PKG_CONFIG_PATH="$PCPATH" \
        CC="$CC" CXX="$CXX" \
        logcmd $CONFIGURE_CMD $CONFIGURE_OPTS_32 \
        $CONFIGURE_OPTS "$@" || \
        logerr "--- Configure failed"
}

configure64() {
    logmsg "--- configure (64-bit)"
    eval set -- $CONFIGURE_OPTS_WS_64 $CONFIGURE_OPTS_WS
    [ -n "$RUN_AUTORECONF" ] && configure_autoreconf
    PCPATH=
    [ -n "$PKG_CONFIG_PATH" ] && addpath PCPATH "$PKG_CONFIG_PATH"
    [ -n "$PKG_CONFIG_PATH64" ] && addpath PCPATH "$PKG_CONFIG_PATH64"
    CFLAGS="$CFLAGS $CFLAGS64" \
        CXXFLAGS="$CXXFLAGS $CXXFLAGS64" \
        CPPFLAGS="$CPPFLAGS $CPPFLAGS64" \
        LDFLAGS="$LDFLAGS $LDFLAGS64" \
        PKG_CONFIG_PATH="$PCPATH" \
        CC="$CC" CXX="$CXX" \
        logcmd $CONFIGURE_CMD $CONFIGURE_OPTS_64 \
        $CONFIGURE_OPTS "$@" || \
        logerr "--- Configure failed"
}

make_prog() {
    eval set -- $MAKE_ARGS_WS
    [ -n "$NO_PARALLEL_MAKE" ] && MAKE_JOBS=""
    if [ -n "$LIBTOOL_NOSTDLIB" ]; then
        libtool_nostdlib "$LIBTOOL_NOSTDLIB" "$LIBTOOL_NOSTDLIB_EXTRAS"
    fi
    logmsg "--- make"
    logcmd $MAKE $MAKE_JOBS $MAKE_ARGS "$@" $MAKE_TARGET \
        || logerr "--- Make failed"
}

make_prog32() {
    make_prog
}

make_prog64() {
    make_prog
}

make_install() {
    local args="$@"
    eval set -- $MAKE_INSTALL_ARGS_WS
    logmsg "--- make install"
    if [ "${MAKE##*/}" = "ninja" ]; then
        DESTDIR=${DESTDIR} logcmd $MAKE $args $MAKE_INSTALL_ARGS "$@" \
            $MAKE_INSTALL_TARGET || logerr "--- Make install failed"
    else
        logcmd $MAKE DESTDIR=${DESTDIR} $args $MAKE_INSTALL_ARGS "$@" \
            $MAKE_INSTALL_TARGET || logerr "--- Make install failed"
    fi
}

make_install32() {
    make_install $MAKE_INSTALL_ARGS_32
}

make_install64() {
    make_install $MAKE_INSTALL_ARGS_64
}

make_pure_install() {
    # Make pure_install for perl modules so they don't touch perllocal.pod
    logmsg "--- make install (pure)"
    logcmd $MAKE DESTDIR=${DESTDIR} pure_install || \
        logerr "--- Make pure_install failed"
}

make_param() {
    logmsg "--- make $@"
    logcmd $MAKE "$@" || \
        logerr "--- $MAKE $1 failed"
}

# Helper function that can be called by build scripts to make in a specific dir
make_in() {
    [ -z "$1" ] && logerr "------ Make in dir failed - no dir specified"
    [ -n "$NO_PARALLEL_MAKE" ] && MAKE_JOBS=""
    logmsg "------ make in $1"
    logcmd $MAKE $MAKE_JOBS -C $1 $MAKE_TARGET || \
        logerr "------ Make in $1 failed"
}

# Helper function that can be called by build scripts to install in a specific
# dir
make_install_in() {
    [ -z "$1" ] && logerr "--- Make install in dir failed - no dir specified"
    logmsg "------ make install in $1"
    logcmd $MAKE -C $1 DESTDIR=${DESTDIR} $MAKE_INSTALL_TARGET || \
        logerr "------ Make install in $1 failed"
}

build() {
    local ctf=${CTF_DEFAULT:-0}

    while [[ "$1" = -* ]]; do
        case "$1" in
            -ctf)   ctf=1 ;;
            -noctf) ctf=0 ;;
            -multi) MULTI_BUILD=1 ;;
        esac
        shift
    done

    [ $ctf -eq 1 ] && CFLAGS+=" $CTF_CFLAGS"

    [ -n "$MULTI_BUILD" ] && logmsg "--- Using multiple build directories"
    typeset _BUILDDIR=$BUILDDIR
    for b in $BUILDORDER; do
        if [[ $BUILDARCH =~ ^($b|both)$ ]]; then
            if [ -n "$MULTI_BUILD" ]; then
                BUILDDIR+="/build.$b"
                mkdir -p $TMPDIR/$BUILDDIR
                MULTI_BUILD_LAST=$BUILDDIR
            fi
            build$b
            BUILDDIR=$_BUILDDIR
        fi
    done

    [ $ctf -eq 1 ] && convert_ctf
}

check_buildlog() {
    typeset -i expected="${1:-0}"

    logmsg "--- Checking logfile for errors (expect $expected)"

    errs="`grep 'error: ' $LOGFILE | \
        $EGREP -cv 'pathspec.*did not match any file'`"

    [ "$errs" -ne "$expected" ] \
        && logerr "Found $errs errors in logfile (expected $expected)"
}

build32() {
    pushd $TMPDIR/$BUILDDIR > /dev/null
    logmsg "Building 32-bit"
    export ISALIST="$ISAPART"
    make_clean
    configure32
    make_prog32
    [ -z "$SKIP_BUILD_ERRCHK" ] && check_buildlog ${EXPECTED_BUILD_ERRS:-0}
    make_install32
    popd > /dev/null
    unset ISALIST
    export ISALIST
}

build64() {
    pushd $TMPDIR/$BUILDDIR > /dev/null
    logmsg "Building 64-bit"
    make_clean
    configure64
    make_prog64
    [ -z "$SKIP_BUILD_ERRCHK" ] && check_buildlog ${EXPECTED_BUILD_ERRS:-0}
    make_install64
    popd > /dev/null
}

run_testsuite() {
    local target="${1:-test}"
    local dir="$2"
    local output="${3:-testsuite.log}"
    if [ -z "$SKIP_TESTSUITE" ] && ( [ -n "$BATCH" ] || ask_to_testsuite ); then
        if [ -z "$MULTI_BUILD" ]; then
            pushd $TMPDIR/$BUILDDIR/$dir > /dev/null
        else
            pushd $TMPDIR/$MULTI_BUILD_LAST/$dir > /dev/null
        fi
        logmsg "Running testsuite"
        op=`mktemp`
        eval set -- $MAKE_TESTSUITE_ARGS_WS
        $TESTSUITE_MAKE $target $MAKE_TESTSUITE_ARGS "$@" 2>&1 | tee $op
        if [ -n "$TESTSUITE_SED" ]; then
            sed "$TESTSUITE_SED" $op > $SRCDIR/$output
        elif [ -n "$TESTSUITE_FILTER" ]; then
            $EGREP "$TESTSUITE_FILTER" $op > $SRCDIR/$output
        else
            cp $op $SRCDIR/$output
        fi
        rm -f $op
        popd > /dev/null
    fi
}

#############################################################################
# Build function for dependencies which are not packaged
#############################################################################

build_dependency() {
    typeset merge=0
    typeset buildargs=
    while [[ "$1" = -* ]]; do
        case $1 in
            -merge)     merge=1 ;;
            -ctf)       buildargs+=" -ctf" ;;
            -noctf)     buildargs+=" -noctf" ;;
        esac
        shift
    done
    typeset dep="$1"
    typeset dir="$2"
    typeset dldir="$3"
    typeset prog="$4"
    typeset ver="$5"

    # Preserve the current variables
    typeset _BUILDDIR=$BUILDDIR
    typeset _PATCHDIR=$PATCHDIR
    typeset _DESTDIR=$DESTDIR

    # Adjust variables so that download, patch and build work correctly
    BUILDDIR="$dir"
    PATCHDIR="patches-$dep"
    [ ! -d "$PATCHDIR" -a -d "patches-$ver" ] && PATCHDIR="patches-$ver"
    if [ $merge -eq 0 ]; then
        DEPROOT=$TMPDIR/_deproot
        DESTDIR=$DEPROOT
        mkdir -p $DEPROOT
    else
        DEPROOT=$DESTDIR
    fi

    note -n "-- Building dependency $dep"
    download_source "$dldir" "$prog" "$ver" "$TMPDIR"
    patch_source
    build $buildargs

    # Restore variables
    BUILDDIR=$_BUILDDIR
    PATCHDIR=$_PATCHDIR
    DESTDIR=$_DESTDIR
}

#############################################################################
# Build function for python programs
#############################################################################

set_python_version() {
    PYTHONVER=$1
    PYTHONPKGVER=${PYTHONVER//./}
    PYTHONPATH=/usr
    PYTHON=$PYTHONPATH/bin/python$PYTHONVER
    PYTHONLIB=$PYTHONPATH/lib
    PYTHONVENDOR=$PYTHONLIB/python$PYTHONVER/vendor-packages
}
set_python_version $DEFAULT_PYTHON_VER

pre_python_32() {
    logmsg "prepping 32bit python build"
}

pre_python_64() {
    logmsg "prepping 64bit python build"
}

python_path_fixup() {
    pushd $DESTDIR/$PREFIX/bin >/dev/null || return
    for f in *; do
        [ -f "$f" ] || continue
        file "$f" | $EGREP -s 'executable.*python.*script' || continue
        logmsg "Fixing python library path in $f"
        sed -i "1a\\
import sys; sys.path.insert(1, '$PREFIX/lib/python$PYTHONVER/vendor-packages')
        " "$f"
    done
    popd >/dev/null
}

python_vendor_relocate() {
    pushd $DESTDIR/$PREFIX/lib >/dev/null || logerr "python relocate pushd"
    [ -d python$PYTHONVER/site-packages ] || return
    logmsg "Relocating python $PYTHONVER site to vendor-packages"
    if [ -d python$PYTHONVER/vendor-packages ]; then
        rsync -a python$PYTHONVER/site-packages/ \
            python$PYTHONVER/vendor-packages/ \
            || logerr "python: cannot copy from site to vendor-packages"
        rm -rf python$PYTHONVER/site-packages \
            || logerr "python: cannot remove site-packages directory"
    else
        mv python$PYTHONVER/site-packages/ python$PYTHONVER/vendor-packages/ \
            || logerr "python: cannot move from site to vendor-packages"
    fi
    popd >/dev/null
}

python_compile() {
    logmsg "Compiling python modules"
    logcmd $PYTHON -m compileall $DESTDIR
}

python_build32() {
    ISALIST=i386
    export ISALIST
    pre_python_32
    logmsg "--- setup.py (32) build"
    CFLAGS="$CFLAGS $CFLAGS32" LDFLAGS="$LDFLAGS $LDFLAGS32" \
        logcmd $PYTHON ./setup.py build $PYBUILD32OPTS \
        || logerr "--- build failed"
    logmsg "--- setup.py (32) install"
    logcmd $PYTHON ./setup.py install \
        --root=$DESTDIR --prefix=$PREFIX $PYINST32OPTS \
        || logerr "--- install failed"
}

python_build64() {
    ISALIST="amd64 i386"
    export ISALIST
    pre_python_64
    logmsg "--- setup.py (64) build"
    CFLAGS="$CFLAGS $CFLAGS64" LDFLAGS="$LDFLAGS $LDFLAGS64" \
        logcmd $PYTHON ./setup.py build $PYBUILD64OPTS \
        || logerr "--- build failed"
    logmsg "--- setup.py (64) install"
    logcmd $PYTHON ./setup.py install \
        --root=$DESTDIR --prefix=$PREFIX $PYINST64OPTS \
        || logerr "--- install failed"
}

python_build() {
    [ -z "$PYTHON" ] && logerr "PYTHON not set"
    [ -z "$PYTHONPATH" ] && logerr "PYTHONPATH not set"
    [ -z "$PYTHONLIB" ] && logerr "PYTHONLIB not set"

    logmsg "Building using python setup.py"

    pushd $TMPDIR/$BUILDDIR > /dev/null

    # we only ship 64 bit python3
    [[ $PYTHONVER = 3.* ]] && BUILDARCH=64

    for b in $BUILDORDER; do
        [[ $BUILDARCH =~ ^($b|both)$ ]] && python_build$b
    done

    popd > /dev/null

    python_vendor_relocate
    python_path_fixup
    python_compile
}

#############################################################################
# Build function for rust utils
#############################################################################

build_rust() {
    logmsg "Building 64-bit"

    pushd $TMPDIR/$BUILDDIR >/dev/null

    logcmd $CARGO build --release $@ || logerr "build failed"

    popd >/dev/null
}

#############################################################################
# Build/test function for perl modules
#############################################################################
# Detects whether to use Build.PL or Makefile.PL
# Note: Build.PL probably needs Module::Build installed
#############################################################################

siteperl_to_vendor() {
    logcmd mv $DESTDIR/$PREFIX/perl5/site_perl \
        $DESTDIR/$PREFIX/perl5/vendor_perl \
        || logerr "can't move to vendor_perl"
}

buildperl() {
    if [ -f "$SRCDIR/${PROG}-${VER}.env" ]; then
        logmsg "Sourcing environment file: $SRCDIR/${PROG}-${VER}.env"
        source $SRCDIR/${PROG}-${VER}.env
    fi
    pushd $TMPDIR/$BUILDDIR > /dev/null
    logmsg "Building 64-bit"
    if [ -f Makefile.PL ]; then
        make_clean
        makefilepl $PERL_MAKEFILE_OPTS
        make_prog
        [ -n "$PERL_MAKE_TEST" ] && make_param test
        make_pure_install
    elif [ -f Build.PL ]; then
        build_clean
        buildpl $PERL_MAKEFILE_OPTS
        build_prog
        [ -n "$PERL_MAKE_TEST" ] && build_test
        build_install
    fi
    popd > /dev/null
}

makefilepl() {
    logmsg "--- Makefile.PL 64-bit"
    logcmd $PERL Makefile.PL $@ || logerr "Failed to run Makefile.PL"
}

buildpl() {
    logmsg "--- Build.PL 64-bit"
    logcmd $PERL Build.PL prefix=$PREFIX $@ ||
        logerr "Failed to run Build.PL"
}

build_clean() {
    if [ -n "$CLEAN_SOURCE" ]; then
        CLEAN_SOURCE=
        return
    fi
    logmsg "--- Build (dist)clean"
    logcmd ./Build distclean || \
    logcmd ./Build clean || \
        logmsg "--- *** WARNING *** make (dist)clean Failed"
}

build_prog() {
    logmsg "--- Build"
    logcmd ./Build ||
        logerr "Build failed"
}

build_test() {
    logmsg "--- Build test"
    logcmd ./Build test ||
        logerr "Build test failed"
}

build_install() {
    logmsg "--- Build install"
    logcmd ./Build pure_install --destdir=$DESTDIR || \
        logmsg "Build install failed"
}

test_if_core() {
    logmsg "Testing whether $MODNAME is in core"
    logmsg "--- Ensuring ${PKG} is not installed"
    if logcmd pkg info -q ${PKG}; then
        logerr "------ Package ${PKG} appears to be installed.  Please uninstall it."
    else
        logmsg "------ Not installed, good."
    fi
    if logcmd $PERL -M$MODNAME -e '1'; then
        # Module is in core, don't create a package
        logmsg "--- Module is in core for Perl $DEPVER.  Not creating a package."
        exit 0
    else
        logmsg "--- Module is not in core for Perl $DEPVER.  Continuing with build."
    fi
}

#############################################################################
# Check for dangling symlinks
#############################################################################

check_symlinks() {
    logmsg "-- Checking for dangling symlinks"
    for link in `find "$1" -type l`; do
        readlink -e $link >/dev/null || logerr "Dangling symlink $link"
    done
}

#############################################################################
# Add a component to a path
#############################################################################

addpath() {
    declare -n var=$1
    typeset val="$2"

    var+="${var:+:}$val"
}

#############################################################################
# Check that hardlinks are anchored for reproducible package builds
#############################################################################

check_hardlinks() {
    typeset manifest="$1"; shift
    typeset targets="$@"
    typeset -A tlookup

    logmsg "-- Checking hardlinks"

    for t in $targets; do
        t="`$REALPATH \"$DESTDIR/$t\"`"
        tlookup[$t]=1
    done

    hlf=`mktemp`

    nawk '$1 == "hardlink" {
            path = ""
            for (i = 0; i <= NF; i++) {
                split($i, a, "=")
                key = a[1]; val = a[2]
                if (key == "path") {
                    dir = path = val
                    sub(/\/[^\/]*$/, "/", dir)
                }
                if (key == "target") {
                    if (val ~ /^\//)
                        print val, path
                    else
                        printf("%s%s %s\n", dir, val, path)
                }
            }
        }' < "$manifest" | while read link path; do
            flink="`$REALPATH \"$DESTDIR/$link\"`"
            logmsg "--- checking hardlink $link"
            [ -n "${tlookup[$flink]}" ] || echo "$link <- $path" >> $hlf
    done

    if [ -s $hlf ]; then
        logmsg "---"
        logmsg -e "These hardlinks do not have locked targets,"\
            "resulting in inconsistent builds."
        cat $hlf | while read hl; do
            logmsg -e "--- Unlocked hardlink: $hl"
        done
        logerr "---"
    fi

    rm -f $hlf
}

#############################################################################
# Check for library ABI change
#############################################################################

extract_libabis() {
    declare -Ag "$1"
    local -n array="$1"
    local src="$2"

    while read file; do
        lib=${file%.so.*}
        abi=${file#*.so.}
        array[$lib]+="$abi "
    done < <(sed < "$src" '
        # basename
        s/.*\///
        # Remove minor versions (e.g. .so.7.1.2 -> .so.7)
        s/\(\.so\.[0-9][0-9]*\)\..*/\1/
        ' | sort | uniq)
}

check_libabi() {
    local pkg="$1"
    local mf="$2"

    logmsg "-- Checking for library ABI changes"

    # Build list of libraries and ABIs from this package on disk
    nawk '
        $1 == "file" && $2 ~ /\.so\.[0-9]/ { print $2 }
    ' < $mf > $TMPDIR/libs.$$
    extract_libabis cla__new $TMPDIR/libs.$$
    logcmd rm -f $TMPDIR/libs.$$

    [ ${#cla__new[@]} -gt 0 ] || return

    # The package has at least one library

    logmsg "--- Found libraries, fetching previous package contents"
    pkgitems -g $IPS_REPO $pkg | nawk '
            /^file path=.*\.so\./ {
                sub(/path=/, "", $2)
                print $2
            }
        ' > $TMPDIR/libs.$$
    [ -s $TMPDIR/libs.$$ ] || logerr "Could not retrieve contents"
    # In case the user chooses to continue after the previous error
    [ -s $TMPDIR/libs.$$ ] || return
    extract_libabis cla__prev $TMPDIR/libs.$$
    rm -f $TMPDIR/libs.$$

    # Compare
    typeset change=0
    for k in "${!cla__new[@]}"; do
        [ "${cla__new[$k]}" = "${cla__prev[$k]}" ] && continue
        # The list of ABIs has changed. Make sure that all of the old versions
        # are present in the new.
        logmsg -n "--- $k ABI change, ${cla__prev[$k]} -> ${cla__new[$k]}"
        local prev new flag
        for prev in ${cla__prev[$k]}; do
            flag=0
            for new in ${cla__new[$k]}; do
                [ "$prev" = "$new" ] && flag=1
            done
            [ "$flag" -eq 1 ] && continue
            change=1
            logmsg -e "--- $k.so.$prev missing from new package"
        done
    done
    [ $change -eq 1 ] && logerr "--- old ABI libraries missing"
}

#############################################################################
# ELF operations
#############################################################################

rtime_files() {
    # `find_elf` invokes `elfedit` and expects it to be the illumos one.
    PATH=$USRBIN logcmd -p $FIND_ELF -fr $DESTDIR/ > $TMPDIR/rtime.files
}

rtime_objects() {
    rtime_files
    nawk '/^OBJECT/ { print $NF }' $TMPDIR/rtime.files
}

strip_install() {
    logmsg "Stripping installation"

    pushd $DESTDIR > /dev/null || logerr "Cannot change to $DESTDIR"
    while read file; do
        logmsg "------ stripping $file"
        MODE=$(stat -c %a "$file")
        logcmd chmod u+w "$file" || logerr -b "chmod failed: $file"
        logcmd strip -x "$file" || logerr -b "strip failed: $file"
        logcmd chmod $MODE "$file" || logerr -b "chmod failed: $file"
    done < <(rtime_objects)
    popd > /dev/null
}

convert_ctf() {
    logmsg "Converting DWARF to CTF"

    pushd $DESTDIR > /dev/null || logerr "Cannot change to $DESTDIR"

    local ctftag='---- CTF:'

    while read file; do
        if [ -f $SRCDIR/files/ctf.skip ] \
          && echo $file | $EGREP -qf $SRCDIR/files/ctf.skip; then
            logmsg "$ctftag skipped $file"
            logcmd strip -x "$file"
            continue
        fi

        if $CTFDUMP -h "$file" 1>/dev/null 2>&1; then
            continue
        fi

        typeset mode=`stat -c %a "$file"`
        logcmd chmod u+w "$file" || logerr -b "chmod u+w failed: $file"
        typeset tf="$file.$$"

        typeset flags="$CTF_FLAGS"
        if [ -f $SRCDIR/files/ctf.ignore ]; then
            [ $RELVER -ge 151037 ] && flags+=" -M$SRCDIR/files/ctf.ignore" \
                || flags+=" -m"
        fi
        if logcmd $CTFCONVERT $flags -l "$PROG-$VER" -o "$tf" "$file"; then
            if [ -s "$tf" ]; then
                logcmd cp "$tf" "$file"
                if [ -z "$BATCH" -o -n "$CTF_AUDIT" ]; then
                    logmsg -n "$ctftag $file" \
                        "`$CTFDUMP -S $file | \
                        nawk '/number of functions/{print $6}'` function(s)"
                else
                    logmsg "$ctftag converted $file"
                fi
            else
                logmsg "$ctftag no DWARF data $file"
            fi
        else
            logmsg -e "$ctftag failed $file"
            if [ -n "$CTF_AUDIT" ]; then
                logcmd mkdir -p $BASE_TMPDIR/ctfobj
                typeset f=${file:2}
                logcmd cp $file $BASE_TMPDIR/ctfobj/${f//\//_}
            fi
        fi

        logcmd rm -f "$tf"
        logcmd strip -x "$file"
        logcmd chmod $mode "$file" || logerr -b "chmod failed: $file"
    done < <(rtime_objects)

    popd >/dev/null
}

check_rtime() {
    logmsg "-- Checking ELF runtime attributes"
    rtime_files

    cp $ROOTDIR/doc/rtime $TMPDIR/rtime.cfg
    [ -f $SRCDIR/rtime ] && cat $SRCDIR/rtime >> $TMPDIR/rtime.cfg

    logcmd $CHECK_RTIME \
        -e $TMPDIR/rtime.cfg \
        -E $TMPDIR/rtime.err \
        -f $TMPDIR/rtime.files

    if [ -s "$TMPDIR/rtime.err" ]; then
        cat $TMPDIR/rtime.err | tee -a $LOGFILE
        logerr "ELF runtime problems detected"
    fi
}

check_ssp() {
    logmsg "-- Checking stack smashing protection"

    : > $TMPDIR/rtime.ssp
    while read obj; do
        [ -f "$DESTDIR/$obj" ] || continue
        nm $DESTDIR/$obj | $EGREP -s '__stack_chk_guard' \
            || echo "$obj does not include stack smashing protection" \
            >> $TMPDIR/rtime.ssp &
        parallelise $LCPUS
    done < <(rtime_objects)
    wait
    if [ -s "$TMPDIR/rtime.ssp" ]; then
        cat $TMPDIR/rtime.ssp | tee -a $LOGFILE
        logerr "Found object(s) without SSP"
    fi
}

check_bmi() {
    [ -n "$BMI_EXPECTED" ] && return

    # In the past, some programs have ended up containing BMI instructions
    # that will cause an illegal instruction error on pre-Haswell processors.
    # We explicitly check for this in the elf objects.

    logmsg "-- Checking for BMI instructions"

    : > $TMPDIR/rtime.bmi
    while read obj; do
        [ -f "$DESTDIR/$obj" ] || continue
        dis $DESTDIR/$obj 2>/dev/null \
            | $RIPGREP -wq --no-messages 'mulx|lzcntq|shlx' \
            && echo "$obj has been built with BMI instructions" \
            >> $TMPDIR/rtime.bmi &
        parallelise $LCPUS
    done < <(rtime_objects)
    wait
    if [ -s "$TMPDIR/rtime.bmi" ]; then
        cat $TMPDIR/rtime.bmi | tee -a $LOGFILE
        logerr "BMI instruction set found"
    fi
}

#############################################################################
# Check package licences
#############################################################################

check_licences() {
    typeset -i lics=0
    typeset -a errs
    typeset -i flag
    while read file types; do
        ((lics++))
        logmsg "-- licence '$file' ($types)"

        # Check if the "license" lines point to valid files
        flag=0
        for dir in $DESTDIR $TMPDIR/$EXTRACTED_SRC $SRCDIR; do
            if [ -f "$dir/$file" ]; then
                #logmsg "   found in $dir/$file"
                flag=1
                break
            fi
        done
        if [ $flag -eq 0 ]; then
            errs+=("Licence '$file' not found.")
            continue
        fi

        # Consolidate found licences into a temporary directory
        mkdir -p $BASE_TMPDIR/licences
        typeset lf="$BASE_TMPDIR/licences/$PKGD.`basename $file`"
        dos2unix "$dir/$file" "$lf"
        chmod u+rw "$lf"

        [ -z "$FORCE_LICENCE_CHECK" -a -n "$BATCH" ] && continue

        _IFS="$IFS"; IFS=,
        for type in $types; do
            case "$type" in $SKIP_LICENCES) continue ;; esac

            # Check that the licence type is correct
            pattern="`nawk -F"\t+" -v type="${type%%/*}" '
                /^#/ { next }
                $1 == type { print $2 }
            ' $ROOTDIR/doc/licences`"
            if [ -z "$pattern" ]; then
                    errs+=("Unknown licence type '$type'")
                    continue
            fi
            if ! $RIPGREP -qU "$pattern" "$lf"; then
                errs+=("Wrong licence in mog for $file ($type)")
            fi
        done
        IFS="$_IFS"
    done < <(nawk '
            $1 == "license" {
                if (split($0, a, /"/) != 3) split($0, a, "=")
                print $2, a[2]
            }
        ' $P5M_INT2)

    if [ "${#errs[@]}" -gt 0 ]; then
        for e in "${errs[@]}"; do
            logmsg -e $e
        done
        logerr ""
    fi

    if [ $lics -eq 0 ]; then
        logerr "-- No 'license' line in final mog"
        return
    fi
}

#############################################################################
# Clean up and print Done message
#############################################################################

clean_up() {
    logmsg "-- Cleaning up"
    if [ -z "$DONT_REMOVE_INSTALL_DIR" ]; then
        logmsg "--- Removing temporary install directory $DESTDIR"
        logcmd chmod -R u+w $DESTDIR > /dev/null 2>&1
        logcmd rm -rf $DESTDIR || \
            logerr "Failed to remove temporary install directory"
        logmsg "--- Cleaning up temporary manifest and transform files"
        logcmd rm -f $P5M_INT $P5M_INT2 $P5M_INT3 $P5M_INT3.res \
            $MY_MOG_FILE $MANUAL_DEPS || \
            logerr "Failed to remove temporary manifest and transform files"
        logmsg "Done."
    fi
    return 0
}

#############################################################################
# Helper functions to save and restore variables and functions
#############################################################################

save_function() {
    local ORIG_FUNC=$(declare -f $1)
    local NEWNAME_FUNC="$2${ORIG_FUNC#$1}"
    eval "$NEWNAME_FUNC"
}

save_variable() {
    local var=$1
    declare -n _var=$var
    declare -g __save__$var="$_var"
}

restore_variable() {
    local var=$1
    declare -n _var=__save__$var
    declare -g $var="$_var"
}

save_buildenv() {
    local opt
    for opt in $BUILDENV_OPTS; do
        save_variable $opt
    done
}

restore_buildenv() {
    local opt
    for opt in $BUILDENV_OPTS; do
        restore_variable $opt
    done
}

pkg_ver() {
    local src="$1"
    local script="${2:-build.sh}"

    src=$ROOTDIR/build/$src/$script
    [ -f $src ] || logerr "pkg_ver: cannot locate source"
    local ver=`sed -n '/^VER=/ {
                s/.*=//
                p
                q
        }' $src`
    [ -n "$ver" ] || logerr "No version found."
    echo $ver
}

inherit_ver() {
    VER=`pkg_ver "$@"`
    logmsg "-- inherited version '$VER'"
}

# Vim hints
# vim:ts=4:sw=4:et:fdm=marker
