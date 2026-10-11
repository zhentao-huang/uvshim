> 中文文档: [zh/README.md](zh/README.md)

# uvshim — Global Python management shims for uv

`uvshim` is a lightweight set of shell shims that route your system's `python` / `python3` / `pip` / `pip3` through [uv](https://github.com/astral-sh/uv), plus a context-aware version pinning tool called `uvpin`.

In a nutshell:

- **One set of commands, globally**: no matter how many Pythons are installed, `python` / `pip` always point to the uv-managed version that is correct for the current context.
- **Virtualenv-aware**: if a `.venv` is active, its Python is used directly.
- **Project-aware**: running `uvpin 3.12` inside a project pins that version for the project only.
- **Loop-safe**: the shims remove their own directory from `PATH` before calling uv, so uv's Python probing never hits the shims again.

---

## Table of Contents

- [Background and Goals](#background-and-goals)
- [How It Works](#how-it-works)
- [Requirements](#requirements)
- [Installation](#installation)
- [Usage](#usage)
  - [python / python3](#python--python3)
  - [pip / pip3](#pip--pip3)
  - [uvpin](#uvpin)
- [Choosing Between the Two pip Plans](#choosing-between-the-two-pip-plans)
- [Uninstall](#uninstall)
- [FAQ](#faq)

---

## Background and Goals

uv is a powerful Python toolkit covering project management, virtualenvs, and package management, but as of 2026/10/09 it still **lacks global multi-version Python management**.

pyenv uses shims to let users switch Python versions easily; since uv does not offer this officially, third-party projects such as `uv-python-shims` have appeared — they may be more mature, and are worth considering. This project takes a slightly different but broadly similar approach.

Building shims looks easy, yet a few pitfalls need handling:

- **Cross-platform consistency**: mainly Linux vs macOS; making shims behave identically is non-trivial.
- **Coexisting with system Python**: systems ship their own Python and users may install more; folding all of them into uv's version management is not easy.
- **venv and global side by side**: a project may use a virtualenv or the global environment; the shims must handle both.
- **Where to put the shims**: `/usr/bin`, `/usr/local/bin`, or the user's home directory? The user should have full freedom of choice.
- **The pip-to-python binding problem**: native pip is a separate program and, when misconfigured, easily drifts out of sync with the main Python, which is painful to manage.
  - It is also stable but slow; can the faster `uv pip` replace it? See [Choosing Between the Two pip Plans](#choosing-between-the-two-pip-plans).

This project solves all of the above with a **simple, good-enough** design. Questions and discussion are welcome.

## How It Works

The installer generates 5 executable scripts in the target directory (default `~/.local/bin`):

| Shim | Role |
| --- | --- |
| `python` / `python3` | Smart routing: use the venv Python if a virtualenv is active, otherwise `uv run python` |
| `pip` / `pip3` | Dynamically bound to the version behind the current `python`, forwarding install requests |
| `uvpin` | Context-aware version pinning tool, replacing bare `uv python pin` |

Core logic of the `python` shim:

```sh
if [ -n "$VIRTUAL_ENV" ]; then
    exec "$VIRTUAL_ENV/bin/python" "$@"   # 1. virtualenv takes priority
fi
# 2. find the real uv
# 3. remove the shim directory from PATH (loop safety)
# 4. run uv run python with the cleaned PATH
PATH="$CLEANED_PATH" exec "$REAL_UV" run python "$@"
```

So as long as the shim directory comes earlier in `PATH`, your usual `python xxx.py` and `pip install xxx` automatically go through uv.

---

## Requirements

- **uv installed**, and callable from the command line (`command -v uv`).
  - Official install guide: <https://docs.astral.sh/uv/getting-started/installation/>
- Shell: any
- System: Linux / macOS

---

## Installation

### One-line install (from GitHub)

Installs to `~/.local/bin` by default:

```sh
curl -fsSL https://raw.githubusercontent.com/zhentao-huang/uvshim/main/install_uvshim.sh | sh
```

### Install from the local scripts

After cloning or downloading this repository, pick one of the two installers; they are used the same way:

```sh
# Plan A: pip uses native python -m pip (best compatibility)
./install_uvshim.sh [target-dir]

# Plan B: pip forwards directly to uv pip (faster)
./install_uvshim_w_uvpip.sh [target-dir]
```

- `[target-dir]` is optional and defaults to `~/.local/bin`.
- If the target dir does not exist, you are asked whether to create it.
- Show help:

```sh
./install_uvshim.sh --help
```

On success you will see:

```
🚀 Deploying global multi-platform uv shims into /home/<user>/.local/bin ...
  ✅ Deployed: python
  ✅ Deployed: python3
  ✅ Deployed: pip
  ✅ Deployed: pip3
  ✅ Deployed: uvpin

🟢 PATH check: python/python3/pip/pip3 are all handled by these shims first.

==========================================================
🎉 Done! The global multi-version Python shims are ready!
📂 Install path: /home/<user>/.local/bin
💡 To make the new paths effective, run `rehash` in zsh and `hash -r` in bash.
==========================================================
```

If the PATH check fails (the install dir does not take effect), a warning is printed instead — with hints on how to fix `PATH` — and the success banner above is not shown.

---

## Usage

### python / python3

Use them as usual:

```sh
python --version
python script.py
python -m http.server
python3 script.py
```

Rules:

1. **With an active virtualenv**, the environment's Python is used directly (`$VIRTUAL_ENV/bin/python`).
2. **Without a virtualenv**, `uv run python` is used, and uv picks the Python according to the version pinned for the current directory.

### pip / pip3

```sh
pip install requests
pip install -r requirements.txt
pip list
pip3 install "flask>=3.0"
```

`pip` is automatically bound to the version behind `python` in the current context, so you never need to write `python -m pip` manually.

If the resolved Python has no `pip` module (some system Pythons ship without it), the shim falls back to a standalone `pip` / `pip3` found elsewhere in `PATH`.

> Note: in shim mode it is **not** recommended to install into the system/uv global environment from an arbitrary directory. To isolate dependencies per project, create a virtualenv first:
>
> ```sh
> uv venv
> source .venv/bin/activate
> pip install requests      # installs into this venv once activated
> ```

### uvpin

`uvpin` pins or queries the Python version for the current context in a single command, replacing the manual directory juggling of `uv python pin`.

```sh
uvpin                # show the effective Python version and its source
uvpin 3.12           # smartly pin the current context to 3.12
uvpin --help         # show help
```

**Smart write priority (`uvpin <version>`):**

| Case | Condition | Written to |
| --- | --- | --- |
| 1. Project directory | walking up finds a directory containing `.python-version`, `pyproject.toml`, or `.venv` (and it is not the home dir) | local `.python-version` at the project root |
| 2. Legacy home file | `~/.python-version` exists | overwritten in place |
| 3. Plain global | none of the above | `~/.config/uv/.python-version` (`uv python pin --global`) |

Example:

```sh
# inside a project
cd ~/projects/myapp
uvpin 3.12
# 📂 Project directory detected; pinning version 3.12 for this project...
# creates ~/projects/myapp/.python-version

# query
uvpin
# 📌 Project-pinned version: 3.12
```

The uvpin query classifies the context into three kinds:

- `project`: inside a project dir; shows the project-pinned version (or says none is pinned yet).
- `home_legacy`: controlled by a legacy `~/.python-version` in the home dir.
- `global`: the central config; shows the global default version (or says it is not initialized).

---

## Choosing Between the Two pip Plans

| | Plan A: `install_uvshim.sh` | Plan B: `install_uvshim_w_uvpip.sh` |
| --- | --- | --- |
| pip implementation | `exec "$SCRIPT_DIR/python" -m pip "$@"` | `exec "$REAL_UV" pip "$@"` |
| Speed | normal | faster (native uv resolution) |
| Version-switching logic | fully inherits the `python` shim's directory pin | relies on `uv pip`'s own environment resolution |
| macOS + Homebrew | ✅ works | ⚠️ may fail to install into the target Python version |
| Recommended for | compatibility first | Linux, when install speed matters |

> On **macOS + Homebrew + uv**, Plan B's `pip` may not install into the directory of the specified Python version. If you hit this, switch to Plan A (`install_uvshim.sh`).

---

## Uninstall

Use `remove_uvshim.sh` to clean up automatically:

```sh
# scan all directories in PATH
./remove_uvshim.sh

# or target a specific directory
./remove_uvshim.sh ~/.local/bin
```

You can also run it straight from GitHub (scans PATH automatically):

```sh
curl -fsSL https://raw.githubusercontent.com/zhentao-huang/uvshim/main/remove_uvshim.sh | sh
```

The script identifies its own shims precisely by the unique marker `[UV-SHIMS-MARKER]` in each file, so it **never deletes** native `python` / `pip` or other system files.

Example output:

```
🗑️ Found and removed shim: /home/user/.local/bin/python
...
🎉 Cleanup complete! Removed 5 uv shim script(s) above.
```

---

## FAQ

**Q: `python` fails with "uv not found in the system or current directory".**

A: Install uv first.

```sh
command -v uv   # should print the path to uv
```

**Q: `which python` still points to the system Python.**

A: The shim directory is not early enough in `PATH`. Check the order in `~/.zshrc` / `~/.bashrc` and make sure `export PATH="<shim-dir>:$PATH"` comes before other Python-related paths, then `source` the file again.

**Q: After installing, `which python3` (or actual execution) still points to an old path like `/opt/homebrew/bin/python3`, even though the shim exists?**

A: This is the shell's **command hash** at work, not a `PATH` ordering problem. `~/.local/bin` was already in `PATH`, but the shims were just added; the shell had already cached `python3` as the old path, and adding files to a directory that is already in `PATH` does not trigger a rescan. Run `rehash` (zsh) or `hash -r` (bash), or simply open a new terminal.

> Note: bash's `which` is usually an external program that scans `PATH` directly, so it may show the new path while **actual execution** still uses the cached old command; zsh's `which` is builtin and reads the cache, so it shows the old path directly. Both are fixed by the commands above.

**Q: Will it clash with the system Python or delete system files?**

A: No. The shims are just standalone shell scripts, and the uninstaller only deletes files carrying the `[UV-SHIMS-MARKER]` marker.

**Q: What happens if a virtualenv / conda is already active?**

A: If `VIRTUAL_ENV` is set, the `python` shim calls that environment's Python directly, bypassing uv. A conda environment that does not set `VIRTUAL_ENV` is handled by the normal logic and passed to uv.

**Q: How do I isolate dependencies in a project?**

A: Create and activate a virtualenv, then install:

```sh
uv venv
source .venv/bin/activate
pip install <package>
```

**Q: With Plan B, `pip --version` fails with `error: unexpected argument '--version' found`.**

A: This is expected with Plan B (`install_uvshim_w_uvpip.sh`). The shim forwards `pip` straight to `uv pip`, and `uv pip` does not support the `--version` option, so it errors; this does not affect `pip install` and other commands.

To avoid the error, switch to Plan A (`install_uvshim.sh`), whose `pip` goes through `python -m pip` and supports `--version`.

---

## License

Released under the [MIT License](LICENSE).
