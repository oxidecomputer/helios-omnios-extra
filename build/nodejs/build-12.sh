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

. ../../lib/functions.sh

PROG=node
VER=12.22.1
PKG=ooce/runtime/node-12
SUMMARY="Node.js is an evented I/O framework for the V8 JavaScript engine."
DESC="Node.js is an evented I/O framework for the V8 JavaScript engine. "
DESC+="It is intended for writing scalable network programs such as web servers."

set_arch 64

set_builddir $PROG-v$VER

BUILD_DEPENDS_IPS="
    developer/gnu-binutils
    runtime/python-27
"

MAJVER=${VER%%.*}

OPREFIX=$PREFIX
PREFIX+=/$PROG-$MAJVER

# objdump is needed to build nodejs
TRIPLET=$TRIPLET64
PATH+=":/usr/gnu/$TRIPLET/bin"

CXXFLAGS+="-ffunction-sections -fdata-sections"
MAKE_ARGS="CC=$CC"

XFORM_ARGS="
    -DPREFIX=${PREFIX#/}
    -DOPREFIX=${OPREFIX#/}
    -DPROG=$PROG
    -DPKGROOT=$PROG-$MAJVER
    -DMEDIATOR=$PROG -DMEDIATOR_VERSION=$MAJVER
    -DVERSION=$MAJVER
"

CONFIGURE_OPTS_64=
CONFIGURE_OPTS="
    --prefix=$PREFIX
    --with-dtrace
    --dest-cpu=x64
    --shared-nghttp2
    --shared-openssl
    --shared-zlib
"
CONFIGURE_OPTS+=" --shared-brotli"

init
download_source $PROG $PROG v$VER
patch_source
prep_build
build -noctf    # ctfconvert does currently not work
strip_install
make_package
clean_up

# Vim hints
# vim:ts=4:sw=4:et:fdm=marker
