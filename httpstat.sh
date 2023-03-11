#!/usr/bin/env bash

print_help() {
    cat <<'END'
Usage: httpstat URL [CURL_OPTIONS]
       httpstat -h | --help
       httpstat --version
Arguments:
  URL     url to request, could be with or without `http(s)://` prefix
Options:
  CURL_OPTIONS  any curl supported options, except for -w -D -o -S -s,
                which are already used internally.
  -h --help     show this screen.
  --version     show version.
Environments:
  HTTPSTAT_SHOW_HEADER  By default httpstat will show the request header, set to `false` to close it.
  HTTPSTAT_SHOW_BODY    By default httpstat will write response body
                        in a tempfile, but you can let it print out by setting
                        this variable to `true`.
  HTTPSTAT_SHOW_SPEED   set to `true` to show download and upload speed.
END
}

green="\033[32m"
cyan="\033[36m"
white="\033[37m"
reset="\033[0m"

while (( $# > 0 ))
do
    case "$1" in
        -h | --help)
            print_help
            exit 1
            ;;
        --version)
            echo "httpstat 0.0.1"
            exit 0
            ;;
        '-w' | '--write-out')
            continue
            ;;
        '-D' | '--dump-header')
            continue
            ;;
        '-o' | '--output')
            continue
            ;;
        '-s' | '--silent')
            continue
            ;;
        -* | --*)
            args+=( "$1" )
            ;;
        *)
            url="$1"
            ;;
    esac
    shift
done

if [[ -z $url ]]; then
    echo "too few arguments" >&2
    exit 1
fi

curl_format='{
"time_namelookup": %{time_namelookup},
"time_connect": %{time_connect},
"time_appconnect": %{time_appconnect},
"time_pretransfer": %{time_pretransfer},
"time_redirect": %{time_redirect},
"time_starttransfer": %{time_starttransfer},
"time_total": %{time_total},
"speed_download": %{speed_download},
"speed_upload": %{speed_upload}
}'

head="/tmp/httpstat-header.$$$RANDOM$(date +%s)"
body="/tmp/httpstat-body.$$$RANDOM$(date +%s)"

data="$(
LC_ALL=C curl \
    -w "$curl_format" \
    -D "$head" \
    -o "$body" \
    -s -S \
    "${args[@]}" \
    "$url" 2>&1
)"

get() {
    local d
    d="$(
    echo "$data" \
        | grep "$1" \
        | awk '{print $2}' \
        | sed 's/,//g'
    )"
    if type bc &>/dev/null; then
        echo "$d"*1000 | bc -l
    else
        echo "$d" | awk 'END{print $0*1000}'
    fi
}

calc() {
    if type bc &>/dev/null; then
        echo "$@" | bc -l
    else
        echo "$@" | awk "BEGIN{print $*}"
    fi
}

time_namelookup="$(get time_namelookup)"
time_connect="$(get time_connect)"
time_appconnect="$(get time_appconnect)"
time_pretransfer="$(get time_pretransfer)"
time_redirect="$(get time_redirect)"
time_starttransfer="$(get time_starttransfer)"
time_total="$(get time_total)"
speed_download="$(get speed_download)"
speed_upload="$(get speed_upload)"

range_dns="$time_namelookup"
range_connection="$(calc "$time_connect" - "$time_namelookup")"
range_ssl="$(calc "$time_pretransfer" - "$time_connect")"
range_server="$(calc "$time_starttransfer" - "$time_pretransfer")"
range_transfer="$(calc "$time_total" - "$time_starttransfer")"

fmta() {
    echo "$1" \
        | awk '{printf("%5dms\n", $1 + 0.5)}'
}

fmtb() {
    local d
    d="$(
    echo "$1" \
        | awk '{printf("%d\n", $1 + 0.5)}'
    )"
    printf "%-7s\n" "${d}ms"
}

a000="$cyan$(fmta "$range_dns")$reset"
a001="$cyan$(fmta "$range_connection")$reset"
a002="$cyan$(fmta "$range_ssl")$reset"
a003="$cyan$(fmta "$range_server")$reset"
a004="$cyan$(fmta "$range_transfer")$reset"
b000="$cyan$(fmtb "$time_namelookup")$reset"
b001="$cyan$(fmtb "$time_connect")$reset"
b002="$cyan$(fmtb "$time_pretransfer")$reset"
b003="$cyan$(fmtb "$time_starttransfer")$reset"
b004="$cyan$(fmtb "$time_total")$reset"

https_template="$white
  DNS Lookup   TCP Connection   SSL Handshake   Server Processing   Content Transfer$reset
[   ${a000}  |     ${a001}    |    ${a002}    |      ${a003}      |      ${a004}     ]
             |                |               |                   |                  |
    namelookup:${b000}        |               |                   |                  |
                        connect:${b001}       |                   |                  |
                                    pretransfer:${b002}           |                  |
                                                      starttransfer:${b003}          |
                                                                                 total:${b004}
"

http_template="$white
  DNS Lookup   TCP Connection   Server Processing   Content Transfer$reset
[   ${a000}  |     ${a001}    |      ${a003}      |      ${a004}     ]
             |                |                   |                  |
    namelookup:${b000}        |                   |                  |
                        connect:${b001}           |                  |
                                      starttransfer:${b003}          |
                                                                 total:${b004}
"

# output, need to print escape sequences raw (disable those checks for shellcheck)
# shellcheck disable=SC2059,SC2002
{
    # Print header
    if [[ "${HTTPSTAT_SHOW_HEADER}" == false ]]; then
       printf "${green}Header${reset} stored in: $head\n"
    else
       cat "$head"; printf '\n'
    fi

    # Print body
    if [[ "${HTTPSTAT_SHOW_BODY}" == true ]]; then
        cat "$body"; printf '\n'
    else
        printf "${green}Body${reset} stored in: $body\n"
    fi

    if [[ "$url" =~ https:// ]]; then
        printf "$https_template\n"
    else
        printf "$http_template\n"
    fi

    # speed, originally bytes per second
    if [[ "${HTTPSTAT_SHOW_SPEED}" == true ]]; then
        printf "Download Speed: %.2f KiB/s, Upload Speed: %.2f KiB/s\n" \
            $([ -n "${speed_download}" -a "${speed_download}" != "0" ] && echo "scale=2;${speed_download}/1024/1024"|bc)
            $([ -n "${speed_upload}" -a "${speed_upload}" != "0" ] && echo "scale=2;${speed_upload}/1024/1024"|bc)
    fi
}
