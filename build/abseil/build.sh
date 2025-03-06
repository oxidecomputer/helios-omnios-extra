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

PROG=abseil
VER=20240116.3
PKG=ooce/library/abseil
SUMMARY="abseil"
DESC="Collection of c++ libraries from google"

set_builddir $PROG-cpp-$VER

CONFIGURE_OPTS="
    -DCMAKE_BUILD_TYPE=Release
    -DCMAKE_INSTALL_PREFIX=$PREFIX
"

CONFIGURE_OPTS[i386]="-DCMAKE_INSTALL_LIBDIR=$PREFIX/${LIBDIRS[i386]}"
CONFIGURE_OPTS[amd64]="-DCMAKE_INSTALL_LIBDIR=$PREFIX/${LIBDIRS[amd64]}"

init
download_source abseil $PROG-cpp-$VER
patch_source
prep_build cmake
build -noctf    # C++
make_package
clean_up

# Vim hints
# vim:ts=4:sw=4:et:fdm=marker
