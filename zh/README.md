# uvshim —— uv 全局 Python 管理垫片

> 英文文档: [../README.md](../README.md)

`uvshim` 是一套轻量的 Shell 垫片（Shims），把系统里的 `python` / `python3` / `pip` / `pip3` 全部路由到 [uv](https://github.com/astral-sh/uv)，并额外提供一个环境感知的版本锁定工具 `uvpin`。

一句话概括它的价值：

- **全局只需要一套命令**：无论系统里装了几个 Python，`python` / `pip` 永远指向当前上下文正确的环境。
- **自动感知虚拟环境**：激活了 `.venv` 就直接用 venv 里的 Python。
- **自动感知项目目录**：在项目里执行 `uvpin 3.12` 就只给该项目锁定版本，互不干扰。
- **防死循环**：垫片调用 uv 时会从 `PATH` 中剔除自身目录，避免 uv 探测 `python` 时再次命中垫片。

---

## 目录

- [多版本 Python 的困局](#多版本-python-的困局)
- [原理和设计](#原理和设计)
- [前置要求](#前置要求)
- [安装](#安装)
- [使用方法](#使用方法)
  - [python / python3](#python--python3)
  - [pip / pip3](#pip--pip3)
  - [uvpin](#uvpin)
- [pip 后端](#pip-后端)
- [卸载](#卸载)
- [常见问题](#常见问题)

---

## 多版本 Python 的困局

多版本 Python 管理，听起来简单，实操却处处是坑。下面这些问题，你是否也遇到过？

- 有没有一个统一、全面的多版本 Python 管理工具？
  - `uv` 和 `pyenv` 我该选哪个？
  - `uv-python-shims`、`pipx`、裸用 `uv`…… 好像每个都只解决一部分，到底怎么组合？
  - 为什么它们都不能同时管好系统自带、第三方（Homebrew）、以及 uv 托管的 Python？
- 为什么在一台机器上「装包」这么麻烦？
  - Ubuntu 上系统自带的 Python，为什么官方让我用 `apt install python3-*` 装库，而不是 `pip`？
  - 照着装了 `python3-pip`，为什么 `pip install` 还是被拒绝、总弹 `externally-managed-environment`？
  - 为什么有时候只有 `python -m pip install` 能装，而 `pip install` 就是不行？
  - `pip install` 明明成功了，为什么 `import` 却找不到（包被装到了别的环境）？
- 为什么切换 Python 版本之后，行为就不一致了？
  - macOS 上，为什么我切换了 Python 版本，`uv pip install` 仍然装进 Homebrew 的同一个目录？
  - 在多个 Python 版本之间切换时，为什么有的能 `pip` 装、有的不能？
  - 为什么 `which python3` 显示的，和命令实际执行的，可能不是同一个？
- 为什么系统、项目、各类工具的环境总是互相干扰？
  - 用 `sudo pip` 装完，普通用户为什么又用不了？
  - 卸载某个 pip 包后，系统里的工具怎么突然坏了？
  - 为什么常看到 "Defaulting to user installation…"，装到了 `~/.local` 而不是系统目录？

## 原理和设计

### 为什么用 uv —— 而不是只用 pyenv？

uv 是一套现代、基于 Rust 的 Python 工具链。相比 pyenv，它明显更先进：

- **快。** uv 安装预编译的 CPython，几秒完成；pyenv 要从源码编译每个 Python，慢，还依赖 C 工具链。
- **一站式。** uv 还覆盖虚拟环境、包管理等；pyenv 只管解释器。
- **各平台行为一致。** Linux / macOS / Windows 表现相同。

但 uv 有一个关键缺口：**它没有 pyenv 垫片那样的、全局且上下文感知的 `python` / `pip`。**

两者都不完美。于是我们以 uv 为基础来补全它的功能，本工具由此而生。

### PEP 668 与「受管理」的环境

现代的基础 Python 都受 [PEP 668](https://peps.python.org/pep-0668/) 保护：它们带 `EXTERNALLY-MANAGED` 标记，安装器除非被显式强制，否则拒绝改动。这覆盖：

- **Ubuntu 系统自带的 Python**——由 `apt` 管理。系统本身依赖 Python，若让 pip 随意改动，可能破坏系统工具，所以安装是受限的。
- **Homebrew 的 Python**——同样标记为受管理。
- **uv 托管的 Python**——也一样。

出于同样的安全考虑，Ubuntu 把 Python 库做成系统包（`apt install python3-*`），而不是放任 pip；`python3-pip` 也并非为系统 Python 服务——它主要用于虚拟环境，默认不安装，即便装了，往系统里装包仍会被拦。

再叠加 `PATH` 上并存多个 `python` 与 `pip`（系统、Homebrew、uv、venv），问题就更复杂：先被搜索到的 `python` 与先被搜索到的 `pip` 可能根本不是一套，包被装进了运行中的 Python 从不 import 的环境。

这正是uvshim要解决的痛点。uvshim产生的**pip垫片**，一律采用`uv pip`来安装包，避免了pip模块存不存在的问题。

### 为什么切换版本后行为不一致

由于 PEP 668 的存在，每个 Python 安装都各不相同：有的必须被保护，有的需要能被扩展。而现有工具各有短板：

- **pyenv 的垫片**能切换解释器，却完全不处理这个问题。
- **pipx / `uv tool`**能安装隔离的 CLI 工具，却无法安装纯库。
- **uv**可以只用它自己托管的 Python——但这样要么能管的 Python 太少，要么把系统已有的同版本再装一份，显得冗余。

uvshim 的应对是：为受管的系统 Python 提供一个**基础环境**，它

- 独立于系统那个不可写的环境，不影响系统使用的原生库；
- 又能利用系统环境中已安装的包；
- 同时不影响项目 venv 的隔离。
- 由于是自建的环境，是可写的。也解决了受管理的系统，依赖特别机制来安装工具，或是不能安装纯库的问题。

### 环境为何互相干扰

这个问题通常是环境配置造成的——最常见的是 `PATH` 中目录的先后顺序。uvshim 无法替你修改 shell 配置，所以它做了力所能及的事：在安装时检查垫片目录是否对 `python` / `python3` / `pip` / `pip3` 优先生效，若不是，就给出警告并建议如何调整 `PATH`。

### 工作原理

安装脚本会在目标目录（默认 `~/.local/bin`）部署这些文件：

| 文件 | 作用 |
| --- | --- |
| `python` / `python3` | 用 `uv python find` 解析解释器（尊重 `.python-version`、项目与虚拟环境）并执行 |
| `pip` / `pip3` | 通过 `uv pip` 装进当前生效的环境 |
| `uvpin` | 环境感知的版本锁定工具，替代裸用 `uv python pin` |
| `_uvshim_resolve` | 各垫片共用的内部辅助脚本，负责判定生效环境 |

`python`、`pip` 垫片都委托给 `_uvshim_resolve`，它输出 `<模式> <路径>`：

- `venv <dir>`：已激活的虚拟环境、项目 `.venv`，或**用户级 base venv**（见下）；
- `tool <python>`：uv 托管的 base python（不可写），`pip` 安装走 `uv tool`；
- `plain <python>`：非 managed 的 base python（pyenv / 官方安装 / 自编译），`pip` 用 `python -m pip`。

解析顺序：`VIRTUAL_ENV` → `uv python find`（项目 `.venv` / `.python-version`）→ 用户 base venv / tool / plain。

### 系统 managed 的 python 会获得用户级 base venv

发行版/Homebrew 的 python 带外部管理标记（PEP 668），无法直接装包。为此 uvshim 会为它创建**用户级 base venv**，位于：

```
~/.local/share/uvshim/base-venvs/<key>
```

（`<key>` 由 base python 的真实路径得到）。包和工具都装进它，系统 python 不受影响。base venv 以 `--system-site-packages` 创建，因此系统安装的 Python 包（如 Debian 的 `dist-packages`）仍可 import。uv 托管的 python 不建 base venv，其安装走 `uv tool`。

> base venv 按需创建（由垫片创建，切换 python 时 `uvpin` 也会创建）。它**不会**在 shell 里被激活，因此不与项目虚拟环境冲突：项目 `.venv` 激活时优先，`deactivate` 后回落到垫片（进而用 base venv）。

因此，只要垫片目录排在 `PATH` 前面，你平常写的 `python xxx.py`、`pip install xxx` 就能直接工作。

项目 `.venv` 天生就是隔离的，uvshim 不去改变它，只是与之协作：激活（或项目 `.venv`）时优先，`deactivate` 之后垫片恢复接管。

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

克隆或下载本仓库后：

```sh
./install_uvshim.sh [目标目录]
```

- `[目标目录]` 可选，默认 `~/.local/bin`。
- 目标目录不存在时会询问是否自动创建。
- 查看帮助：

```sh
./install_uvshim.sh --help
```

安装成功后会看到：

```
✅ 已成功部署: _uvshim_resolve
✅ 已成功部署: python
✅ 已成功部署: python3
✅ 已成功部署: pip
✅ 已成功部署: pip3
✅ 已成功部署: uvpin

🟢 路径检查: python/python3/pip/pip3 均优先由本垫片接管。

==========================================================
🎉 恭喜！全平台多版本 Python 全局管理垫片已部署就绪！
📂 安装路径: /home/<user>/.local/bin
💡 为确保新路径正常工作，zsh 请执行 `rehash`；bash 请执行 `hash -r`。
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
2. **否则**用 `uv python find` 解析解释器（尊重项目 `.venv` 与 `.python-version`）。若解析到系统 managed 的 base python，则使用它的**用户级 base venv**（见[工作原理](#工作原理)）。

### pip / pip3

```sh
pip install requests
pip install -r requirements.txt
pip list
pip3 install "flask>=3.0"
```

`pip` 会自动绑定到当前上下文里 `python` 所对应的版本，因此你不需要手动写 `python -m pip`。

`pip` 通过 `uv pip` 装进当前生效的环境——已激活的虚拟环境、项目 `.venv`，或系统 python 的用户级 base venv；对 uv 托管的 base python 则回退到 `uv tool`（隔离的 CLI 环境）。注意 `uv tool` 只适合 CLI 工具；纯库请安装到 venv。

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

## pip 后端

`pip` / `pip3` 一律通过 `uv pip` 装进当前生效的环境——已激活的虚拟环境、项目 `.venv`，或系统 python 的用户级 base venv；对 uv 托管的 base python（无可写环境）则回退到 `uv tool`。由于 `uv pip` 绑定的是明确的环境，这在 macOS + Homebrew 下同样可用。

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
🎉 清理完成！成功移除了以上 6 个 uv 垫片脚本。
```

---

## 常见问题

**Q：`python` 执行后报错“uvshim: 无法解析 Python 解释器”？**

A：垫片需要 `uv`（在 `PATH` 上）来解析解释器。请先安装 uv。

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

A：若设置了 `VIRTUAL_ENV`，垫片会直接使用该环境内的 Python。未设置 `VIRTUAL_ENV` 的 conda 环境则走正常解析（`uv python find` → base venv / tool / plain）。

**Q：想在项目里隔离依赖怎么办？**

A：创建并激活虚拟环境后再安装：

```sh
uv venv
source .venv/bin/activate
pip install <package>
```

**Q：`pip --version` 打印的是 uvshim 的提示，而不是 pip 版本号。**

A：本垫片由 `uv pip` 驱动、不使用 pip 包，所以 uvshim 会拦截 `pip --version` / `-V` 并打印一句提示，避免让 `uv pip` 报出难看的错误。其它命令（`pip install`、`pip list` 等）仍通过 `uv pip` 正常工作。

---

## 许可证

本项目基于 [MIT 许可证](../LICENSE) 发布。

