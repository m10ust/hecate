"""Locate the engine and fixtures regardless of tree layout.

The development tree nests the plugin under io.github.m10ust.hecate/; the
published tree puts the plugin at the repository root. Tests must work in both,
so they ask this module instead of assuming a depth.
"""
from pathlib import Path

_HERE = Path(__file__).resolve().parent


def _find(rel: str) -> Path | None:
    """Search this directory and its parents for a relative path."""
    for base in [_HERE, *_HERE.parents]:
        cand = base / rel
        if cand.exists():
            return cand
    return None


ENGINE_DIR = None
for _rel in ("engine", "io.github.m10ust.hecate/engine"):
    _hit = _find(_rel)
    if _hit and (_hit / "hecate.py").is_file():
        ENGINE_DIR = _hit
        break

ENGINE_PY = (ENGINE_DIR / "hecate.py") if ENGINE_DIR else None

FIXTURES = None
for _rel in ("fixtures", "tools/fixtures"):
    _hit = _find(_rel)
    if _hit and _hit.is_dir():
        FIXTURES = _hit
        break
