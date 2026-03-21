#!/usr/bin/env bash

statusline_toml_get() {
    local config_file="$1"
    local key="$2"
    local default_value="$3"

    if [ -f "$config_file" ]; then
        local val
        val=$(sed -n '/^\[statusline\]/,/^\[/{ s/^'"$key"'[[:space:]]*=[[:space:]]*"\{0,1\}\([^"]*\)"\{0,1\}$/\1/p; }' "$config_file" 2>/dev/null | head -1)
        [ -n "$val" ] && { printf "%s" "$val"; return; }
    fi

    printf "%s" "$default_value"
}

statusline_resolve_bool_setting() {
    local requested="$1"
    local default_value="$2"
    local normalized

    normalized=$(printf "%s" "$requested" | tr '[:upper:]' '[:lower:]')
    case "$normalized" in
        1|true|yes|on)
            printf "1"
            ;;
        0|false|no|off)
            printf "0"
            ;;
        "")
            printf "%s" "$default_value"
            ;;
        *)
            printf "%s" "$default_value"
            ;;
    esac
}
