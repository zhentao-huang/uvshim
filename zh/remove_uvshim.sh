#!/bin/sh

# 在单个目录中识别并移除带有独家特征码的垫片。
# （DELETED_COUNT 由 main 以 local 提供，依赖 shell 的动态作用域）
remove_shims_in_dir() {
    local dir=$1
    [ -d "$dir" ] || return
    # 变量声明都带赋值：zsh 的 local 在无赋值时会打印变量值（TYPESET_SILENT 默认关闭）
    local abs_dir=
    abs_dir=$(cd "$dir" && pwd) || return
    local name= file_path=
    # 直接列出文件名，避免依赖未加引号变量的单词拆分（zsh 默认不拆分）
    for name in python python3 pip pip3 uvpin; do
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
    local DELETED_COUNT=0

    echo "🔍 开始扫描系统环境与目标目录，寻找专属 uv 垫片..."

    # 1. 优先处理用户传入的参数路径
    # POSIX sh 不会对变量值里的 ~ 做展开，这里手动展开 "~" 与 "~/..."
    local ARG_DIR=$1
    case "$ARG_DIR" in
        "~")   ARG_DIR=$HOME ;;
        "~/"*) ARG_DIR=$HOME/${ARG_DIR#\~/} ;;
    esac
    if [ -n "$ARG_DIR" ] && [ -d "$ARG_DIR" ]; then
        remove_shims_in_dir "$ARG_DIR"
    fi

    # 2. 解析全局 PATH（手动按冒号切分：兼容 zsh 默认不对未加引号的变量做单词拆分）
    local rest=$PATH p=
    while [ -n "$rest" ]; do
        case "$rest" in
            *:*) p=${rest%%:*}; rest=${rest#*:} ;;
            *)   p=$rest; rest= ;;
        esac
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
