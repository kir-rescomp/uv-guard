# uv-guard

Guard rails for using [uv](https://docs.astral.sh/uv/) virtual environments alongside EasyBuild/Lmod software modules on the BMRC cluster.

uv-guard ensures that, when a uv virtual environment is active, Python packages are loaded from that environment rather than from Python-related modules that have been loaded on the system. It consists of an activation wrapper, an interpreter start-up guard, and an optional site-level Lmod hook.

