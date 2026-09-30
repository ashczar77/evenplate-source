"""Check the deployed backend with a disposable account, then delete it."""
import json
import base64
import struct
import re
import secrets
import subprocess
import uuid
import zlib
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import Request, urlopen


def read_config(path):
    config = {}
    for line in Path(path).read_text().splitlines():
        if '=' in line and not line.lstrip().startswith('#'):
            name, value = line.split('=', 1)
            config[name.strip()] = value.strip().strip('"\'')
    return config


config = read_config('.env')
base = config['SUPABASE_URL'].rstrip('/')
key = config['SUPABASE_ANON_KEY']
token = key


def request(path, body=None, method=None, admin_key=None):
    payload = None if body is None else json.dumps(body).encode()
    headers = {'apikey': admin_key or key, 'Authorization': 'Bearer ' + (admin_key or token),
               'Content-Type': 'application/json', 'Prefer': 'return=representation'}
    req = Request(base + path, data=payload, headers=headers, method=method)
    try:
        with urlopen(req, timeout=65) as response:
            status, raw = response.status, response.read()
    except HTTPError as error:
        status, raw = error.code, error.read()
    return status, json.loads(raw) if raw else None


def check(label, condition, status):
    print(f'{label}: HTTP {status}, {"PASS" if condition else "FAIL"}', flush=True)
    if not condition:
        raise RuntimeError(label)


created = False
deleted = False
try:
    project = re.fullmatch(r'https://([a-z0-9]+)\.supabase\.co', base)
    if project is None:
        raise RuntimeError('Expected a hosted Supabase test target')
    output = subprocess.run(['supabase', 'projects', 'api-keys', '--project-ref', project[1], '--reveal', '--output', 'json'], capture_output=True, text=True, check=True)
    rows = json.loads(output.stdout)
    if isinstance(rows, dict):
        rows = rows.get('api_keys', rows.get('keys', []))
    admin_key = next(row['api_key'] for row in rows if row.get('name') == 'service_role')
    credentials = {'email': 'release-smoke-' + str(uuid.uuid4()) + '@invalid.example', 'password': secrets.token_urlsafe(32) + 'Aa9!'}
    status, account = request('/auth/v1/admin/users', {**credentials, 'email_confirm': True}, admin_key=admin_key)
    check('Disposable verified account creation', status in (200, 201) and bool(account.get('id')), status)
    owner = account['id']
    created = True
    status, session = request('/auth/v1/token?grant_type=password', credentials)
    check('Disposable account sign-in', status == 200 and bool(session.get('access_token')), status)
    token = session['access_token']
    status, quota = request('/rest/v1/rpc/get_my_quota', {})
    check('Authoritative quota', status == 200 and isinstance(quota, dict), status)
    initial = quota['text_included_remaining']
    print('Quota fields: ' + ', '.join(sorted(quota)), flush=True)
    status, result = request('/functions/v1/analyze-foods', {'foods': ['eggs'], 'analysisConsent': False})
    check('Consent denial', status == 403, status)
    status, denied_quota = request('/rest/v1/rpc/get_my_quota', {})
    check('Consent denial preserves quota', denied_quota == quota, status)
    body = {'foods': ['eggs', 'oats'], 'mealName': 'Release smoke test',
            'analysisConsent': True, 'requestId': str(uuid.uuid4()), 'dietaryPreference': 'vegetarian'}
    status, result = request('/functions/v1/analyze-foods', body)
    check('Live Gemini food scoring', status == 200 and result.get('captureIssue') == 'none', status)
    check('Complete Gemini score is versioned independently of optional range', result.get('assessmentMethod') == 'gemini-meal-v1' and 0 <= result.get('satietyScore', -1) <= 100 and result.get('durationHours') == 0 and len(result.get('components', [])) == 2, status)
    estimate = result.get('fullnessEstimate')
    check('Regular-portion range returned in the same live assessment', isinstance(estimate, dict) and estimate.get('portion') == 'regular' and estimate.get('basis') == 'model_regular_portion_v1' and isinstance(estimate.get('minHours'), int) and isinstance(estimate.get('maxHours'), int) and 1 <= estimate['minHours'] < estimate['maxHours'] <= 12, status)
    print('Live model output (not accuracy validation): ' + str(estimate['minHours']) + '-' + str(estimate['maxHours']) + ' hours', flush=True)
    status, spent = request('/rest/v1/rpc/get_my_quota', {})
    check('Food scoring consumes one credit', spent['text_included_remaining'] == initial - 1, status)
    status, replay = request('/functions/v1/analyze-foods', body)
    check('Identical request replays original result', status == 200 and replay == result, status)
    status, after_replay = request('/rest/v1/rpc/get_my_quota', {})
    check('Replay cannot double charge', after_replay == spent, status)
    for foods in [['cake'], ['sushi platter', 'edamame'], ['grilled sausages', 'rice', 'vegetables'], ['coke', 'biscuits']]:
        lookup = {'foods': foods, 'mealName': 'Plate', 'analysisConsent': True, 'requestId': str(uuid.uuid4())}
        if foods[0] == 'sushi platter':
            lookup['originalAnalysis'] = {**result, 'mealName': 'Sushi platter', 'components': ['sushi platter'], 'assessmentNote': 'One standard sushi platter, estimated from a photo.', 'captureIssue': 'none', 'durationHours': 0.5, 'crashRisk': 'moderate'}
        status, identified = request('/functions/v1/analyze-foods', lookup)
        check('Complete-meal assessment: ' + ', '.join(foods), status == 200 and identified.get('assessmentMethod') == 'gemini-meal-v1' and sorted(identified.get('components', [])) == sorted(foods), status)
        print('Relative estimate: ' + str(identified.get('satietyScore')) + '/100', flush=True)
    status, before_photo = request('/rest/v1/rpc/get_my_quota', {})
    def chunk(kind, data):
        return struct.pack('!I', len(data)) + kind + data + struct.pack('!I', zlib.crc32(kind + data))
    image = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('!2I5B', 8, 8, 8, 2, 0, 0, 0))
    image += chunk(b'IDAT', zlib.compress((b'\x00' + b'\x00\x80\x00' * 8) * 8)) + chunk(b'IEND', b'')
    status, photo = request('/functions/v1/analyze-plate', {'imageBase64': base64.b64encode(image).decode(), 'mimeType': 'image/png', 'analysisConsent': True, 'requestId': str(uuid.uuid4())})
    check('Live vision rejects a synthetic non-food image', status == 200 and photo.get('captureIssue') != 'none', status)
    status, after_photo = request('/rest/v1/rpc/get_my_quota', {})
    check('Non-food photo refunds the reserved credit', after_photo == before_photo, status)
    status, _ = request('/rest/v1/rpc/refund_scan_credit', {'p_user_id': owner, 'p_purchased': False})
    check('Customer cannot mint credits', status in (401, 403, 404), status)
    status, _ = request('/rest/v1/profiles?id=eq.' + owner, {'is_pro': True}, 'PATCH')
    check('Customer cannot grant Pro', status in (401, 403), status)
    status, _ = request('/rest/v1/user_preferences', {'user_id': owner, 'preferences': {'dietaryPreference': 'vegan'}}, 'POST')
    check('Preference persistence', status == 201, status)
    status, _ = request('/functions/v1/reconcile-billing', {})
    check('RevenueCat reconciliation', status == 200, status)
finally:
    if created:
        status, result = request('/functions/v1/delete-account', {})
        deleted = status == 200 and result.get('deleted') is True
        if not deleted:
            request('/auth/v1/admin/users/' + owner, method='DELETE', admin_key=admin_key)
        check('Account and external identity deletion', deleted, status)
        status, _ = request('/auth/v1/user')
        check('Deleted account no longer authenticates', status in (401, 403, 404), status)
        status, result = request('/functions/v1/delete-account', {})
        check('Account deletion retry is idempotent', status == 200 and result.get('deleted') is True, status)
if deleted:
    print('Live smoke checks completed; disposable account removed.', flush=True)
