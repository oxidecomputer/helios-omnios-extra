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

PROG=socat
VER=1.7.4.1
PKG=ooce/network/socat
SUMMARY="Multipurpose socket relay"
DESC="socat is a relay for bidirectional data transfer "
DESC+="between two independent data channels."

# socat was moved to omnios core from r151031 on
exit 0

set_arch 64

CONFIGURE_OPTS="
    --bindir=$PREFIX/bin
"

init
download_source $PROG $PROG $VER
patch_source
prep_build
build
make_package
clean_up

# Vim hints
# vim:ts=4:sw=4:et:fdm=marker
