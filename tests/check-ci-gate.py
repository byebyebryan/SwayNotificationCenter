#!/usr/bin/env python3
"""Fail the always-reported fork check if any prerequisite failed or was skipped."""

import json
import os

from fork_ci import ContractError, required_jobs


if __name__ == "__main__":
    try:
        required_jobs(json.loads(os.environ["FORK_CHECK_NEEDS"]))
    except (ContractError, KeyError, ValueError, TypeError) as error:
        raise SystemExit(str(error)) from error
    print("All required fork checks passed.")
