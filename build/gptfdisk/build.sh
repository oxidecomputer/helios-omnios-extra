#!/usr/bin/bash
#
# {{{ CDDL HEADER
#
# This file and its contents are supplied under the terms of the
# Common Development and Distribution License ("CDDL"), version 1.0.
# You may only use this file in accordance with the terms of version
# 1.0 of the CDDL.
#
# A full copy of the text of the CDDL should have accompanied this
# source. A copy of the CDDL is also available via the Internet at
# http://www.illumos.org/license/CDDL.
# }}}

# Copyright 2021 OmniOS Community Edition (OmniOSce) Association.
# Copyright 2024 Oxide Computer Company

. ../../lib/build.sh

PROG=gptfdisk
VER=1.0.9
PKG=ooce/system/gptfdisk
SUMMARY="GPT fdisk (gdisk, cgdisk, sgdisk, fixparts)"
DESC="GPT fdisk is a disk partitioning tool loosely modeled on Linux "
DESC+="fdisk, but used for modifying GUID Partition Table (GPT) disks."

POPTVER=1.14

set_arch 64

init
prep_build

#########################################################################
# Download and build a static version of popt

save_buildenv

CONFIGURE_OPTS=" --disable-shared --enable-static"

build_dependency popt popt-$POPTVER popt popt $POPTVER

restore_buildenv

export POPT_CFLAGS="-I$DEPROOT/$PREFIX/include"
export POPT_LDFLAGS="-L$DEPROOT/$PREFIX/lib/amd64"

#########################################################################

pre_configure() {
    typeset arch=$1

    MAKE_ARGS_WS="
        CXXFLAGS=\"$CXXFLAGS ${CXXFLAGS[$arch]} $POPT_CFLAGS\"
        LDFLAGS=\"$LDFLAGS ${LDFLAGS[$arch]} $POPT_LDFLAGS -zignore\"
    "

    # No configure
    false
}

make_install() {
    for d in bin share/man/man8; do
        logcmd $MKDIR -p $DESTDIR$PREFIX/$d
    done

    for p in gdisk cgdisk sgdisk fixparts; do
        logcmd $CP $TMPDIR/$BUILDDIR/$p \
            $DESTDIR$PREFIX/bin/$p
        logcmd $CP $TMPDIR/$BUILDDIR/$p.8 \
            $DESTDIR$PREFIX/share/man/man8/$p.8
    done
}

download_source $PROG $PROG $VER
patch_source
build -noctf    # C++
make_package
clean_up

# Vim hints
# vim:ts=4:sw=4:et:fdm=marker
