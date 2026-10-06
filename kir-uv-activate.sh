# kir-uv-activate.sh
#
# Source this file (for example from the KIR-utils module) to define:
#   uvactivate [VENV_DIR]     activate a uv virtual environment with isolation checks
#   uvdeactivate              deactivate and restore the saved environment
#   uvguard-install [VENV]    install the Python start-up guard into a venv
#
# Configuration:
#   KIR_UV_MODE   isolate (default)  remove module-provided Python search paths
#                 unload             additionally unload EasyBuild Python modules
#   KIR_UV_GUARD  1 (default) install kir_pyguard if missing; 0 to skip
#
# In job scripts:  uvactivate /path/to/.venv || exit 1

_KIR_UV_GUARD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

_kir_uv_msg() { printf 'uvactivate: %s\n' "$*" >&2; }

# Loaded modules that provide or extend an EasyBuild Python.
_kir_uv_python_modules() {
    local m mods=()
    IFS=: read -ra mods <<< "${LOADEDMODULES:-}"
    for m in "${mods[@]}"; do
        case "$m" in
            Python/*|Python-bundle-PyPI/*|SciPy-bundle/*) printf '%s\n' "$m" ;;
        esac
    done
}

# Remove PYTHONPATH entries that lie under an EasyBuild installation root,
# keeping any entries the user has added deliberately.
_kir_uv_filter_pythonpath() {
    [[ -n "${PYTHONPATH:-}" ]] || return 0
    local v entry root parts=() keep=() roots=() removed=0
    for v in $(compgen -v EBROOT); do roots+=("${!v}"); done
    IFS=: read -ra parts <<< "$PYTHONPATH"
    for entry in "${parts[@]}"; do
        [[ -z "$entry" ]] && continue
        for root in "${roots[@]}"; do
            if [[ -n "$root" && ( "$entry" == "$root" || "$entry" == "$root"/* ) ]]; then
                removed=$((removed + 1)); continue 2
            fi
        done
        keep+=("$entry")
    done
    (( removed )) && _kir_uv_msg "removed $removed module-provided PYTHONPATH entries"
    if (( ${#keep[@]} )); then
        local IFS=:
        export PYTHONPATH="${keep[*]}"
    else
        unset PYTHONPATH
    fi
}

_kir_uv_verify() {
    local venv="$1" status=0 name resolved bindir
    bindir="$(cd "$venv/bin" && pwd -P)"
    for name in python python3; do
        resolved="$(command -v "$name" 2>/dev/null)"
        if [[ -z "$resolved" || "$(cd "$(dirname "$resolved")" && pwd -P)" != "$bindir" ]]; then
            _kir_uv_msg "WARNING: '$name' resolves to ${resolved:-nothing}, not $venv/bin/$name"
            status=1
        fi
    done
    python - "$venv" <<'EOF' || status=1
import os, sys
venv = os.path.realpath(sys.argv[1])
if os.path.realpath(sys.prefix) != venv:
    sys.exit(f"uvactivate: WARNING: sys.prefix is {sys.prefix}, expected {venv}")
EOF
    if (( status == 0 )); then
        _kir_uv_msg "OK: $(python -c 'import sys; print(sys.executable, sys.version.split()[0])')"
    fi
    return $status
}

uvguard-install() {
    local venv="${1:-${VIRTUAL_ENV:-.venv}}" site
    site="$(env -u PYTHONPATH -u PYTHONHOME "$venv/bin/python" -c \
        'import sysconfig; print(sysconfig.get_paths()["purelib"])')" || return 1
    if [[ -f "$site/kir_pyguard.pth" ]] && cmp -s "$_KIR_UV_GUARD_DIR/kir_pyguard.py" "$site/kir_pyguard.py"; then
        return 0
    fi
    cp "$_KIR_UV_GUARD_DIR/kir_pyguard.py" "$site/kir_pyguard.py" &&
        printf 'import kir_pyguard\n' > "$site/kir_pyguard.pth" &&
        _kir_uv_msg "installed start-up guard in $site"
}

uvactivate() {
    local venv="${1:-.venv}" mode="${KIR_UV_MODE:-isolate}" v m
    if [[ -n "${VIRTUAL_ENV:-}" ]]; then
        _kir_uv_msg "an environment is already active ($VIRTUAL_ENV); run uvdeactivate first"
        return 1
    fi
    venv="$(cd "$venv" 2>/dev/null && pwd)" || { _kir_uv_msg "directory not found: ${1:-.venv}"; return 1; }
    if [[ ! -f "$venv/pyvenv.cfg" || ! -f "$venv/bin/activate" ]]; then
        _kir_uv_msg "$venv is not a virtual environment"
        return 1
    fi

    # 1. Optionally unload EasyBuild Python modules, recording them for uvdeactivate.
    _KIR_UV_UNLOADED=""
    if [[ "$mode" == unload ]]; then
        for m in $(_kir_uv_python_modules); do
            module unload "$m" && _KIR_UV_UNLOADED+="$m "
        done
        [[ -n "$_KIR_UV_UNLOADED" ]] && _kir_uv_msg "unloaded: $_KIR_UV_UNLOADED"
    fi

    # 2. Save, then clean, the variables that alter Python's search path.
    for v in PYTHONPATH PYTHONHOME EBPYTHONPREFIXES; do
        [[ -n "${!v+x}" ]] && export "_KIR_UV_SAVED_$v=${!v}"
    done
    _kir_uv_filter_pythonpath
    [[ -n "${PYTHONHOME+x}" ]] && { unset PYTHONHOME; _kir_uv_msg "cleared PYTHONHOME"; }
    [[ -n "${EBPYTHONPREFIXES+x}" ]] && { unset EBPYTHONPREFIXES; _kir_uv_msg "cleared EBPYTHONPREFIXES"; }

    # 3. Activate, install the start-up guard, and verify.
    # shellcheck disable=SC1091
    source "$venv/bin/activate" || return 1
    hash -r
    [[ "${KIR_UV_GUARD:-1}" == 1 ]] && uvguard-install "$venv"
    _kir_uv_verify "$venv"
}

uvdeactivate() {
    local v saved
    declare -F deactivate >/dev/null && deactivate
    for v in PYTHONPATH PYTHONHOME EBPYTHONPREFIXES; do
        saved="_KIR_UV_SAVED_$v"
        if [[ -n "${!saved+x}" ]]; then
            export "$v=${!saved}"
            unset "$saved"
        fi
    done
    if [[ -n "${_KIR_UV_UNLOADED:-}" ]]; then
        # shellcheck disable=SC2086
        module load $_KIR_UV_UNLOADED
    fi
    unset _KIR_UV_UNLOADED
    hash -r
}
