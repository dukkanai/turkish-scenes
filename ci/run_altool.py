#!/usr/bin/env python3
"""altool can print an Apple rejection while returning zero. Fail closed."""
import re
import subprocess
import sys


def check_result(output, returncode, operation):
    if operation not in ("validate", "upload"):
        raise ValueError("Unknown altool operation")
    if returncode != 0 or re.search(r"\b(?:ERROR|FAILED)\b", output, re.IGNORECASE):
        raise ValueError("Apple reported an error or altool returned a failure")
    marker = (r"\bVERIFY SUCCEEDED\b|\bNo errors validating\b" if operation == "validate"
              else r"\bUPLOAD SUCCEEDED\b|\bNo errors uploading\b")
    if not re.search(marker, output, re.IGNORECASE):
        raise ValueError("No explicit Apple success confirmation; inspect the outcome before retrying")


def main():
    operation, *arguments = sys.argv[1:]
    if operation not in ("validate", "upload"):
        raise ValueError("Expected validate or upload")
    result = subprocess.run(
        ["xcrun", "altool", f"--{operation}-app", *arguments],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, check=False,
    )
    print(result.stdout, end="", flush=True)
    try:
        check_result(result.stdout, result.returncode, operation)
    except ValueError as error:
        print(f"::error::{error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
