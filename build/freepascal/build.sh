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

. ../../lib/build.sh

PROG=fpc
VER=3.2.2
PKG=ooce/developer/freepascal
SUMMARY="Free Pascal compiler"
DESC="Mature, versatile, open source Pascal compiler"

# freepascal compiler is written in pascal
BUILD_DEPENDS_IPS="ooce/developer/freepascal"

set_arch 64

SKIP_RTIME_CHECK=1

OPREFIX=$PREFIX
PREFIX+="/$PROG"

XFORM_ARGS="
    -DPREFIX=${PREFIX#/}
    -DOPREFIX=${OPREFIX#/}
    -DPROG=$PROG
    -DVER=$VER
"

MAKE_TARGET=all

pre_configure() {
    logmsg "--- Generating Makefile"
    logcmd fpcmake Makefile.fpc || logerr "failed to generate Makefile"

    MAKE_INSTALL_ARGS="PREFIX=$DESTDIR$PREFIX"

    # no configure
    false
}

post_install() {
    logcmd mkdir -p $DESTDIR/etc$PREFIX || logerr "mkdir"
    logcmd $DESTDIR$PREFIX/lib/fpc/$VER/samplecfg $PREFIX/lib/fpc/$VER \
        $DESTDIR/etc$PREFIX || logerr "create config failed"
}

init
download_source $PROG $PROG "$VER.source"
patch_source
prep_build
build -noctf
make_package
clean_up

# Vim hints
# vim:ts=4:sw=4:et:fdm=marker
