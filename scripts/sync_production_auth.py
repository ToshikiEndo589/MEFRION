"""Copy the already approved Brevo SMTP setup to production; no new provider.

Use a short-lived Management token on the two MEFRION projects. Supabase
currently requires project_admin_write for the PATCH endpoint even when the
Auth Config read/write capability is selected. Prefer the existing dashboard
instead of expanding a restricted migration token. Secrets stay out of output.
"""
import argparse
import json
import os
import re
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = 'pmrvzpuznwzuejbuhaqm'
TARGET = 'pbnimpqrthvznbwewtcf'
FIELDS = ('smtp_host', 'smtp_port', 'smtp_user', 'smtp_pass', 'smtp_admin_email', 'smtp_sender_name', 'smtp_max_frequency')


def main():
    parser = argparse.ArgumentParser(); parser.add_argument('--apply', action='store_true'); args = parser.parse_args()
    token = os.environ.get('SUPABASE_ACCESS_TOKEN')
    if not token: raise RuntimeError('A short-lived Auth Management token is required')
    def request(ref, body=None):
        data = json.dumps(body).encode() if body is not None else None
        req = urllib.request.Request('https://api.supabase.com/v1/projects/'+ref+'/config/auth', data=data,
                                     headers={'Authorization': 'Bearer '+token, 'Content-Type': 'application/json'}, method='PATCH' if body is not None else 'GET')
        with urllib.request.urlopen(req, timeout=40) as response: return json.load(response)
    current = request(SOURCE)
    if current.get('smtp_host') != 'smtp-relay.brevo.com' or not current.get('smtp_pass') or '*' in current['smtp_pass'] or re.fullmatch(r'[0-9a-fA-F]{64}', current['smtp_pass']):
        raise RuntimeError('The Management API exposes a digest, not a reusable SMTP credential; configure a provider-issued key through the dashboard')
    desired = {key: current[key] for key in FIELDS if key in current}
    desired.update({'smtp_sender_name': 'MEFRION', 'mailer_autoconfirm': False, 'disable_signup': False,
                    'external_email_enabled': True, 'password_min_length': max(12, current.get('password_min_length', 12)),
                    'site_url': 'https://mefrion-support.toshiki1108.chatgpt.site',
                    'uri_allow_list': 'mefrion://auth-callback',
                    'mailer_subjects_confirmation': 'MEFRIONの確認コード',
                    'mailer_subjects_recovery': 'MEFRIONのパスワード再設定コード',
                    'mailer_templates_confirmation_content': (ROOT/'docs/operations/email-templates/confirmation.html').read_text(),
                    'mailer_templates_recovery_content': (ROOT/'docs/operations/email-templates/recovery.html').read_text()})
    if args.apply: request(TARGET, desired)
    result = request(TARGET)
    print(json.dumps({'applied': args.apply, 'smtp_configured': result.get('smtp_host') == 'smtp-relay.brevo.com' and bool(result.get('smtp_user')),
                       'email_confirmation_required': not result.get('mailer_autoconfirm', True),
                       'signup_enabled': not result.get('disable_signup', True),
                       'password_min_length': result.get('password_min_length'), 'new_email_provider': False}))


if __name__ == '__main__': main()
