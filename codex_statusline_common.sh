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

statusline_json_get() {
    local config_file="$1"
    local jq_filter="$2"
    local default_value="$3"

    if [ -f "$config_file" ] && command -v jq >/dev/null 2>&1; then
        local val
        val=$(jq -r "$jq_filter // empty" "$config_file" 2>/dev/null | head -1)
        [ -n "$val" ] && [ "$val" != "null" ] && { printf "%s" "$val"; return; }
    fi

    printf "%s" "$default_value"
}

statusline_json_env_get() {
    local config_file="$1"
    local env_name="$2"
    local default_value="$3"

    statusline_json_get "$config_file" ".env[\"$env_name\"]" "$default_value"
}

statusline_env_get_first() {
    local env_name value

    for env_name in "$@"; do
        value="${!env_name:-}"
        if [ -n "$value" ]; then
            printf "%s" "$value"
            return 0
        fi
    done

    return 1
}

statusline_json_env_get_first() {
    local config_file="$1"
    local default_value="$2"
    shift 2

    local env_name value
    for env_name in "$@"; do
        value=$(statusline_json_env_get "$config_file" "$env_name" "")
        if [ -n "$value" ]; then
            printf "%s" "$value"
            return 0
        fi
    done

    printf "%s" "$default_value"
}

statusline_resolve_json_setting() {
    local config_file="$1"
    local default_value="$2"
    shift 2

    local value
    value=$(statusline_env_get_first "$@" 2>/dev/null || true)
    if [ -n "$value" ]; then
        printf "%s" "$value"
        return 0
    fi

    statusline_json_env_get_first "$config_file" "$default_value" "$@"
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

statusline_resolve_json_bool_setting() {
    local config_file="$1"
    local default_value="$2"
    shift 2

    local requested
    requested=$(statusline_resolve_json_setting "$config_file" "" "$@")
    statusline_resolve_bool_setting "$requested" "$default_value"
}
