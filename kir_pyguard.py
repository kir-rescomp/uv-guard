"""Start-up guard for uv virtual environments on a shared EasyBuild/Lmod stack.

Installed into a virtual environment's site-packages together with
``kir_pyguard.pth``, so it runs every time that environment's interpreter
starts, whether interactively, in a Slurm job, or from a workflow manager.

It removes sys.path entries that were injected from outside the environment by
EasyBuild modules, i.e. entries that came from PYTHONPATH or EBPYTHONPREFIXES
and either lie under an EasyBuild installation root (any EBROOT* variable) or
belong to a different Python version (for example .../python3.11/site-packages
when the interpreter is 3.14). Entries a user has placed on PYTHONPATH
deliberately, such as a project's src/ directory, are left in place.

The environment variables themselves are not modified, so subprocesses that use
a different interpreter (for example an R session using reticulate) still see
them.

Environment variables:
    KIR_PYGUARD        strip (default) | warn | off
    KIR_PYGUARD_QUIET  set to 1 to suppress the notice printed in strip mode
"""

import os
import re
import sys

_VERSION_RE = re.compile(r"python(\d+)\.(\d+)")


def _split(value):
    return [os.path.realpath(p) for p in value.split(os.pathsep) if p]


def _under(path, roots):
    return any(path == r or path.startswith(r + os.sep) for r in roots)


def _foreign(path, eb_roots):
    if _under(path, eb_roots):
        return True
    match = _VERSION_RE.search(path)
    return bool(match) and (int(match[1]), int(match[2])) != sys.version_info[:2]


def _run():
    mode = os.environ.get("KIR_PYGUARD", "strip").lower()
    if mode == "off" or sys.prefix == sys.base_prefix:
        return

    injected = set(_split(os.environ.get("PYTHONPATH", "")))
    eb_prefixes = _split(os.environ.get("EBPYTHONPREFIXES", ""))
    if not injected and not eb_prefixes:
        return

    eb_roots = [os.path.realpath(v) for k, v in os.environ.items()
                if k.startswith("EBROOT") and v]

    offending = []
    for entry in sys.path:
        if not entry:
            continue
        real = os.path.realpath(entry)
        if (real in injected and _foreign(real, eb_roots)) or _under(real, eb_prefixes):
            offending.append(entry)

    if not offending:
        return

    listing = "\n  ".join(offending)
    if mode == "warn":
        sys.stderr.write(
            "kir_pyguard: WARNING: these search-path entries come from loaded "
            f"modules and may shadow packages in {sys.prefix}:\n  {listing}\n"
        )
        return

    sys.path[:] = [p for p in sys.path if p not in offending]
    if os.environ.get("KIR_PYGUARD_QUIET") != "1":
        sys.stderr.write(
            f"kir_pyguard: removed {len(offending)} module-provided search-path "
            f"entr{'y' if len(offending) == 1 else 'ies'} so that packages are "
            f"loaded from {sys.prefix}\n"
        )


try:
    _run()
except Exception as exc:  # never prevent the interpreter from starting
    sys.stderr.write(f"kir_pyguard: check skipped ({exc})\n")
