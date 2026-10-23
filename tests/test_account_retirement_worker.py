"""Offline checks for the queued account-erasure worker."""
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from uuid import uuid4

from scripts import process_account_retirement as worker


class Response:
    def __init__(self, value):
        self.value = value

    def __enter__(self):
        return self

    def __exit__(self, *_):
        return False

    def read(self):
        return json.dumps(self.value).encode()


class RetirementWorkerTests(unittest.TestCase):
    def test_explicitly_queued_regular_account_is_erased(self):
        user_id = str(uuid4())
        calls = []
        erased = False

        def urlopen(request, timeout):
            nonlocal erased
            path = request.full_url.split("supabase.co", 1)[1]
            calls.append((request.get_method(), path))
            if path.endswith("/mefrion_retirement_batch"):
                return Response([{"user_id": user_id, "paths": [{"bucket": "family-originals", "path": "owner/photo.jpg"}]}])
            if path == f"/auth/v1/admin/users/{user_id}":
                if request.get_method() == "DELETE":
                    erased = True
                    return Response({})
                return Response({"id": user_id, "email": "person@example.com", "deleted_at": "now" if erased else None})
            if path == "/storage/v1/object/family-originals":
                return Response({})
            if path == "/storage/v1/object/list/family-originals":
                return Response([])
            if path.endswith("/mefrion_retirement_ack"):
                self.assertTrue(erased)
                return Response(True)
            self.fail(f"Unexpected request: {path}")

        with tempfile.TemporaryDirectory() as directory:
            local = Path(directory) / ".local"
            local.mkdir()
            (local / "supabase-server.json").write_text(json.dumps({
                "url": "https://pmrvzpuznwzuejbuhaqm.supabase.co", "secret_key": "test-only"
            }))
            with patch.object(worker, "ROOT", Path(directory)), patch.object(worker.urllib.request, "urlopen", side_effect=urlopen):
                result = worker.execute(user_id)

        self.assertEqual(result["processed"], 1)
        self.assertEqual(result["storage_paths_removed"], 1)
        self.assertTrue(erased)
        self.assertEqual(calls[-1][1], "/rest/v1/rpc/mefrion_retirement_ack")

    def test_unqueued_account_is_not_touched(self):
        user_id = str(uuid4())
        with tempfile.TemporaryDirectory() as directory:
            local = Path(directory) / ".local"
            local.mkdir()
            (local / "supabase-server.json").write_text(json.dumps({
                "url": "https://pmrvzpuznwzuejbuhaqm.supabase.co", "secret_key": "test-only"
            }))
            with patch.object(worker, "ROOT", Path(directory)), patch.object(worker.urllib.request, "urlopen", return_value=Response([])) as urlopen:
                result = worker.execute(user_id)

        self.assertEqual(result["processed"], 0)
        self.assertEqual(urlopen.call_count, 1)


if __name__ == "__main__":
    unittest.main()
