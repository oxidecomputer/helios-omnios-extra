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

PROG=smartmontools
VER=7.2
VERHUMAN=$VER
PKG=ooce/system/smartmontools
SUMMARY="smartmontools"
DESC="Control and monitor storage systems using SMART"

RUN_DEPENDS_IPS=ooce/security/gnupg

OPREFIX=$PREFIX
PREFIX+="/$PROG"

XFORM_ARGS="
    -DPREFIX=${PREFIX#/}
    -DOPREFIX=${OPREFIX#/}
    -DPROG=$PROG
    -DPKGROOT=$PROG
"

# Build 64-bit only and skip the arch-specific directories
set_arch 64

CONFIGURE_OPTS="
    --with-gnupg=$OOCEBIN/gpg
    --with-scriptpath=$USRBIN:$OOCEBIN
"

MAKE_ARGS_WS="BUILD_INFO='\"(Helios r$RELVER)\"'"

init
download_source $PROG $PROG $VER
patch_source
prep_build
build -noctf    # C++
strip_install
install_smf ooce system-smartd.xml
make_package
clean_up

# Vim hints
# vim:ts=4:sw=4:et:fdm=marker
