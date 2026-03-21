#!/usr/bin/env bash
# DEPRECATED: Use codex_statusline.sh instead.
# This shim exists for backward compatibility.
script_dir="$(cd "$(dirname "$0")" && pwd)"
exec "$script_dir/codex_statusline.sh" "$@"
