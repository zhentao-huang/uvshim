> 中文文档: [zh/README.md](zh/README.md)

# uvshim — Global Python management shims for uv

`uvshim` is a lightweight set of shell shims that route your system's `python` / `python3` / `pip` / `pip3` through [uv](https://github.com/astral-sh/uv), plus a context-aware version pinning tool called `uvpin`.

In a nutshell:

- **One set of commands, globally**: no matter how many Pythons are installed, `python` / `pip` always point to the environment that is correct for the current context.
- **Virtualenv-aware**: if a `.venv` is active, its Python is used directly.
- **Project-aware**: running `uvpin 3.12` inside a project pins that version for the project only.
- **Loop-safe**: the shims remove their own directory from `PATH` before calling uv, so uv's Python probing never hits the shims again.

---

## Table of Contents

- [The multi-Python dilemma](#the-multi-python-dilemma)
- [How It Works](#how-it-works)
- [Requirements](#requirements)
- [Installation](#installation)
- [Usage](#usage)
  - [python / python3](#python--python3)
  - [pip / pip3](#pip--pip3)
  - [uvpin](#uvpin)
- [pip Backends](#pip-backends)
- [Uninstall](#uninstall)
- [FAQ](#faq)

---

## The multi-Python dilemma

Managing several Python versions sounds simple until you actually try. Do any of these sound familiar?

- Is there one unified, comprehensive tool to manage all the Pythons?
  - `uv` or `pyenv` — which should I use?
  - `uv-python-shims`, `pipx`, plain `uv`… each seems to solve only part of it. How do they fit together?
  - Why does none of them handle the OS, Homebrew, and uv-managed Pythons together?
- Why is installing packages on a single machine so painful?
  - On Ubuntu, why does the system Python tell me to use `apt install python3-*` instead of `pip`?
  - I installed `python3-pip`, yet `pip install` still refuses with `externally-managed-environment`. Why?
  - Why does only `python -m pip install` work, while `pip install` does not?
  - `pip install` succeeded, so why can't I `import` the package (it went to some other environment)?
- Why does everything behave differently once you switch Python versions?
  - On macOS, why does `uv pip install` still land in the same Homebrew directory after I switch Python?
  - When switching between Python versions, why can I `pip install` into some but not others?
  - Why can `which python3` disagree with the Python that actually runs?
- Why do the system, project, and per-tool environments keep stepping on each other?
  - I installed with `sudo pip`; why can't my normal user use it?
  - Uninstalling a pip package suddenly broke a system tool — why?
  - Why do I keep seeing "Defaulting to user installation…", installing into `~/.local` instead of the system directory?

## How It Works

The installer deploys these files in the target directory (default `~/.local/bin`):

| File | Role |
| --- | --- |
| `python` / `python3` | Resolve the interpreter with `uv python find` (respects `.python-version`, projects, and virtualenvs) and exec it |
| `pip` / `pip3` | Install via `uv pip` into the effective environment |
| `uvpin` | Context-aware version pinning tool, replacing bare `uv python pin` |
| `_uvshim_resolve` | Internal helper shared by the shims; picks the effective environment |

The `python` and `pip` shims delegate to `_uvshim_resolve`, which prints `<mode> <path>`:

- `venv <dir>` — an activated virtualenv, a project `.venv`, or a **user base venv** (see below);
- `tool <python>` — a uv-managed base Python (not writable): `pip` installs go to `uv tool`;
- `plain <python>` — a non-managed base Python (pyenv / python.org / source build): `pip` uses `python -m pip`.

Resolution order: `VIRTUAL_ENV` → `uv python find` (project `.venv` / `.python-version`) → per-user base venv / tool / plain.

### System-managed Pythons get a user base venv

Distro/Homebrew Pythons are marked externally-managed (PEP 668), so packages cannot be installed into them directly. For those, uvshim creates a **per-user base venv** under:

```
~/.local/share/uvshim/base-venvs/<key>
```

(keyed by the base Python's real path). Packages and tools install there, so the system Python stays untouched. The base venv is created with `--system-site-packages`, so OS-installed Python packages (e.g. Debian's `dist-packages`) remain importable. uv-managed Pythons are not given a base venv; their installs go to `uv tool`.

> The base venv is created on demand (by the shims, and by `uvpin` when you switch Python). It is never "activated" in your shell, so it does not interfere with project virtualenvs: activating a project `.venv` takes precedence, and `deactivate` falls back to the shim (which then uses the base venv).

So as long as the shim directory comes earlier in `PATH`, your usual `python xxx.py` and `pip install xxx` just work.

A project `.venv` is already isolated by design — uvshim does not change that. It simply cooperates: an active venv (or a project `.venv`) takes precedence, and after `deactivate` the shim resumes.

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

After cloning or downloading this repository:

```sh
./install_uvshim.sh [target-dir]
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
  ✅ Deployed: _uvshim_resolve
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
2. **Otherwise** the interpreter is resolved with `uv python find` (which respects a project `.venv` and `.python-version`). If it resolves to a system-managed base Python, its **user base venv** is used (see [How It Works](#how-it-works)).

### pip / pip3

```sh
pip install requests
pip install -r requirements.txt
pip list
pip3 install "flask>=3.0"
```

`pip` is automatically bound to the version behind `python` in the current context, so you never need to write `python -m pip` manually.

`pip` installs via `uv pip` into the effective environment — an activated virtualenv, a project `.venv`, or the per-user base venv for a system Python. For a uv-managed base Python it falls back to `uv tool` (isolated CLI environments). Note that `uv tool` is only for CLI tools; install pure libraries into a venv.

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

## pip Backends

`pip` / `pip3` always install through `uv pip` into the effective environment — an activated virtualenv, a project `.venv`, or the per-user base venv for system Pythons. For a uv-managed base Python (no writable environment) it falls back to `uv tool`. Because `uv pip` binds to an explicit environment, this works on macOS + Homebrew too.

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
🎉 Cleanup complete! Removed 6 uv shim script(s) above.
```

---

## FAQ

**Q: `python` fails with "uvshim: could not resolve a Python interpreter".**

A: The shims need `uv` on `PATH` to resolve an interpreter. Install uv first.

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

A: If `VIRTUAL_ENV` is set, the shim uses that environment's Python directly. A conda environment that does not set `VIRTUAL_ENV` goes through the normal resolution (`uv python find` → base venv / tool / plain).

**Q: How do I isolate dependencies in a project?**

A: Create and activate a virtualenv, then install:

```sh
uv venv
source .venv/bin/activate
pip install <package>
```

**Q: `pip --version` prints a uvshim notice instead of a pip version.**

A: The shim is backed by `uv pip` and does not use the `pip` package, so uvshim intercepts `pip --version` / `-V` and prints a short notice instead of letting `uv pip` error out. Other commands (`pip install`, `pip list`, ...) work normally via `uv pip`.

---

## License

Released under the [MIT License](LICENSE).
