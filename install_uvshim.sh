#!/usr/bin/env bash

# 1. 确定目标安装目录 (优先读取脚本参数，若无则默认使用 ~/.local/bin)
TARGET_DIR="${1:-$HOME/.local/bin}"

# 将路径转换为绝对路径，避免相对路径导致脚本内部定位失败
if [ ! -d "$TARGET_DIR" ]; then
    echo -e "\033[1;33m⚠️  提示: 目标安装目录 [ $TARGET_DIR ] 当前不存在。\033[0m"
    read -p "是否需要自动创建该目录并继续安装？[y/N]: " CONFIRM
    case "$CONFIRM" in
        [yY]|[yY][eE][sS])
            echo "  📂 正在创建目录: $TARGET_DIR"
            mkdir -p "$TARGET_DIR"
            ;;
        *)
            echo "❌ 用户取消操作，安装脚本已安全退出。"
            exit 0
            ;;
    esac
fi
TARGET_DIR=$(cd "$TARGET_DIR" && pwd)

echo "🚀 开始在 $TARGET_DIR 中部署全局多平台兼容 uv 垫片（Shims）..."

# 获取当前系统类型 (Linux / Darwin)
OS_TYPE=$(uname -s)

# 2. 动态生成 python 和 python3 垫片
create_python_shim() {
    local name=$1
    local file_path="$TARGET_DIR/$name"

    # 根据不同操作系统，预设好绝对兼容的 PATH 清洗命令
    local sed_cmd=""
    if [ "$OS_TYPE" = "Darwin" ]; then
        # macOS (BSD sed) 兼容写法
        sed_cmd='CLEANED_PATH=$(echo "$PATH" | sed -E "s#(^|:)$SCRIPT_DIR(:|\$)#:#g; s#^:##; s#:\$##")'
    else
        # Linux (GNU sed) 兼容写法
        sed_cmd='CLEANED_PATH=$(echo "$PATH" | sed -r "s#(^|:)$SCRIPT_DIR(:|\$)#:#g; s#^:##; s#:\$##")'
    fi

    cat << EOF > "$file_path"
#!/bin/sh
# [UV-SHIMS-MARKER] - DO NOT REMOVE THIS LINE
# 1. 如果已经在激活的虚拟环境中，直接执行虚拟环境内的 python
if [ -n "\$VIRTUAL_ENV" ]; then
    exec "\$VIRTUAL_ENV/bin/python" "\$@"
fi

# 2. 获取当前脚本（和 uv）所在的目录
SCRIPT_DIR=\$(cd "\$(dirname "\$0")" && pwd)

# 3. 找到真正的 uv 绝对路径 (优先 command -v，比 which 更跨平台)
REAL_UV="\$SCRIPT_DIR/uv"
if [ ! -x "\$REAL_UV" ]; then
    REAL_UV=\$(command -v uv 2>/dev/null)
fi

if [ -z "\$REAL_UV" ]; then
    echo "❌ 错误: 未在系统或当前目录中找到 uv，请先安装 uv！" >&2
    exit 1
fi

# 4. 从当前的 PATH 中安全移除当前拦截脚本的目录 (防止 uv 内部探测时发生死循环)
$sed_cmd

# 5. 用干净的 PATH 执行 uv run
PATH="\$CLEANED_PATH" exec "\$REAL_UV" run python "\$@"
EOF

    chmod +x "$file_path"
    echo "  ✅ 已成功部署: $name"
}

# 3. 创建 pip 和 pip3 垫片 (升级为方案 B：动态绑定 python 版本，解决 macOS/Homebrew 冲突)
create_pip_shim() {
    local name=$1
    local file_path="$TARGET_DIR/$name"

    cat << 'EOF' > "$file_path"
#!/bin/sh
# [UV-SHIMS-MARKER] - DO NOT REMOVE THIS LINE
# 1. 获取当前脚本所在的目录
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

# 2. 精确调用旁边已经打好「防死循环补丁」的 python 垫片
# 通过 python -m pip 调用，完美继承目录 pin 的所有多版本切换逻辑，且不惧 Homebrew 干扰
exec "$SCRIPT_DIR/python" -m pip "$@"
EOF

    chmod +x "$file_path"
    echo "  ✅ 已成功部署: $name"
}

# 4. 【核心新增】创建智能环境感知 uvpin 脚本
create_uvpin_tool() {
    local file_path="$TARGET_DIR/uvpin"

    cat << 'EOF' > "$file_path"
#!/bin/sh
# [UV-SHIMS-MARKER] - DO NOT REMOVE THIS LINE

show_help() {
    echo "💡 现代化 uv 环境感知版本管理工具 - uvpin"
    echo "--------------------------------------------------------"
    echo "用法:"
    echo "  uvpin                  查看当前上下文生效的 Python 版本"
    echo "  uvpin <version>        智能为当前项目、遗留环境或系统全局锁定 Python 版本"
    echo "  uvpin -h | --help      显示本帮助信息"
    echo ""
    echo "🧠 智能写入优先级逻辑:"
    echo "  1. 项目工程目录内 ➔ 自动在当前项目根目录锁定并生成本地 .python-version"
    echo "  2. 触碰用户根目录 ➔ 原地覆盖更新遗留的 ~/.python-version"
    echo "  3. 纯全局空目录下 ➔ 安全写入核心配置中心 ~/.config/uv/.python-version"
    echo "--------------------------------------------------------"
}

# 处理帮助选项
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    show_help
    exit 0
fi

CURRENT_DIR=$(pwd)
HOME_DIR=$(cd "$HOME" && pwd)

# 递归向上寻找最适合的控制文件或工程根目录
find_active_target() {
    dir="$CURRENT_DIR"
    while [ "$dir" != "/" ]; do
        # 1. 检测项目本地标志
        if [ -f "$dir/.python-version" ] || [ -f "$dir/pyproject.toml" ] || [ -d "$dir/.venv" ]; then
            if [ "$dir" = "$HOME_DIR" ]; then
                break
            fi
            echo "project:$dir"
            return
        fi
        dir=$(dirname "$dir")
    done

    # 2. 检测家目录残留
    if [ -f "$HOME_DIR/.python-version" ]; then
        echo "home_legacy:$HOME_DIR"
        return
    fi

    # 3. 默认全局
    echo "global:$HOME_DIR/.config/uv"
}

TARGET_INFO=$(find_active_target)
TARGET_TYPE=$(echo "$TARGET_INFO" | cut -d':' -f1)
TARGET_PATH=$(echo "$TARGET_INFO" | cut -d':' -f2-)

# 【新增：不带参数时的智能查询功能】
if [ -z "$1" ]; then
    echo "🔍 正在分析当前环境的 Python 调度上下文..."
    case "$TARGET_TYPE" in
        "project")
            if [ -f "$TARGET_PATH/.python-version" ]; then
                echo "📂 当前身处项目目录: $TARGET_PATH"
                echo "📌 项目本地锁定的版本为: $(cat "$TARGET_PATH/.python-version")"
            else
                echo "📂 当前属于项目开发路径 ($TARGET_PATH)，但尚未锁定任何本地 Python 版本。"
                echo "💡 提示: 你可以输入 'uvpin 3.x' 为此项目精确锁定一个版本。"
            fi
            ;;
        "home_legacy")
            echo "⚠️  当前受用户根目录遗留本地文件控制: $TARGET_PATH/.python-version"
            echo "📌 锁定版本为: $(cat "$TARGET_PATH/.python-version")"
            ;;
        "global"|*)
            if [ -f "$HOME_DIR/.config/uv/.python-version" ]; then
                echo "🌍 当前处于全局纯净环境，受核心配置中心控制。"
                echo "📌 全局默认 Python 版本为: $(cat "$HOME_DIR/.config/uv/.python-version")"
            else
                echo "🌍 全局配置中心尚未初始化。当前由系统原装 Python 接管。"
                echo "💡 提示: 你可以输入 'uvpin 3.x' 设置全局默认 Python 版本。"
            fi
            ;;
    esac
    exit 0
fi

# 【带参数时的智能写入功能】
VERSION="$1"
case "$TARGET_TYPE" in
    "project")
        echo "📂 检测到处于项目目录，正在为当前项目锁定版本为 $VERSION..."
        uv python pin "$VERSION"
        ;;
    "home_legacy")
        echo "⚠️  检测到用户根目录存在本地旧版文件，正在原地更新为 $VERSION..."
        (cd "$HOME" && uv python pin "$VERSION")
        ;;
    "global"|*)
        echo "🌍 未检测到特定项目，正在更新全局配置 (~/.config/uv/.python-version) 为 $VERSION..."
        uv python pin --global "$VERSION"
        ;;
esac
EOF
    chmod +x "$file_path"
    echo "  ✅ 已成功部署: uvpin"
}

# 5. 执行生成逻辑
create_python_shim "python"
create_python_shim "python3"
create_pip_shim "pip"
create_pip_shim "pip3"
create_uvpin_tool

echo "=========================================================="
echo "🎉 恭喜！全平台多版本 Python 全局管理垫片已部署就绪！"
echo "📂 安装路径: $TARGET_DIR"
echo "💡 请确保该路径已加入到你的系统 PATH 环境变量最前列（如 ~/.zshrc 或 ~/.bashrc）"
echo "   示例: export PATH=\"$TARGET_DIR:\$PATH\""
echo "=========================================================="
