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

# The protobuf package installs its own copy of this library in the standard
# location, so we install into a abseil-specific directory.
# XXX: see if the protobuf package can be convinced to use a pre-existing
# abseil, and make it depend on this one
PREFIX=$PREFIX/absl

set_arch amd64

CONFIGURE_OPTS[amd64]="
    -DCMAKE_BUILD_TYPE=Release
    -DCMAKE_INSTALL_PREFIX=$PREFIX
"

set_mirror github.com
CHECKSUM_VALUE=sha256:e887b423da5a1ba66e71610094fd7147ff2febfedccdfbf00f2c644ac21adf83
BUILDDIR=abseil-cpp-$VER

init
download_source abseil/abseil-cpp/releases/download/${VER} abseil-cpp-${VER}
prep_build cmake
build -noctf    # C++
make_package
clean_up

# Vim hints
# vim:ts=4:sw=4:et:fdm=marker
