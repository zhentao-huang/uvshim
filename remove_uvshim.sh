#!/bin/sh

# 在单个目录中识别并移除带有独家特征码的垫片。
# （SHIM_NAMES / DELETED_COUNT 由 main 以 local 提供，依赖 shell 的动态作用域）
remove_shims_in_dir() {
    local dir=$1
    [ -d "$dir" ] || return
    local abs_dir
    abs_dir=$(cd "$dir" && pwd) || return
    local name file_path
    for name in $SHIM_NAMES; do
        file_path="$abs_dir/$name"

        # 必须是常规文件且可读
        if [ -f "$file_path" ] && [ -r "$file_path" ]; then
            # 精准检测我们留下的独家特征码
            if grep -q "\[UV-SHIMS-MARKER\]" "$file_path"; then
                echo "  🗑️ 发现并移除垫片: $file_path"
                rm "$file_path"
                DELETED_COUNT=$((DELETED_COUNT + 1))
            fi
        fi
    done
}

# ==============================================================================
# 主流程。
# 封装成函数后：被 source 时 set -- 与变量都不会污染调用者，
# 也不会因 exit 而杀掉调用者的 shell。
# ==============================================================================
main() {
    # 定义要清理的垫片文件名
    local SHIM_NAMES="python python3 pip pip3 uvpin"
    local DELETED_COUNT=0

    echo "🔍 开始扫描系统环境与目标目录，寻找专属 uv 垫片..."

    # 1. 优先处理用户传入的参数路径
    if [ -n "$1" ] && [ -d "$1" ]; then
        remove_shims_in_dir "$1"
    fi

    # 2. 拆分并解析全局 PATH（以冒号为分隔符逐个目录处理，关闭通配避免路径中含通配符）
    local old_ifs=$IFS
    IFS=':'
    set -f
    set -- $PATH
    set +f
    IFS=$old_ifs
    local p
    for p in "$@"; do
        [ -n "$p" ] && remove_shims_in_dir "$p"
    done

    # 3. 打印清理结果
    echo "=========================================================="
    if [ "$DELETED_COUNT" -gt 0 ]; then
        echo "🎉 清理完成！成功移除了以上 $DELETED_COUNT 个 uv 垫片脚本。"
    else
        echo "👍 未在你的系统 PATH 或指定目录中检测到任何属于我们的 uv 垫片，未做任何修改。"
    fi
    echo "=========================================================="
}

main "$@"
