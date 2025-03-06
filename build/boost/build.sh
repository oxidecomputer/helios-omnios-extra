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

# Copyright 2025 Oxide Computer Company

. ../../lib/build.sh

PROG=boost
VER=1.87.0
PKG=ooce/library/boost
SUMMARY="boost"
DESC="Widely used collection of c++ libraries"

SKIP_LICENCES=bsl

OPREFIX=$PREFIX
PREFIX+="/$PROG"

VERNAME=${VER//./_}
set_arch 64
set_builddir boost_$VERNAME

build() {
    pushd $TMPDIR/$BUILDDIR >/dev/null \
        || logerr "Cannot change to $TMPDIR/$BUILDDIR"
    logcmd ./bootstrap.sh --prefix=$DESTDIR/$PREFIX || logerr "bootstrap failed"
    logcmd ./b2 link=static runtime-link=static install || logerr "build failed"
    popd >/dev/null
}

init
download_source boost boost_$VERNAME
patch_source
prep_build
build
make_package
clean_up

# Vim hints
# vim:ts=4:sw=4:et:fdm=marker
