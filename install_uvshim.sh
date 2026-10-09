#!/usr/bin/env bash

# 1. 确定目标安装目录 (优先读取脚本参数，若无则默认使用 ~/.local/bin)
TARGET_DIR="${1:-$HOME/.local/bin}"

# 将路径转换为绝对路径，避免相对路径导致脚本内部定位失败
mkdir -p "$TARGET_DIR"
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

# 1. 获取当前脚本所在的目录
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

# 2. 精确调用旁边已经打好「防死循环补丁」的 python 垫片
# 通过 python -m pip 调用，完美继承目录 pin 的所有多版本切换逻辑，且不惧 Homebrew 干扰
exec "$SCRIPT_DIR/python" -m pip "$@"
EOF

    chmod +x "$file_path"
    echo "  ✅ 已成功部署: $name"
}

# 4. 执行生成逻辑
create_python_shim "python"
create_python_shim "python3"
create_pip_shim "pip"
create_pip_shim "pip3"

echo "=========================================================="
echo "🎉 恭喜！全平台多版本 Python 全局管理垫片已部署就绪！"
echo "📂 安装路径: $TARGET_DIR"
echo "💡 请确保该路径已加入到你的系统 PATH 环境变量最前列（如 ~/.zshrc 或 ~/.bashrc）"
echo "   示例: export PATH=\"$TARGET_DIR:\$PATH\""
echo "=========================================================="
