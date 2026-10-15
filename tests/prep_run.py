#!/usr/bin/env python3
"""Write override and a test secret into a temp run dir. No network."""
import sys
from pathlib import Path

ROOT = Path(sys.argv[1])
sys.path.insert(0, str(ROOT / "lib"))
import merge  # noqa: E402

run = Path(sys.argv[2])
mixed = sys.argv[3]
api = sys.argv[4]
merge.write_defaults(run / "override.yaml", mixed, api)
secret = run / "secret"
secret.write_text("test-secret-value\n", encoding="utf-8")
secret.chmod(0o600)
