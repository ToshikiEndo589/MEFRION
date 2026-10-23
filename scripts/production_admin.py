"""Explicit production administration through a TLS-verified DB connection.

Credentials are read only from ignored local files, never command arguments.
This is a deployment tool, not an application/runtime dependency on this Mac.
"""
import argparse
import json
import secrets
import ssl
from pathlib import Path

import pg8000.native

ROOT = Path(__file__).resolve().parents[1]
LOCAL = ROOT / '.local'
REF = 'pbnimpqrthvznbwewtcf'


def connect():
    context = ssl.create_default_context()
    context.load_verify_locations(str(LOCAL / 'supabase-root-ca.crt'))
    host = (LOCAL / 'production-db-host').read_text().strip()
    if host != f'db.{REF}.supabase.co':
        raise RuntimeError('Unexpected production database host')
    return pg8000.native.Connection('postgres', password=(LOCAL / 'production-db-password').read_text().strip(),
                                   host=host, database='postgres', ssl_context=context, timeout=120)


def prepare_worker_token(connection):
    rows = connection.run("select decrypted_secret from vault.decrypted_secrets where name='mefrion_cloud_worker_token'")
    token = rows[0][0] if rows else secrets.token_urlsafe(48)
    if not rows:
        connection.run("select vault.create_secret(:value,'mefrion_cloud_worker_token','Internal cloud queue only')", value=token)
    if not connection.run("select 1 from vault.secrets where name='mefrion_project_url'"):
        connection.run("select vault.create_secret(:value,'mefrion_project_url','Production project endpoint')", value=f'https://{REF}.supabase.co')
    target = LOCAL / 'production-cloud-worker-token'
    target.touch(mode=0o600, exist_ok=True)
    target.chmod(0o600)
    target.write_text(token)
    return token


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=['status', 'prepare-worker', 'validate', 'apply', 'tick'])
    parser.add_argument('--migration', type=Path)
    args = parser.parse_args()
    connection = connect()
    try:
        if args.action == 'prepare-worker':
            prepare_worker_token(connection)
            print('Internal worker token and endpoint configured in production Vault; no secret printed.')
        elif args.action in ('validate', 'apply'):
            if not args.migration:
                parser.error('--migration required')
            path = args.migration.resolve()
            if path.parent != ROOT / 'supabase/migrations':
                raise RuntimeError('Only a repository migration can be applied')
            sql = path.read_text()
            if args.action == 'validate':
                sql = sql.rsplit('commit;', 1)[0] + 'rollback;'
            connection.run(sql)
            if args.action == 'apply':
                version, _, name = path.stem.partition('_')
                connection.run('insert into supabase_migrations.schema_migrations(version,name,statements) values(:version,:name,:statements) on conflict(version) do nothing',
                               version=version, name=name, statements=[path.read_text()])
            print(json.dumps({'migration': path.name, 'applied': args.action == 'apply', 'validated': True}))
        elif args.action == 'tick':
            print(json.dumps(connection.run('select mefrion_private.cloud_tick()')[0][0]))
        else:
            print(json.dumps({'database_bytes': connection.run("select pg_database_size(current_database())")[0][0],
                              'extensions': [r[0] for r in connection.run('select extname from pg_extension')],
                              'cron': connection.run("select jobname,schedule,active from cron.job where jobname like 'mefrion-%'") if connection.run("select to_regclass('cron.job')")[0][0] else []}, default=str))
    finally:
        connection.close()


if __name__ == '__main__':
    main()
