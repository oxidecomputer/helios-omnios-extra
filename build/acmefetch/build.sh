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
#
# Copyright 2020 OmniOS Community Edition (OmniOSce) Association.

. ../../lib/functions.sh

PROG=acmefetch
VER=0.7.5
PKG=ooce/util/acmefetch
SUMMARY="AcmeFetch"
DESC="A thin wrapper arount he ACME::Protocol library to fetch and maintain "
DESC+="ssl certificates using the the services of Let's Encrypt!"

OPREFIX=$PREFIX
PREFIX+="/$PROG"

set_arch 64

XFORM_ARGS="
    -DPREFIX=${PREFIX#/}
    -DOPREFIX=${OPREFIX#/}
    -DPROG=$PROG
"

CONFIGURE_OPTS_64="
    --prefix=$PREFIX
    --sysconfdir=/etc$PREFIX
"

copy_config() {
    # copy config template
    logcmd cp $DESTDIR/etc$PREFIX/$PROG.cfg.dist $DESTDIR/etc$PREFIX/$PROG.cfg \
        || logerr "--- cannot copy config file template"
}

init
download_source $PROG $PROG $VER
patch_source
prep_build
build
copy_config
make_package
clean_up

# Vim hints
# vim:ts=4:sw=4:et:fdm=marker
