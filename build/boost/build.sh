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
BUILDARCH=amd64

PREFIX+="/$PROG"

build() {
    cd $TMPDIR/$BUILDDIR
    ./bootstrap.sh --prefix=$DESTDIR/$PREFIX
    ./b2 link=static runtime-link=static install
}

set_mirror archives.boost.io
VERNAME=`echo $VER | sed "s/\./_/g"`
VERSEP="_"
CHECKSUM_VALUE=sha256:af57be25cb4c4f4b413ed692fe378affb4352ea50fbe294a11ef548f4d527d89
BUILDDIR=boost_$VERNAME

init
download_source release/$VER/source boost $VERNAME
prep_build
build
make_package
clean_up

# Vim hints
# vim:ts=4:sw=4:et:fdm=marker
