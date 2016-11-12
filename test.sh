#!/bin/sh
# -*- sh-basic-offset:4; indent-tabs-mode:nil -*- vi: set sw=4 et:

# MIT License
#
# Copyright (c) 2016 Earl Chew

[ -z "${0##*/*}" ] || exec "$PWD/$0" "$@" || exit 1

set -e

[ $# -eq 3 ] || exit 1

EMAIL=$1    ; shift
APITOKEN=$1 ; shift
ZONE=$1     ; shift

cloudflare()
{
    printf 'Test : %s\n' "$*"
    if [ x"$1" = x"!" ] ; then
        shift
        ! "${0%/*}/cloudflare-cli" "$EMAIL" "$APITOKEN" "$ZONE" "$@"
    else
        "${0%/*}/cloudflare-cli" "$EMAIL" "$APITOKEN" "$ZONE" "$@"
    fi
    printf 'Test : ok\n'
}

trap '[ x$? = x0 ] && printf "Test : PASS\n" || printf "Test : FAIL\n"' EXIT

cloudflare   A @
cloudflare   TXT _acme-challenge = aaa
cloudflare   TXT _acme-challenge = bbb
cloudflare   TXT _acme-challenge =
cloudflare ! TXT _acme-challenge
