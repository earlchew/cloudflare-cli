# -*- sh-basic-offset:4; indent-tabs-mode:nil -*- vi: set sw=4 et:

# MIT License
#
# Copyright (c) 2016 Earl Chew

print()
{
    printf "%s\n" "$1"
}

die()
{
    print "$1" >&2
    exit 1
}

fail()
{
    print "$1" >&2
    return 1
}

_debug()
{
    [ -z "${CLOUDFLAREDEBUG++}" ] || print "$0: $1" >&2
}

_curl()
{
    local _result

    _debug "curl $*"
    _result=$(curl "$@") || return 1
    _debug " -> $_result"
    print "$_result"
}

_jsonsh()
{
    "${0%/*}/jsonsh" "$@"
}

_jsonindex()
{
    set -- "${1#*,}"
    set -- "${1%%,*}"
    print "$1"
}

_jsonvalue()
{
    set -- "${1#*\]}"
    set -- "${1#*\"}"
    set -- "${1%\"*}"
    print "$1"
}

_jsonobjectfield()
{
    set -- "$(
        print "$2" |
        while read -r _field ; do
            _name=$_field
            _name="${_name%%\]*}"
            _name="${_name##*,}"
            _name="${_name#\"}"
            _name="${_name%\"}"
            [ x"$_name" != x"$1" ] ||
                { print "$_field" ; break ; }
        done)"
    [ -n "$1" ] || return 1
    print "$1"
}

_callCloudFlare()
{
    (
	exec 9>&1
        (
            exec 8>&1

            _email=$1                                      ; shift
            _apitoken=$1                                   ; shift
	    _api="https://api.cloudflare.com/client/v4/$1" ; shift

	    set -- "$_api" "$@"
	    set -- "$@" -s
	    set -- "$@" -H Content-Type:application/json
	    set -- "$@" -H X-Auth-Key:"$_apitoken"
	    set -- "$@" -H X-Auth-Email:"$_email"

            set +e
	    ( _curl "$@"     ; printf "%s" $? >&8 ; ) |
            ( _jsonsh -b >&9 ; printf "%s\n" $? >&8 ; )
	) | (
            read -r _rc
            : $_rc
            [ x"$_rc" = x"00" ] || exit 1
            exit 0
        )
    )
}

_checkCloudFlareResult()
{
    (
        _result="$(print "$1" | grep '^\["success"\]')"
        _debug "result $_result"
        _status="$(_jsonvalue "$_result" | {
            read -r _result && print "$_result"; } )"
        [ x"true" = x"$_status" ] ||
            fail "Operation result $_result"
    )
}

_zoneId()
{
    local _email=$1    ; shift
    local _apitoken=$1 ; shift
    local _zone=$1     ; shift

    local _zones
    { _zones="$(_callCloudFlare "$_email" "$_apitoken" "zones?name=$_zone")" &&
      _checkCloudFlareResult "$_zones" ; } ||
      die "Unable to find zone $_zone"

    local _zoneindex=
    { _zoneindex=$(print "$_zones" |
        grep '\["result",[^,]*,"name"\]' |
        grep -F "\""$_zone"\"") && [ -n "$_zoneindex" ] ; } ||

        die "Unable to find zone index in $_zones"
    _debug "zone index <$_zoneindex>"

    _zoneindex="$(_jsonindex "$_zoneindex")" ||
        die "Unable to extract zone index from $_zoneindex"

    { _zoneid=$(print "$_zones" |
        grep '\["result",'"$_zoneindex"',"id"\]') &&
      [ -n "$_zoneid" ] ; } ||

        die "Unable to find zone id in $_zones"
    _debug "zone id <$_zoneid>"

    _zoneid="$(_jsonvalue "$_zoneid")" ||
        die "Unable to extract zone id from $_zoneid"
    print "$_zoneid"
}

_cloudflareAction()
{
    local _action=$1   ; shift
    local _email=$1    ; shift
    local _apitoken=$1 ; shift
    local _zone=$1     ; shift
    local _type=$1     ; shift
    local _host=$1     ; shift

    if [ x"$_host" = x"@" ] ; then
        _host=$_zone
    else
        _host="$_host.$_zone"
    fi

    local _zoneid
    _zoneid=$(_zoneId "$_email" "$_apitoken" "$_zone")
    [ -n "$_zoneid" ] ||
        die "Unable to determine zone id for $_zone"

    local _records
    { _records="$(
        set --
        set -- "$@" "$_email"
        set -- "$@" "$_apitoken"
        set -- "$@" "zones/$_zoneid/dns_records"
        _callCloudFlare "$@")" &&
        _checkCloudFlareResult "$_records" ; } ||
        die "Unable to find domain records for zone $_zoneid"
    _debug "domain records <$_records>"

    _recordindexlist="$(print "$_records" |
        grep '^\["result",[^,]*,"type"\].*"'"$_type"'"$' |
        while read -r _record ; do
            _recordindex="$(_jsonindex "$_record")"
            [ -n "$_recordindex" ] ||
                die "Unable to extract record index $_record"
            print "$_recordindex"
        done)"

    _recordindex="$(
        for _recordindex in $_recordindexlist ; do
            print "$_records" |
            grep '^\["result",'"$_recordindex"',"name"\]' |
            while read -r _field ; do
                [ -z "${_field##*\"$_host\"}" ] || continue
                print "$_recordindex"
                exit 0
            done
         done)"

    if [ -n "$_recordindex" ] ; then

        _recordid="$(
            print "$_records" |
            grep '^\["result",'"$_recordindex"',"id"\]')"
        [ -n "$_recordid" ] ||
            die "Unable to extract record id $_record"
        _recordid="$(_jsonvalue "$_recordid")"
        _debug "record id <$_recordid>"

        _recordcontent="$(
            print "$_records" |
            grep '^\["result",'"$_recordindex"',"content"\]')"
        [ -n "$_recordcontent" ] ||
            die "Unable to extract record content $_record"
        _recordcontent="$(_jsonvalue "$_recordcontent")"
        _debug "record content <$_recordcontent>"

        {
            _replacement="$(
                eval "$_action" 'content "$_recordcontent" "$@"')"
        } 3>&1 || return 1
        _debug "record content replacement <$_replacement>"

        if [ x"=$_recordcontent" != x"$_replacement" ] ; then
            if [ -z "${_replacement}" ] ; then
                (
                    set --
                    set -- "$@" "$_email"
                    set -- "$@" "$_apitoken"
                    set -- "$@" "zones/$_zoneid/dns_records/$_recordid"
                    _checkCloudFlareResult "$(
                        _callCloudFlare "$@" -X DELETE)" ||
                    die "Unable remove record $_recordid"
                )
            else
                _replacement="${_replacement#=}"

                (
                    _record=
                    _record="$_record,\"type\": \"$_type\""
                    _record="$_record,\"name\": \"$_host\""
                    _record="$_record,\"content\": \"$_replacement\""
                    _record="{ ${_record#,} }"

                    set --
                    set -- "$@" "$_email"
                    set -- "$@" "$_apitoken"
                    set -- "$@" "zones/$_zoneid/dns_records/$_recordid"
                    set -- "$@" -d "$_record"
                    _checkCloudFlareResult "$(
                        _callCloudFlare "$@" -X PUT)" ||
                    die "Unable to modify record $_recordid"
                )
            fi
        fi

    else
        {
            _content="$(eval "$_action" '"" "$@"')"
        } 3>&1 || return 1

        if [ -n "$_content" ] ; then
            _content="${_content#=}"
            _debug "record content initial value <$_content>"

            (
                _record=
                _record="$_record,\"type\": \"$_type\""
                _record="$_record,\"name\": \"$_host\""
                _record="$_record,\"content\": \"$_content\""
                _record="$_record,\"ttl\": 1"
                _record="{ ${_record#,} }"

                set --
                set -- "$@" "$_email"
                set -- "$@" "$_apitoken"
                set -- "$@" "zones/$_zoneid/dns_records"
                set -- "$@" -d "$_record"
                _checkCloudFlareResult "$(
                    _callCloudFlare "$@" -X POST)" ||
                die "Unable to create record for $_host"
            )
        fi
    fi
}

_cloudflareRead()
{
    [ x"$1" = x"content" ] || return 1
    print "$2" >&3
    print "=$2"
}

cloudflareRead()
{
    _cloudflareAction _cloudflareRead "$@"
}

_cloudflareWrite()
{
    if [ x"$1" = x"content" ] ; then
        print "=$3"
    else
        print "=$2"
    fi
}

cloudflareWrite()
{
    _cloudflareAction _cloudflareWrite "$@"
}

_cloudflareDelete()
{
    print ''
}

cloudflareDelete()
{
    _cloudflareAction _cloudflareDelete "$@"
}
