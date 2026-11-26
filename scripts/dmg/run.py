# Runs the vendored dmgbuild: /usr/bin/python3 -I -B scripts/dmg/run.py <dmgbuild arguments>
# `-I` (isolated mode) ignores PYTHONPATH, so this launcher puts scripts/dmg/vendor first on sys.path itself. Nothing is
# imported from site-packages, Homebrew or the network.
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "vendor"))

from dmgbuild.__main__ import main  # noqa: E402

if __name__ == "__main__":
    sys.argv[0] = "dmgbuild"
    main()
