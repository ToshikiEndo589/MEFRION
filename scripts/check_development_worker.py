"""Read only worker freshness/health check. Logs counts, never identities."""
import json
import sys
import time
from pathlib import Path


def assess(report, now=None, max_age=180):
    now = time.time() if now is None else now
    stamp = report.get('timestamp')
    if not isinstance(stamp, (int, float)) or not 0 <= now - stamp <= max_age:
        return {'healthy': False, 'reason': 'missing_or_stale_status'}
    failures = report.get('failures')
    if not isinstance(failures, int) or failures != 0:
        return {'healthy': False, 'reason': 'processing_failed'}
    if report.get('automatic_local') is not True:
        return {'healthy': False, 'reason': 'not_automatic'}
    return {'healthy': True, 'reason': 'recent_local_cycle', 'age_seconds': int(now - stamp), 'cloud_schedule': report.get('cloud_schedule') is True}


if __name__ == '__main__':
    source = Path(__file__).resolve().parent.parent / '.local/development-worker-status.json'
    try:
        result = assess(json.loads(source.read_text()))
    except (OSError, ValueError, TypeError):
        result = {'healthy': False, 'reason': 'status_unavailable'}
    print(json.dumps(result))
    sys.exit(0 if result['healthy'] else 1)
