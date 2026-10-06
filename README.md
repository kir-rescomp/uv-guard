# uv-guard

Guard rails for using [uv](https://docs.astral.sh/uv/) virtual environments alongside EasyBuild/Lmod software modules on the BMRC cluster.

uv-guard ensures that, when a uv virtual environment is active, Python packages are loaded from that environment rather than from Python-related modules that have been loaded on the system. It consists of an activation wrapper, an interpreter start-up guard, and an optional site-level Lmod hook.

## The problem

Many EasyBuild modules depend on a Python toolchain. Loading them, directly or as dependencies, modifies the environment in two ways:

- `PATH` gains the module's Python interpreter, for example `Python/3.11.3-GCCcore-12.3.0`.
- `PYTHONPATH` gains the `site-packages` directories of bundle modules such as `SciPy-bundle` and `Python-bundle-PyPI`.

A virtual environment only works because its `bin/` directory is first on `PATH` and its own `site-packages` is searched for packages. Module-provided paths interfere with both, and the outcome depends on the order in which modules are loaded and the environment is activated.

**Module loaded before activation.** The venv's interpreter is used, but `PYTHONPATH` places the module's Python 3.11 packages ahead of the venv's packages. This can produce `ModuleNotFoundError` or `ImportError` for packages that are correctly installed in the venv.

**Module loaded after activation.** The module's interpreter now comes first on `PATH`, so `python` runs Python 3.11 with the module's packages. This frequently succeeds silently with different package versions. For example, with the R module `R/4.5.1-gfbf-2023a-bare-noSciPy` loaded after activating a Python 3.14 venv:

```console
$ python -c "import sys, numpy; print(sys.executable); print(numpy.__version__)"
/apps/eb/el8/2023a/skylake/software/Python/3.11.3-GCCcore-12.3.0/bin/python
1.25.1

$ "$VIRTUAL_ENV/bin/python" -c "import sys, numpy; print(sys.executable); print(numpy.__version__)"
kir_pyguard: removed 8 module-provided search-path entries so that packages are loaded from /path/to/.venv
/path/to/.venv/bin/python
2.5.3
```

## Components

| File | Purpose |
|------|---------|
| `kir-uv-activate.sh` | Defines `uvactivate`, `uvdeactivate` and `uvguard-install`. Cleans module-provided Python search paths, activates the environment, installs the start-up guard and verifies the result. |
| `kir_pyguard.py` | Start-up guard installed into the venv's `site-packages` with a `.pth` file. Runs every time the venv's interpreter starts and removes module-provided entries from `sys.path`. |
| `lmod/SitePackage-venv-hook.lua` | Optional Lmod hook that warns when a Python-related module is loaded while a virtual environment is active. Requires site administrator access. |

