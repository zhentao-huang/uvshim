# uvshim —— uv 全局 Python 管理垫片

> 英文文档: [../README.md](../README.md)

`uvshim` 是一套轻量的 Shell 垫片（Shims），把系统里的 `python` / `python3` / `pip` / `pip3` 全部路由到 [uv](https://github.com/astral-sh/uv)，并额外提供一个环境感知的版本锁定工具 `uvpin`。

一句话概括它的价值：

- **全局只需要一套命令**：无论系统里装了几个 Python，`python` / `pip` 永远指向 uv 托管的、当前上下文正确的版本。
- **自动感知虚拟环境**：激活了 `.venv` 就直接用 venv 里的 Python。
- **自动感知项目目录**：在项目里执行 `uvpin 3.12` 就只给该项目锁定版本，互不干扰。
- **防死循环**：垫片调用 uv 时会从 `PATH` 中剔除自身目录，避免 uv 探测 `python` 时再次命中垫片。

---

## 目录

- [背景与目标问题](#背景与目标问题)
- [工作原理](#工作原理)
- [前置要求](#前置要求)
- [安装](#安装)
- [使用方法](#使用方法)
  - [python / python3](#python--python3)
  - [pip / pip3](#pip--pip3)
  - [uvpin](#uvpin)
- [两种 pip 方案如何选择](#两种-pip-方案如何选择)
- [卸载](#卸载)
- [常见问题](#常见问题)

---

## 背景与目标问题

uv 是一套强大的 Python 工具，集项目管理、虚拟环境、包管理于一身，但截至目前（2026/10/09）仍**缺少全局的多版本 Python 管理能力**。

pyenv 通过垫片（shims）让用户方便地切换各种 Python 版本；uv 官方尚未提供该能力，因此社区里也出现了 `uv-python-shims` 这样的第三方项目，相对本项目可能更成熟，也欢迎大家选用。本项目采用了一种略有不同、但总体思路一致的实现。

实现垫片看似不难，实际却有几个坑需要处理：

- **跨系统一致性**：主要是 Linux 与 macOS，要做到行为相同的垫片有不小的挑战。
- **兼容系统自带 Python**：系统通常自带 Python，用户也可能自行安装，要把这些全部纳入 uv 的版本管理并不容易。
- **venv 与全局并存**：项目可能使用虚拟环境，也可能直接用全局，垫片需要同时兼顾。
- **垫片放在哪里**：`/usr/bin`、`/usr/local/bin` 还是用户目录？使用者应当拥有充分的自主选择权。
- **pip 与 python 的绑定问题**：原生 pip 作为独立程序，配置不当，很容易和 python 主程序脱节，处理起来很麻烦。
  - 另外稳定但性能略低，能否改用性能更好的 `uv pip` 代替？参见[两种 pip 方案如何选择](#两种-pip-方案如何选择)。

本项目以**简单、够用**的功能解决了上述问题，欢迎交流提问。

## 工作原理

安装脚本会在目标目录（默认 `~/.local/bin`）生成 5 个可执行脚本：

| 垫片 | 作用 |
| --- | --- |
| `python` / `python3` | 智能路由：激活了虚拟环境则用 venv 的 Python，否则用 `uv run python` |
| `pip` / `pip3` | 动态绑定当前 `python` 对应的版本，转发安装请求 |
| `uvpin` | 环境感知的版本锁定工具，替代裸用 `uv python pin` |

`python` 垫片的核心逻辑：

```sh
if [ -n "$VIRTUAL_ENV" ]; then
    exec "$VIRTUAL_ENV/bin/python" "$@"   # 1. 虚拟环境优先
fi
# 2. 找到真正的 uv
# 3. 从 PATH 中剔除垫片目录（防死循环）
# 4. 用干净的 PATH 执行 uv run python
PATH="$CLEANED_PATH" exec "$REAL_UV" run python "$@"
```

因此，只要垫片目录排在 `PATH` 前面，你平常写的 `python xxx.py`、`pip install xxx` 就会自动走 uv。

---

## 前置要求

- **已安装 uv**，并确保 `uv` 可以在命令行中调用（`command -v uv`）。
  - 官方安装方式：<https://docs.astral.sh/uv/getting-started/installation/>
- Shell：任意
- 系统：Linux / macOS

---

## 安装

### 一键安装（从 GitHub）

默认安装到 `~/.local/bin`：

```sh
curl -fsSL https://raw.githubusercontent.com/zhentao-huang/uvshim/main/zh/install_uvshim.sh | sh
```

### 本地脚本安装

克隆或下载本仓库后，两个安装脚本二选一，用法完全一致：

```sh
# 方案 A：pip 走原生 python -m pip（兼容性更佳）
./install_uvshim.sh [目标目录]

# 方案 B：pip 直接转发给 uv pip（速度更快）
./install_uvshim_w_uvpip.sh [目标目录]
```

- `[目标目录]` 可选，默认 `~/.local/bin`。
- 目标目录不存在时会询问是否自动创建。
- 查看帮助：

```sh
./install_uvshim.sh --help
```

安装成功后会看到：

```
✅ 已成功部署: python
✅ 已成功部署: python3
✅ 已成功部署: pip
✅ 已成功部署: pip3
✅ 已成功部署: uvpin

🟢 路径检查: python/python3/pip/pip3 均优先由本垫片接管。

==========================================================
🎉 恭喜！全平台多版本 Python 全局管理垫片已部署就绪！
📂 安装路径: /home/<user>/.local/bin
💡 为确保新路径正常工作，zsh 请执行 rehash；bash 请执行 hash -r。
==========================================================
```

若路径检查未通过（安装目录未生效），则会改为输出警告并提示如何调整 `PATH`，此时不再显示上面的祝贺信息。

---

## 使用方法

### python / python3

和平常一样使用即可：

```sh
python --version
python script.py
python -m http.server
python3 script.py
```

行为规则：

1. **有已激活的虚拟环境**时，直接使用该环境内的 Python（`$VIRTUAL_ENV/bin/python`）。
2. **没有虚拟环境**时，交给 `uv run python`，由 uv 按当前目录的版本锁定规则选择 Python。

### pip / pip3

```sh
pip install requests
pip install -r requirements.txt
pip list
pip3 install "flask>=3.0"
```

`pip` 会自动绑定到当前上下文里 `python` 所对应的版本，因此你不需要手动写 `python -m pip`。

### uvpin

`uvpin` 用来在一个命令里智能地锁定/查询当前上下文的 Python 版本，替代需要手动区分目录的 `uv python pin`。

```sh
uvpin                # 查看当前上下文生效的 Python 版本及来源
uvpin 3.12           # 智能锁定当前上下文为 3.12
uvpin --help         # 查看帮助
```

**智能写入优先级（`uvpin <version>`）：**

| 场景 | 判定条件 | 写入位置 |
| --- | --- | --- |
| 1. 项目工程目录 | 向上查找到含 `.python-version`、`pyproject.toml` 或 `.venv` 的目录（且不是家目录） | 项目根目录下的本地 `.python-version` |
| 2. 家目录遗留文件 | `~/.python-version` 存在 | 原地覆盖更新 |
| 3. 纯全局环境 | 以上都不满足 | `~/.config/uv/.python-version`（`uv python pin --global`） |

示例：

```sh
# 在项目里
cd ~/projects/myapp
uvpin 3.12
# 📂 检测到处于项目目录，正在为当前项目锁定版本为 3.12...
# 生成 ~/projects/myapp/.python-version

# 查询
uvpin
# 📌 项目本地锁定的版本为: 3.12
```

`uvpin` 的查询会把上下文分成三类并给出提示：

- `project`：身处项目目录，显示项目锁定版本（或提示尚未锁定）。
- `home_legacy`：受家目录遗留的 `~/.python-version` 控制。
- `global`：全局配置中心，显示全局默认版本（或提示未初始化）。

---

## 两种 pip 方案如何选择

| | 方案 A：`install_uvshim.sh` | 方案 B：`install_uvshim_w_uvpip.sh` |
| --- | --- | --- |
| pip 实现 | `exec "$SCRIPT_DIR/python" -m pip "$@"` | `exec "$REAL_UV" pip "$@"` |
| 速度 | 普通 | 更快（uv 原生解析） |
| 版本切换逻辑 | 完整继承 `python` 垫片的目录 pin | 依赖 `uv pip` 自身的环境解析 |
| macOS + Homebrew | ✅ 正常 | ⚠️ 可能无法装到目标 Python 版本 |
| 推荐场景 | 兼容性优先 | Linux，追求安装速度 |

> 在 **macOS + Homebrew + uv** 的组合下，方案 B 的 `pip` 可能装不到指定 Python 版本的目录里。遇到此问题请改用作方案 A（`install_uvshim.sh`）。

---

## 卸载

使用 `remove_uvshim.sh` 自动清理：

```sh
# 自动扫描 PATH 中的所有目录
./remove_uvshim.sh

# 或指定要清理的目录
./remove_uvshim.sh ~/.local/bin
```

也可直接从 GitHub 运行（自动扫描 PATH）：

```sh
curl -fsSL https://raw.githubusercontent.com/zhentao-huang/uvshim/main/zh/remove_uvshim.sh | sh
```

脚本通过检测每个文件里的独家特征码 `[UV-SHIMS-MARKER]` 来精准识别属于自己的垫片，**不会误删**系统原生的 `python` / `pip` 等文件。

输出示例：

```
🗑️ 发现并移除垫片: /home/user/.local/bin/python
...
🎉 清理完成！成功移除了以上 5 个 uv 垫片脚本。
```

---

## 常见问题

**Q：`python` 执行后报错“未在系统或当前目录中找到 uv”？**

A：请先安装 uv目录。

```sh
command -v uv   # 应能输出 uv 的路径
```

**Q：`which python` 还是指向系统自带的 python？**

A：垫片目录没有排在 `PATH` 前面。请检查 `~/.zshrc` / `~/.bashrc` 中的顺序，确保 `export PATH="<垫片目录>:$PATH"` 位于其他 Python 相关路径之前，并重新 `source`。

**Q：安装后 `which python3`（或实际运行）仍指向 `/opt/homebrew/bin/python3` 等旧路径，但垫片明明已存在？**

A：这是 shell 的**命令哈希缓存**（command hash）导致的，不是 `PATH` 顺序问题。`~/.local/bin` 本就在 `PATH` 中，但垫片是刚放进去的；shell 早已把 `python3` 缓存成旧路径，而向已存在于 `PATH` 的目录里新增文件不会触发重新扫描。执行 `rehash`（zsh）或 `hash -r`（bash），或直接新开一个终端即可。

> 补充：bash 的 `which` 通常是外部程序、会直接扫描 `PATH`，所以它可能显示新路径，但**实际执行**仍会用缓存的旧命令；zsh 的 `which` 是内建、会读缓存，因此直接显示旧路径。两者都用上面的命令解决。

**Q：会不会和系统里的 Python 打架，甚至删掉系统文件？**

A：不会。垫片只是几个独立的 Shell 脚本；卸载脚本仅删除带 `[UV-SHIMS-MARKER]` 特征码的文件。

**Q：已经激活了 virtualenv / conda，会怎样？**

A：若设置了 `VIRTUAL_ENV`，`python` 垫片会直接调用该环境内的 Python，不经过 uv。conda 环境若未设置 `VIRTUAL_ENV`，则按普通逻辑交给 uv 处理。

**Q：想在项目里隔离依赖怎么办？**

A：创建并激活虚拟环境后再安装：

```sh
uv venv
source .venv/bin/activate
pip install <package>
```

**Q：使用方案 B 时执行 `pip --version` 报 `error: unexpected argument '--version' found`，怎么办？**

A：这是使用方案 B（`install_uvshim_w_uvpip.sh`）时的正常现象。垫片把 `pip` 直接转发给了 `uv pip`，而 `uv pip` 本身不支持 `--version` 选项，因此会报错；这不影响 `pip install` 等其他命令的正常使用。

如果想避免此报错，可改用方案 A（`install_uvshim.sh`），它的 `pip` 走 `python -m pip`，支持 `--version`。

