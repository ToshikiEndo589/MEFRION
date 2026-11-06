"""Reject ambiguous Supabase migration histories before any deployment."""
from pathlib import Path
import re
import sys

def check(directory):
    versions = {}
    for path in sorted(Path(directory).glob('*.sql')):
        match = re.fullmatch(r'(\d+)_.+\.sql', path.name)
        if not match:
            raise ValueError(f'Invalid migration filename: {path.name}')
        version = match[1]
        if version in versions:
            raise ValueError(f'Duplicate migration {version}: {versions[version]} / {path.name}')
        versions[version] = path.name
    return len(versions)

if __name__ == '__main__':
    try:
        print(f'{check(Path(__file__).resolve().parents[1] / "supabase/migrations")} unique migration versions')
    except ValueError as error:
        sys.exit(str(error))
