#!/bin/sh

# ==============================================================================
# Script name (used only in help output).
# When executed directly, $0 is the script name; when sourced, $0 is the current
# shell, so prefer bash's BASH_SOURCE / zsh's %x to recover the real script name.
# A non-bash/zsh sh cannot know it, so fall back to the fixed value below, which
# matches the file name.
# ==============================================================================
APP_NAME=install_uvshim_w_uvpip.sh
if [ -n "$BASH_SOURCE" ]; then
    APP_NAME=${BASH_SOURCE##*/}
elif [ -n "$ZSH_EVAL_CONTEXT" ]; then
    eval 'APP_NAME=${(%):-%x}'
    APP_NAME=${APP_NAME##*/}
fi

# Show usage help for the install script
show_install_help() {
    echo "💡 uv smart global shim suite - one-click installer; this variant uses uv pip instead of native pip for speed"
    echo "--------------------------------------------------------"
    echo "Usage:"
    echo "  ./${APP_NAME} [target-dir]     Deploy shims to a target dir (default: ~/.local/bin)"
    echo "  ./${APP_NAME} -h | --help      Show this help"
    echo ""
    echo "📦 Files deployed:"
    echo "  - python / python3 : smart, loop-safe global router that detects project virtualenvs"
    echo "  - pip / pip3       : installer dynamically bound to the current python version (Plan B)"
    echo "  - uvpin            : context-aware Python version pinning tool, replaces \`uv python pin\`"
    echo ""
    echo "⚠️ Note: on macOS + Homebrew + uv, this plan's pip may not install into the target Python version's directory."
    echo "   In that case, use the \`install_uvshim.sh\` script instead."
    echo "--------------------------------------------------------"
}

# Dynamically generate the python and python3 shims
create_python_shim() {
    local name=$1
    local file_path="$TARGET_DIR/$name"

    # Pick a fully compatible PATH-cleanup command per OS
    local sed_cmd=""
    if [ "$OS_TYPE" = "Darwin" ]; then
        # macOS (BSD sed)
        sed_cmd='CLEANED_PATH=$(echo "$PATH" | sed -E "s#(^|:)$SCRIPT_DIR(:|\$)#:#g; s#^:##; s#:\$##")'
    else
        # Linux (GNU sed)
        sed_cmd='CLEANED_PATH=$(echo "$PATH" | sed -r "s#(^|:)$SCRIPT_DIR(:|\$)#:#g; s#^:##; s#:\$##")'
    fi

    cat << EOF > "$file_path"
#!/bin/sh
# [UV-SHIMS-MARKER] - DO NOT REMOVE THIS LINE
# 1. If a virtualenv is active, use its python directly
if [ -n "\$VIRTUAL_ENV" ]; then
    exec "\$VIRTUAL_ENV/bin/python" "\$@"
fi

# 2. Locate the directory of this script (and of uv)
SCRIPT_DIR=\$(cd "\$(dirname -- "\$0")" && pwd)

# 3. Find the real uv path (prefer command -v over which for portability)
REAL_UV="\$SCRIPT_DIR/uv"
if [ ! -x "\$REAL_UV" ]; then
    REAL_UV=\$(command -v uv 2>/dev/null)
fi

if [ -z "\$REAL_UV" ]; then
    echo "❌ Error: uv not found in the system or current directory; install uv first!" >&2
    exit 1
fi

# 4. Remove this shim's directory from PATH (prevents an infinite loop when uv probes python)
$sed_cmd

# 5. Run uv with the cleaned PATH
PATH="\$CLEANED_PATH" exec "\$REAL_UV" run python "\$@"
EOF

    chmod +x "$file_path"
    echo "  ✅ Deployed: $name"
}

# Create the pip and pip3 shims
create_pip_shim() {
    local name=$1
    local file_path="$TARGET_DIR/$name"

    cat << 'EOF' > "$file_path"
#!/bin/sh
# [UV-SHIMS-MARKER] - DO NOT REMOVE THIS LINE
SCRIPT_DIR=$(cd "$(dirname -- "$0")" && pwd)

REAL_UV="$SCRIPT_DIR/uv"
if [ ! -x "$REAL_UV" ]; then
    REAL_UV=$(command -v uv 2>/dev/null)
fi

if [ -z "$REAL_UV" ]; then
    echo "❌ Error: uv path not found!" >&2
    exit 1
fi

# Forward directly to the fast uv pip, which adapts to the python pinned in the current dir
exec "$REAL_UV" pip "$@"
EOF

    chmod +x "$file_path"
    echo "  ✅ Deployed: $name"
}

# Create the context-aware uvpin tool
create_uvpin_tool() {
    local file_path="$TARGET_DIR/uvpin"

    cat << 'EOF' > "$file_path"
#!/bin/sh
# [UV-SHIMS-MARKER] - DO NOT REMOVE THIS LINE

show_help() {
    echo "💡 Modern context-aware uv version manager - uvpin"
    echo "--------------------------------------------------------"
    echo "Usage:"
    echo "  uvpin                  Show the Python version effective in the current context"
    echo "  uvpin <version>        Smartly pin a Python version for the current project, legacy env, or global"
    echo "  uvpin -h | --help      Show this help"
    echo ""
    echo "🧠 Smart write priority:"
    echo "  1. Inside a project dir   -> pin a local .python-version at the project root"
    echo "  2. Touching the home dir  -> overwrite the legacy ~/.python-version in place"
    echo "  3. Plain global dir       -> write to the central config ~/.config/uv/.python-version"
    echo "--------------------------------------------------------"
}

# Handle the help option
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    show_help
    exit 0
fi

CURRENT_DIR=$(pwd)
HOME_DIR=$(cd "$HOME" && pwd)

# Walk upward to find the most fitting control file or project root
find_active_target() {
    dir="$CURRENT_DIR"
    while [ "$dir" != "/" ]; do
        # 1. Check for local project markers
        if [ -f "$dir/.python-version" ] || [ -f "$dir/pyproject.toml" ] || [ -d "$dir/.venv" ]; then
            if [ "$dir" = "$HOME_DIR" ]; then
                break
            fi
            echo "project:$dir"
            return
        fi
        dir=$(dirname -- "$dir")
    done

    # 2. Check for a leftover file in the home dir
    if [ -f "$HOME_DIR/.python-version" ]; then
        echo "home_legacy:$HOME_DIR"
        return
    fi

    # 3. Default to global
    echo "global:$HOME_DIR/.config/uv"
}

TARGET_INFO=$(find_active_target)
TARGET_TYPE=$(echo "$TARGET_INFO" | cut -d':' -f1)
TARGET_PATH=$(echo "$TARGET_INFO" | cut -d':' -f2-)

# Query mode (no arguments)
if [ -z "$1" ]; then
    echo "🔍 Analyzing the Python dispatch context..."
    case "$TARGET_TYPE" in
        "project")
            if [ -f "$TARGET_PATH/.python-version" ]; then
                echo "📂 In a project directory: $TARGET_PATH"
                echo "📌 Project-pinned version: $(cat "$TARGET_PATH/.python-version")"
            else
                echo "📂 This is a project path ($TARGET_PATH) but no local Python version is pinned yet."
                echo "💡 Hint: run 'uvpin 3.x' to pin a version for this project."
            fi
            ;;
        "home_legacy")
            echo "⚠️  Controlled by a legacy file in the home dir: $TARGET_PATH/.python-version"
            echo "📌 Pinned version: $(cat "$TARGET_PATH/.python-version")"
            ;;
        "global"|*)
            if [ -f "$HOME_DIR/.config/uv/.python-version" ]; then
                echo "🌍 Plain global environment, controlled by the central config."
                echo "📌 Global default Python version: $(cat "$HOME_DIR/.config/uv/.python-version")"
            else
                echo "🌍 Central config not initialized yet; the system Python is in charge."
                echo "💡 Hint: run 'uvpin 3.x' to set the global default Python version."
            fi
            ;;
    esac
    exit 0
fi

# Write mode (with an argument)
VERSION="$1"
case "$TARGET_TYPE" in
    "project")
        echo "📂 Project directory detected; pinning version $VERSION for this project..."
        uv python pin "$VERSION"
        ;;
    "home_legacy")
        echo "⚠️  A legacy local file exists in the home dir; updating it in place to $VERSION..."
        (cd "$HOME" && uv python pin "$VERSION")
        ;;
    "global"|*)
        echo "🌍 No specific project detected; updating the global config (~/.config/uv/.python-version) to $VERSION..."
        uv python pin --global "$VERSION"
        ;;
esac
EOF
    chmod +x "$file_path"
    echo "  ✅ Deployed: uvpin"
}

# Find an executable in PATH; print the first matching directory (as an absolute path)
find_first_dir_in_path() {
    local name=$1
    # Every local declaration carries an assignment: zsh's local prints the value
    # when declared without one (TYPESET_SILENT is off by default).
    local rest=$PATH d=
    # Split on colons manually: zsh does not word-split unquoted variables by default.
    while [ -n "$rest" ]; do
        case "$rest" in
            *:*) d=${rest%%:*}; rest=${rest#*:} ;;
            *)   d=$rest; rest= ;;
        esac
        [ -n "$d" ] || continue
        if [ -x "$d/$name" ]; then
            (cd "$d" 2>/dev/null && pwd)
            return 0
        fi
    done
    return 1
}

# Check whether the install dir takes effect first in PATH; warn if not
check_path_priority() {
    local target=$1
    local rest=$PATH d= idx= target_index= cd_dir=
    idx=0
    target_index=-1
    # Split on colons manually: zsh does not word-split unquoted variables by default.
    while [ -n "$rest" ]; do
        case "$rest" in
            *:*) d=${rest%%:*}; rest=${rest#*:} ;;
            *)   d=$rest; rest= ;;
        esac
        if [ -n "$d" ]; then
            cd_dir=$(cd "$d" 2>/dev/null && pwd) || cd_dir=$d
            if [ "$cd_dir" = "$target" ]; then
                target_index=$idx
                break
            fi
        fi
        idx=$((idx + 1))
    done

    # The shims are effective as long as these commands all resolve to the install dir
    local problems= cmd= found=
    for cmd in python python3 pip pip3; do
        found=$(find_first_dir_in_path "$cmd")
        if [ "$found" != "$target" ]; then
            if [ -z "$found" ]; then
                problems="$problems
  - $cmd: not found in the current PATH"
            else
                problems="$problems
  - $cmd: resolves to $found first"
            fi
        fi
    done

    if [ -z "$problems" ]; then
        echo ""
        echo "🟢 PATH check: python/python3/pip/pip3 are all handled by these shims first."
        return 0
    fi

    echo ""
    printf '\033[1;33m%s\033[0m\n' "⚠️  Warning: the install dir is not taking effect first in PATH!"
    echo "   Install dir: $target"
    if [ "$target_index" -lt 0 ]; then
        echo "   This directory is NOT in your PATH."
    elif [ "$target_index" -gt 0 ]; then
        echo "   The directory is in PATH, but $target_index earlier directories provide the same commands."
    fi
    echo "   These commands do not resolve to the install dir first:$problems"
    echo ""
    echo "   Move it ahead in PATH, e.g. in ~/.zshrc or ~/.bashrc:"
    printf '     export PATH="%s:$PATH"\n' "$target"
    echo "   Then run source ~/.zshrc (or source ~/.bashrc) and retry."
    return 1
}

# ==============================================================================
# Main flow.
# Wrapped in a function so it can exit early with return: when sourced it only
# ends this function instead of killing the caller's shell; when executed the
# script simply ends after the function returns.
# ==============================================================================
main() {
    # 1. Check whether help should be shown
    if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
        show_install_help
        return 0
    fi

    # 1. Determine the target install dir (use the script arg, else ~/.local/bin)
    local TARGET_DIR="${1:-$HOME/.local/bin}"

    # POSIX sh does not expand ~ inside a variable value; expand "~" and "~/..." manually
    case "$TARGET_DIR" in
        "~")   TARGET_DIR=$HOME ;;
        "~/"*) TARGET_DIR=$HOME/${TARGET_DIR#\~/} ;;
    esac

    # Convert to an absolute path so internal lookups do not fail on relative paths
    if [ ! -d "$TARGET_DIR" ]; then
        printf '\033[1;33m⚠️  Note: target install dir [ %s ] does not exist yet.\033[0m\n' "$TARGET_DIR"
        # Prefer reading from the terminal (works with piped installs like curl ... | sh);
        # if there is no terminal (e.g. CI), create the directory by default.
        printf 'Create it automatically and continue installing? [y/N]: '
        CONFIRM=""
        read CONFIRM 2>/dev/null < /dev/tty || CONFIRM="y"
        case "$CONFIRM" in
            [yY]|[yY][eE][sS])
                echo "  📂 Creating directory: $TARGET_DIR"
                mkdir -p "$TARGET_DIR"
                ;;
            *)
                echo "❌ Cancelled by user; installer exited safely."
                return 0
                ;;
        esac
    fi
    TARGET_DIR=$(cd "$TARGET_DIR" && pwd)

    echo "🚀 Deploying global multi-platform uv shims into $TARGET_DIR ..."

    # Current OS type (Linux / Darwin)
    local OS_TYPE=$(uname -s)

    # 2. Run the generation logic
    create_python_shim "python"
    create_python_shim "python3"
    create_pip_shim "pip"
    create_pip_shim "pip3"
    create_uvpin_tool

    # Run the PATH check right after deployment; only print the success banner
    # when the check passes, otherwise keep just the warning.
    if check_path_priority "$TARGET_DIR"; then
        echo ""
        echo "=========================================================="
        echo "🎉 Done! The global multi-version Python shims are ready!"
        echo "📂 Install path: $TARGET_DIR"
        echo "💡 To make the new paths effective, run rehash in zsh and hash -r in bash."
        echo "=========================================================="
    fi
}

main "$@"
