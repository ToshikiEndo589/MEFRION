"""Verify the approved Supabase test project accepts an account with no Pet.

Creates one synthetic confirmed user, checks authenticated browsing and the
optional comment identity, then deletes that exact test user. No credentials or
server responses are printed or persisted.
"""

import json
import secrets
import urllib.error
import urllib.request
from pathlib import Path
from uuid import uuid4


ROOT = Path(__file__).resolve().parent.parent
PUBLIC = json.loads((ROOT / ".local/supabase-public.json").read_text())
SERVER = json.loads((ROOT / ".local/supabase-server.json").read_text())
assert PUBLIC["url"] == SERVER["url"] == "https://pmrvzpuznwzuejbuhaqm.supabase.co"


def request(path, body=None, token=None, admin=False, method=None):
    key = SERVER["secret_key"] if admin else PUBLIC["anon_key"]
    headers = {"apikey": key}
    if token or admin:
        headers["Authorization"] = "Bearer " + (token or key)
    data = None if body is None else json.dumps(body).encode()
    if data is not None:
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(
        PUBLIC["url"] + path, data=data, headers=headers, method=method
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as response:
            raw = response.read()
            return response.status, json.loads(raw) if raw else None
    except urllib.error.HTTPError as error:
        return error.code, None


def checked(label, path, body=None, token=None, admin=False, method=None,
            statuses=(200,)):
    status, value = request(path, body, token, admin, method)
    if status not in statuses:
        raise RuntimeError(f"{label}: HTTP {status}")
    return value


def rpc(name, token, body=None):
    return checked(name, "/rest/v1/rpc/mefrion_" + name, body or {}, token)


identity = {
    "email": "mefrion-test-petless-" + uuid4().hex + "@example.invalid",
    "password": secrets.token_urlsafe(36),
    "email_confirm": True,
    "user_metadata": {"test_only": True},
}
user_id = None
passed = []
try:
    user = checked("create", "/auth/v1/admin/users", identity, admin=True,
                   statuses=(200, 201))
    user_id = user["id"]
    session = checked("login", "/auth/v1/token?grant_type=password",
                      {"email": identity["email"], "password": identity["password"]})
    token = session["access_token"]
    assert rpc("list_pets", token) == []
    passed.append("authenticated with no Pet")

    page = rpc("feed_page", token, {"p_limit": 10})
    assert isinstance(page.get("items"), list)
    passed.append("browse public feed with no Pet")

    speakers = rpc("public_speakers", token)
    assert speakers == []
    assert rpc("set_social_name", token, {"p_name": "閲覧アカウント"}) is True
    profile = rpc("social_identity", token)
    assert profile["name"] == "閲覧アカウント"
    assert rpc("list_pets", token) == []
    passed.append("choose comment nickname without creating a Pet")
finally:
    if user_id is not None:
        # Auth hard deletion conflicts with the app's audit references. Soft
        # erasure revokes this disposable user's login without touching them.
        status, _ = request("/auth/v1/admin/users/" + user_id,
                            {"should_soft_delete": True}, admin=True,
                            method="DELETE")
        if status not in (200, 204):
            raise RuntimeError(f"synthetic user cleanup: HTTP {status}")
        erased = checked("verify cleanup", "/auth/v1/admin/users/" + user_id,
                         admin=True)
        if not erased.get("deleted_at"):
            raise RuntimeError("synthetic user cleanup not confirmed")

print(json.dumps({"passed": len(passed) == 3, "checks": passed}, ensure_ascii=False))
