"""Deployable public-only WSGI gateway; no private or administrative routes."""
import json
import os
import re
from urllib.parse import urlsplit
from backend import cloud_shares

CSS = (cloud_shares.ROOT / 'web/shared.css').read_bytes()
HEADERS = [('Cache-Control', 'no-store, max-age=0'), ('X-Content-Type-Options', 'nosniff'), ('Referrer-Policy', 'no-referrer'), ('X-Robots-Tag', 'noindex, nofollow'), ('Content-Security-Policy', "default-src 'none'; img-src 'self'; style-src 'self' 'unsafe-inline'; base-uri 'none'; frame-ancestors 'none'; form-action 'none'")]


def public_origin():
    value = os.environ.get('MEFRION_PUBLIC_ORIGIN', '').rstrip('/')
    try:
        parsed = urlsplit(value)
        valid_host = parsed.hostname and re.fullmatch(r'[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?', parsed.hostname)
        if parsed.scheme != 'https' or not valid_host or parsed.username or parsed.password or parsed.path or parsed.query or parsed.fragment or parsed.port not in (None, 443):
            return None
    except ValueError:
        return None
    return value


def application(environ, start_response):
    status, data, kind = 404, b'Not found', 'text/plain; charset=utf-8'
    path = environ.get('PATH_INFO', '')
    try:
        if len(path) > 2048 or len(environ.get('QUERY_STRING', '')) > 2048:
            status, data = 414, b'Request too long'
        elif environ.get('REQUEST_METHOD') != 'GET':
            status, data = 405, b'Method not allowed'
        elif path == '/healthz':
            status, data, kind = 200, b'{"gateway":"ready"}', 'application/json'
        elif path == '/shared.css':
            status, data, kind = 200, CSS, 'text/css; charset=utf-8'
        elif path == '/.well-known/apple-app-site-association':
            app_id = os.environ.get('MEFRION_ASSOCIATED_APP_ID', '')
            if public_origin() and re.fullmatch(r'[A-Z0-9]{10}\.[A-Za-z0-9.-]+', app_id):
                status, kind = 200, 'application/json'
                data = json.dumps({'applinks': {'details': [{'appIDs': [app_id], 'components': [{'/': '/cloud-shared/*', 'comment': 'Public shared cards only'}]}]}}).encode()
        else:
            parts = path.strip('/').split('/')
            if len(parts) == 2 and parts[0] == 'cloud-shared' and cloud_shares.UUID.fullmatch(parts[1]):
                status, page = cloud_shares.page(parts[1])
                origin = public_origin()
                if origin:
                    page = page.replace('content="/cloud-shared/', 'content="' + origin + '/cloud-shared/')
                data, kind = page.encode(), 'text/html; charset=utf-8'
            elif len(parts) == 4 and parts[0] == 'cloud-shared' and parts[2] == 'image' and cloud_shares.UUID.fullmatch(parts[1]) and cloud_shares.UUID.fullmatch(parts[3]):
                image = cloud_shares.image(parts[1], parts[3])
                status, data, kind = (200, image, 'image/jpeg') if image else (404, b'Ended', kind)
    except (OSError, ValueError, KeyError, TypeError):
        status, data, kind = 503, b'Share unavailable', 'text/plain; charset=utf-8'
    descriptions = {200: 'OK', 404: 'Not Found', 405: 'Method Not Allowed', 414: 'URI Too Long', 503: 'Service Unavailable'}
    start_response(str(status) + ' ' + descriptions[status], HEADERS + [('Content-Type', kind), ('Content-Length', str(len(data)))])
    return [data]
