"""Exercise shared free credits concurrently without calling Gemini."""
import concurrent.futures
import json
import re
import secrets
import subprocess
import uuid
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import Request, urlopen


config = {}
for line in Path('.env').read_text().splitlines():
    if '=' in line and not line.lstrip().startswith('#'):
        name, value = line.split('=', 1)
        config[name.strip()] = value.strip().strip('"\'')
base = config['SUPABASE_URL'].rstrip('/')
key = config['SUPABASE_ANON_KEY']
project = re.fullmatch(r'https://([a-z0-9]+)\.supabase\.co', base)
if project is None:
    raise RuntimeError('Expected hosted disposable-test target')
output = subprocess.run(['supabase', 'projects', 'api-keys', '--project-ref', project[1], '--reveal', '--output', 'json'], capture_output=True, text=True, check=True)
rows = json.loads(output.stdout)
if isinstance(rows, dict):
    rows = rows.get('api_keys', rows.get('keys', []))
admin = next(row['api_key'] for row in rows if row.get('name') == 'service_role')
owners = []


def request(path, token, body=None, method=None, api_key=None):
    data = None if body is None else json.dumps(body).encode()
    req = Request(base + path, data=data, method=method, headers={
        'apikey': api_key or key, 'Authorization': 'Bearer ' + token,
        'Content-Type': 'application/json'})
    try:
        with urlopen(req, timeout=30) as response:
            return response.status, json.loads(response.read() or b'null')
    except HTTPError as error:
        return error.code, json.loads(error.read() or b'null')


def create(email):
    credentials = {'email': email, 'password': secrets.token_urlsafe(32) + 'Aa9!'}
    status, user = request('/auth/v1/admin/users', admin, {**credentials, 'email_confirm': True}, api_key=admin)
    if status not in (200, 201) or not user.get('id'):
        raise RuntimeError('Disposable account creation failed')
    owners.append(user['id'])
    status, session = request('/auth/v1/token?grant_type=password', key, credentials)
    if status != 200 or not session.get('access_token'):
        raise RuntimeError('Disposable sign-in failed')
    return user['id'], session['access_token']


try:
    mailbox = 'evenplate-quota-' + uuid.uuid4().hex
    first, token_a = create(mailbox + '+one@gmail.com')
    _, token_b = create(mailbox + '+two@gmail.com')
    with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
        outcomes = list(pool.map(lambda token: request('/rest/v1/rpc/consume_scan_credit', token, {}), [token_a, token_b] * 3))
    if any(status != 200 for status, _ in outcomes) or sum(row.get('allowed') is True for _, row in outcomes) != 3:
        raise RuntimeError('Concurrent aliases overspent or lost the photo allowance')
    print('Concurrent Gmail aliases: exactly three shared photo credits, PASS', flush=True)
    status, _ = request('/auth/v1/admin/users/' + first, admin, method='DELETE', api_key=admin)
    if status not in (200, 204):
        raise RuntimeError('Disposable deletion failed')
    owners.remove(first)
    _, token_c = create(mailbox + '+one@gmail.com')
    status, quota = request('/rest/v1/rpc/get_my_quota', token_c, {})
    if status != 200 or quota.get('free_scans_remaining') != 0:
        raise RuntimeError('Account recreation revived the exhausted allowance')
    print('Delete and recreate same email: zero photo credits restored, PASS', flush=True)
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        outcomes = list(pool.map(lambda token: request('/rest/v1/rpc/consume_food_score_credit', token, {}), [token_b, token_c] * 12))
    if any(status != 200 for status, _ in outcomes) or sum(row.get('allowed') is True for _, row in outcomes) != 20:
        raise RuntimeError('Concurrent aliases overspent or lost the text allowance')
    print('Concurrent Gmail aliases: exactly twenty shared text credits, PASS', flush=True)
finally:
    for owner in owners:
        status, _ = request('/auth/v1/admin/users/' + owner, admin, method='DELETE', api_key=admin)
        if status not in (200, 204):
            raise RuntimeError('Disposable cleanup failed')
    print('Disposable accounts removed; no Gemini requests were made.', flush=True)
