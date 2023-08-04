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

# Copyright 2011-2013 OmniTI Computer Consulting, Inc.  All rights reserved.
# Copyright 2023 OmniOS Community Edition (OmniOSce) Association.

. ../../lib/build.sh

PROG=nginx
PKG=ooce/server/nginx-124
VER=1.24.0
SUMMARY="nginx 1.24 web server"
DESC="nginx is a high-performance HTTP(S) server and reverse proxy"

# Brotli source from https://github.com/google/ngx_brotli
BROTLIVER=1.0.0rc

set_arch 64
test_relver '>=' 151045 && set_clangver

MAJVER=${VER%.*}            # M.m
sMAJVER=${MAJVER//./}       # Mm
set_patchdir patches-$sMAJVER

OPREFIX=$PREFIX
PREFIX+=/$PROG-$MAJVER
CONFPATH=/etc$PREFIX
LOGPATH=/var/log$OPREFIX/$PROG
VARPATH=/var$OPREFIX/$PROG
RUNPATH=$VARPATH/run

BUILD_DEPENDS_IPS="library/security/openssl-3 library/pcre2"
RUN_DEPENDS_IPS="ooce/server/nginx-common"

XFORM_ARGS="
    -DPREFIX=${PREFIX#/}
    -DOPREFIX=${OPREFIX#/}
    -DPROG=$PROG
    -DPKGROOT=$PROG-$MAJVER
    -DMEDIATOR=$PROG -DMEDIATOR_VERSION=$MAJVER
    -DVERSION=$MAJVER
    -DsVERSION=$sMAJVER
    -DDsVERSION=-$sMAJVER
    -DBROTLI=$BROTLIVER
"

CONFIGURE_OPTS[amd64]=
CONFIGURE_OPTS="
    --with-ipv6
    --with-threads
    --with-http_v2_module
    --with-http_ssl_module
    --with-http_addition_module
    --with-http_xslt_module
    --with-http_flv_module
    --with-http_gzip_static_module
    --with-http_mp4_module
    --with-http_random_index_module
    --with-http_realip_module
    --with-http_secure_link_module
    --with-http_stub_status_module
    --with-http_sub_module
    --with-http_dav_module
    --with-stream
    --with-mail
    --with-mail_ssl_module
    --user=nginx
    --group=nginx
    --prefix=$PREFIX
    --conf-path=$CONFPATH/$PROG.conf
    --pid-path=$RUNPATH/$PROG-$MAJVER.pid
    --http-log-path=$LOGPATH/access.log
    --error-log-path=$LOGPATH/error.log
    --http-client-body-temp-path=/tmp/.nginx/body
    --http-proxy-temp-path=/tmp/.nginx/proxy
    --http-fastcgi-temp-path=/tmp/.nginx/fastcgi
    --http-uwsgi-temp-path=/tmp/.nginx/uwsgi
    --http-scgi-temp-path=/tmp/.nginx/scgi
    --add-dynamic-module=../ngx_brotli-$BROTLIVER
"


LDFLAGS+=" -L$PREFIX/lib/amd64 -R$PREFIX/lib/amd64"

copy_man_page() {
    logmsg "--- copying man page"
    logcmd mkdir -p $DESTDIR$PREFIX/share/man/man8 || \
        logerr "--- creating man page directory failed"

    logcmd cp $TMPDIR/$BUILDDIR/objs/$PROG.8 $DESTDIR$PREFIX/share/man/man8 || \
        logerr "--- copying man page failed"
}

init
download_source $PROG $PROG $VER
patch_source
BUILDDIR=ngx_brotli-$BROTLIVER download_source $PROG/brotli v$BROTLIVER
prep_build autoconf-like
build
copy_man_page
xform files/http-$PROG-template.xml > $TMPDIR/http-$PROG-$sMAJVER.xml
xform files/http-$PROG-template > $TMPDIR/http-$PROG-$sMAJVER
install_smf network http-$PROG-$sMAJVER.xml http-$PROG-$sMAJVER
make_package
clean_up

# Vim hints
# vim:ts=4:sw=4:et:fdm=marker
