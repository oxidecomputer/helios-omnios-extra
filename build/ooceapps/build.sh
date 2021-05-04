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

PROG=ooceapps
VER=github-latest
PKG=ooce/ooceapps
SUMMARY="OOCEapps"
DESC="Web integrations for OmniOS"

set_arch 64

set_mirror "$OOCEGITHUB/$PROG/releases/download"

# some perl modules require gnu-tar to unpack
export PATH="/usr/gnu/bin:$PATH"

RUN_DEPENDS_IPS="ooce/application/texlive"

OPREFIX=$PREFIX
PREFIX+="/$PROG"

XFORM_ARGS="
    -DPREFIX=${PREFIX#/}
    -DOPREFIX=${OPREFIX#/}
    -DPROG=$PROG
"

CONFIGURE_OPTS_64="
    --prefix=$PREFIX
    --sysconfdir=/etc$PREFIX
    --localstatedir=/var$PREFIX
"

add_extra_files() {
    # copy config template
    for f in $PROG fenix; do
        logcmd cp $DESTDIR/etc/$PREFIX/$f.conf.dist \
            $DESTDIR/etc/$PREFIX/$f.conf \
            || logerr "--- cannot copy $f"
    done
}

init
download_source "v$VER" $PROG $VER
patch_source
prep_build
build
add_extra_files
install_smf ooce ooceapps.xml
install_smf ooce fenix.xml
make_package
clean_up

# Vim hints
# vim:ts=4:sw=4:et:fdm=marker
