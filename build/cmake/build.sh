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

PROG=cmake
VER=3.21.4
PKG=ooce/developer/cmake
SUMMARY="Build coordinator"
DESC="An extensible system that manages the build process in a "
DESC+="compiler-independent manner"

set_arch 64

SKIP_LICENCES=Kitware

MAKE=$NINJA

CONFIGURE_OPTS_64="
    --system-curl
    --prefix=$PREFIX
    --generator=Ninja
"

init
download_source $PROG $PROG $VER
patch_source
prep_build
build
strip_install
make_package
clean_up

# Vim hints
# vim:ts=4:sw=4:et:fdm=marker
