#!/bin/sh

# Identify and remove shims carrying our unique marker in a single directory.
# (DELETED_COUNT is provided as a local by main and relies on the shell's dynamic scope.)
remove_shims_in_dir() {
    local dir=$1
    [ -d "$dir" ] || return
    # Every local declaration carries an assignment: zsh's local prints the value
    # when declared without one (TYPESET_SILENT is off by default).
    local abs_dir=
    abs_dir=$(cd "$dir" && pwd) || return
    local name= file_path=
    # List the file names literally to avoid relying on word splitting of an
    # unquoted variable (zsh does not split by default).
    for name in python python3 pip pip3 uvpin _uvshim_resolve; do
        file_path="$abs_dir/$name"

        # Must be a regular, readable file
        if [ -f "$file_path" ] && [ -r "$file_path" ]; then
            # Precisely detect our unique marker
            if grep -q "\[UV-SHIMS-MARKER\]" "$file_path"; then
                echo "  🗑️ Found and removed shim: $file_path"
                rm "$file_path"
                DELETED_COUNT=$((DELETED_COUNT + 1))
            fi
        fi
    done
}

# ==============================================================================
# Main flow.
# Wrapped in a function so that, when sourced, set -- and variables do not leak
# into the caller and exit cannot kill the caller's shell.
# ==============================================================================
main() {
    local DELETED_COUNT=0

    echo "🔍 Scanning the system PATH and target directories for our uv shims..."

    # 1. Handle the path passed as an argument first
    # POSIX sh does not expand ~ inside a variable value; expand "~" and "~/..." manually
    local ARG_DIR=$1
    case "$ARG_DIR" in
        "~")   ARG_DIR=$HOME ;;
        "~/"*) ARG_DIR=$HOME/${ARG_DIR#\~/} ;;
    esac
    if [ -n "$ARG_DIR" ] && [ -d "$ARG_DIR" ]; then
        remove_shims_in_dir "$ARG_DIR"
    fi

    # 2. Parse the global PATH (split on colons manually: zsh does not word-split
    #    unquoted variables by default)
    local rest=$PATH p=
    while [ -n "$rest" ]; do
        case "$rest" in
            *:*) p=${rest%%:*}; rest=${rest#*:} ;;
            *)   p=$rest; rest= ;;
        esac
        [ -n "$p" ] && remove_shims_in_dir "$p"
    done

    # 3. Print the cleanup result
    echo "=========================================================="
    if [ "$DELETED_COUNT" -gt 0 ]; then
        echo "🎉 Cleanup complete! Removed $DELETED_COUNT uv shim script(s) above."
    else
        echo "👍 No uv shims of ours found in your PATH or the given directory; nothing changed."
    fi
    echo "=========================================================="
}

main "$@"
