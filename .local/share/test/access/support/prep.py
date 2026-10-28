#!/usr/bin/env python3
"""Write override and a test secret into a temp run dir. No network."""
import sys
from pathlib import Path

ROOT = Path(sys.argv[1])
sys.path.insert(0, str(ROOT))
from axs.config import DEFAULT_API, DEFAULT_MIXED  # noqa: E402
from axs.core import write_defaults  # noqa: E402

run = Path(sys.argv[2])
mixed = sys.argv[3] if len(sys.argv) > 3 and sys.argv[3] else DEFAULT_MIXED
api = sys.argv[4] if len(sys.argv) > 4 and sys.argv[4] else DEFAULT_API
write_defaults(run / "override.yaml", mixed, api)
secret = run / "secret"
secret.write_text("test-secret-value\n", encoding="utf-8")
secret.chmod(0o600)
