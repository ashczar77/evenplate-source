"""Keep public legal pages identical to the in-app policy text."""
import json
import html
import re
import sys
from pathlib import Path

source = Path('lib/core/legal/legal_copy.dart').read_text()
documents = {}
for key in ('privacy', 'terms'):
    match = re.search(r"static const String " + key + r"Body = '''\n(.*?)\n''';", source, re.S)
    if match is None:
        raise RuntimeError('Missing in-app document: ' + key)
    documents[key] = match.group(1)
documents['support'] = '''Contact evenplatesupport@gmail.com for help with EvenPlate, privacy questions, or account deletion.

Include your app version and a description of the problem. Do not send passwords, API keys, payment card information, or private meal photos.

To delete your account, open Settings and choose Delete Account. To manage or cancel a subscription, use your App Store or Google Play subscription settings. Deleting an account or the app does not cancel a store subscription.

EvenPlate provides educational fullness estimates. It is not medical advice. For allergies or medical concerns, follow your own care plan.'''
target = Path('supabase/functions/legal/content.ts')
target.parent.mkdir(parents=True, exist_ok=True)
content = '// Policy text mirrors the in-app documents.\nexport const documents = ' + json.dumps(documents, indent=2, ensure_ascii=True) + ' as const;\n'
outputs = {target: content}
titles = {'privacy': 'Privacy Policy', 'terms': 'Terms of Use', 'support': 'Support'}
for key, body in documents.items():
    blocks = []
    for section in body.split('\n\n'):
        lines = section.splitlines()
        if len(lines) > 1 and all(line.startswith('- ') for line in lines[1:]):
            blocks.append('<h2>' + html.escape(lines[0]) + '</h2>')
            blocks.append('<ul>' + ''.join('<li>' + html.escape(line[2:]) + '</li>' for line in lines[1:]) + '</ul>')
        elif len(lines) > 1 and len(lines[0]) < 50:
            blocks.append('<h2>' + html.escape(lines[0]) + '</h2>')
            blocks.append('<p>' + html.escape('\n'.join(lines[1:])) + '</p>')
        else:
            blocks.append('<p>' + html.escape(section) + '</p>')
    rendered = '\n'.join(blocks).replace('evenplatesupport@gmail.com', '<a href="mailto:evenplatesupport@gmail.com">evenplatesupport@gmail.com</a>')
    page = f'''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="description" content="EvenPlate {titles[key].lower()} and contact information.">
<title>{titles[key]} | EvenPlate</title>
<link rel="canonical" href="https://evenplateapp.xyz/{key}/">
<link rel="stylesheet" href="/legal.css">
</head>
<body>
<main>
<a class="brand" href="/">EvenPlate</a>
<h1>{titles[key]}</h1>
{rendered}
<nav aria-label="Website"><a href="/privacy/">Privacy Policy</a><a href="/terms/">Terms of Use</a><a href="/support/">Support</a></nav>
</main>
</body>
</html>
'''
    outputs[Path('docs') / key / 'index.html'] = page
if '--check' in sys.argv:
    for path, expected in outputs.items():
        if not path.exists() or path.read_text() != expected:
            raise SystemExit('Public policy is stale: ' + str(path) + '. Run python3 scripts/sync_legal_pages.py')
    print('Public legal content matches in-app documents')
else:
    for path, expected in outputs.items():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(expected)
    print('Public legal content synchronized')
