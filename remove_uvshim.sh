#!/usr/bin/env bash

# 1. 收集所有可能包含垫片的候选目录
# 优先读取用户传入的参数路径，同时合并当前系统的 PATH 路径（去重处理）
declare -A UNIQUE_DIRS
if [ -n "$1" ] && [ -d "$1" ]; then
    ABS_PARAM_DIR=$(cd "$1" && pwd)
    UNIQUE_DIRS["$ABS_PARAM_DIR"]=1
fi

# 拆分并解析全局 PATH
IFS=':' read -r -a path_array <<< "$PATH"
for p in "${path_array[@]}"; do
    if [ -d "$p" ]; then
        ABS_P=$(cd "$p" && pwd)
        UNIQUE_DIRS["$ABS_P"]=1
    fi
done

echo "🔍 开始扫描系统环境与目标目录，寻找专属 uv 垫片..."

# 定义我们要清理的目标文件名列表
SHIM_NAMES=("python" "python3" "pip" "pip3" "uvpin")
DELETED_COUNT=0

# 2. 遍历所有目录并精准识别特征码
for dir in "${!UNIQUE_DIRS[@]}"; do
    for name in "${SHIM_NAMES[@]}"; do
        file_path="$dir/$name"
        
        # 必须是常规文件且可读
        if [ -f "$file_path" ] && [ -r "$file_path" ]; then
            # 精准检测我们留下的独家特征码
            if grep -q "\[UV-SHIMS-MARKER\]" "$file_path"; then
                echo "  🗑️ 发现并移除垫片: $file_path"
                rm "$file_path"
                ((DELETED_COUNT++))
            fi
        fi
    done
done

# 3. 打印清理结果
echo "=========================================================="
if [ $DELETED_COUNT -gt 0 ]; then
    echo "🎉 清理完成！成功移除了以上 $DELETED_COUNT 个 uv 垫片脚本。"
else
    echo "👍 未在你的系统 PATH 或指定目录中检测到任何属于我们的 uv 垫片，未做任何修改。"
fi
echo "=========================================================="
