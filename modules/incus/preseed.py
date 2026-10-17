#!/usr/bin/env python3
"""Create-only Incus preseed guard; never reconcile an existing storage pool."""
import json
import subprocess
import sys


def incus(*arguments):
    result = subprocess.run(["incus", "--force-local", *arguments], text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if result.returncode:
        raise RuntimeError("Incus operation failed: " + " ".join(arguments[:2]))
    return result.stdout


def condition(pool):
    pools = json.loads(incus("storage", "list", "--format=json"))
    if not isinstance(pools, list) or not all(isinstance(item, dict) and isinstance(item.get("name"), str) for item in pools):
        raise ValueError("Unexpected Incus storage list")
    # ExecCondition 1 skips initialization; errors must use 255, not a skip code.
    if any(item["name"] == pool for item in pools):
        return 1
    if pools:
        raise RuntimeError("Target pool is absent while other pools exist; explicit storage migration is required before preseed.")
    return 0


def main():
    operation, *arguments = sys.argv[1:]
    if operation == "condition" and len(arguments) == 1:
        return condition(arguments[0])
    raise ValueError("Usage: attos-incus condition <pool>")


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as error:
        print("Incus preseed check failed: " + str(error), file=sys.stderr)
        # An ExecCondition daemon/parser failure must fail the unit instead of permitting initialization.
        sys.exit(255)
