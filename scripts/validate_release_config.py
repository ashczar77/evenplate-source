"""Validate release configuration without displaying credential values."""
from pathlib import Path
import sys

def values(path):
    result = {}
    for line in Path(path).read_text().splitlines():
        if '=' in line and not line.lstrip().startswith('#'):
            key, value = line.split('=', 1)
            result[key.strip()] = value.strip().strip('\"\'')
    return result

app = values('.env')
server = values('supabase/.env.functions')
errors = []
platform = sys.argv[1] if len(sys.argv) > 1 else 'ios'
required = ['SUPABASE_URL', 'SUPABASE_ANON_KEY', 'ONESIGNAL_APP_ID', 'SENTRY_DSN', 'REVENUECAT_APPLE_KEY' if platform == 'ios' else 'REVENUECAT_GOOGLE_KEY']
for name in required:
    value = app.get(name, '')
    if not value or 'mock' in value or value == 'test_key' or value.startswith('test_'):
        errors.append(name + ' is not configured for release')
for name in ['GEMINI_API_KEY', 'REVENUECAT_WEBHOOK_SECRET', 'REVENUECAT_SECRET_API_KEY', 'ONESIGNAL_REST_API_KEY', 'ONESIGNAL_APP_ID', 'SENTRY_DSN']:
    if not server.get(name):
        errors.append(name + ' is missing from server configuration')
if server.get('ALLOW_DEV_UNLIMITED_SCANS', '').lower() == 'true':
    errors.append('Development scan bypass must be disabled')
if server.get('ONESIGNAL_APP_ID') != app.get('ONESIGNAL_APP_ID'):
    errors.append('Client and server OneSignal App IDs differ')
if errors:
    print('\n'.join(errors))
    sys.exit(1)
print(platform + ' release configuration passed')
