"""Process entry. Record the real ttys before any command paints."""
import os
import sys


def main():
    os.environ["AXS_TTY_OUT"] = "1" if sys.stdout.isatty() else "0"
    os.environ["AXS_TTY_ERR"] = "1" if sys.stderr.isatty() else "0"
    from axs.cli import main as run

    run(sys.argv[1:])


if __name__ == "__main__":
    main()
