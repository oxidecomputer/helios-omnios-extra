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

# Copyright 2021 Oxide Computer Company

. ../../lib/functions.sh

PROG=lrzsz
VER=0.12.20
PKG=ooce/terminal/lrzsz
SUMMARY="$PROG - XMODEM/YMODEM/ZMODEM implementation"
DESC="$PROG is a UNIX communication package providing the "
DESC+="XMODEM, YMODEM ZMODEM file transfer protocols."

set_arch 64

set_mirror "https://www.ohse.de/uwe/releases/"
set_checksum sha256 \
    'c28b36b14bddb014d9e9c97c52459852f97bd405f89113f30bee45ed92728ff1'

HARDLINK_TARGETS="
    ${PREFIX#/}/bin/sz
    ${PREFIX#/}/bin/rz
"

#
# By default, the package builds programs with an "l" prefix; e.g., "lrx", etc.
# This does not match the names that other software appears to expect, so drop
# the prefix:
#
CONFIGURE_OPTS="--program-transform-name='s/^l//'"

init
download_source '' $PROG $VER
patch_source
prep_build
build
strip_install
make_package
clean_up

# Vim hints
# vim:ts=4:sw=4:et:fdm=marker
