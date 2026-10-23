"""Deploy MEFRION's reviewed Edge Functions to the isolated production project.

Requires a short-lived, project-scoped SUPABASE_ACCESS_TOKEN in the environment.
No service-role key or database password is needed. The command never prunes remote
functions and verifies the deployed list before reporting success.
"""

import json
import os
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CLI = ROOT / ".local/bin/supabase"
PROJECT_REF = "pbnimpqrthvznbwewtcf"
FUNCTIONS = (
    "private-image",
    "private-video",
    "public-image",
    "public-video",
    "shared-page",
    "cloud-worker",
    "asset-ingest",
    "database-backup",
    "offsite-backup",
)


def main() -> int:
    if not CLI.is_file():
        print("Supabase CLI is missing from .local/bin", file=sys.stderr)
        return 2
    if not os.environ.get("SUPABASE_ACCESS_TOKEN"):
        print("SUPABASE_ACCESS_TOKEN is required", file=sys.stderr)
        return 2

    command = [str(CLI), "functions", "deploy", *FUNCTIONS,
               "--project-ref", PROJECT_REF, "--use-api", "--jobs", "2"]
    result = subprocess.run(command, cwd=ROOT, check=False)
    if result.returncode:
        return result.returncode

    check = subprocess.run(
        [str(CLI), "functions", "list", "--project-ref", PROJECT_REF,
         "--output", "json"],
        cwd=ROOT, check=False, capture_output=True, text=True,
    )
    if check.returncode:
        print("Deployment returned success but list verification failed.", file=sys.stderr)
        return 1
    try:
        actual = {item["name"] for item in json.loads(check.stdout)}
    except (ValueError, KeyError, TypeError):
        print("Could not parse the deployed function list.", file=sys.stderr)
        return 1
    missing = set(FUNCTIONS) - actual
    if missing:
        print("Missing deployed functions: " + ", ".join(sorted(missing)), file=sys.stderr)
        return 1
    print(f"Verified {len(FUNCTIONS)} production Edge Functions in {PROJECT_REF}.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
