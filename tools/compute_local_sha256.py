import json, hashlib
p = 'borrowbook-ebac9-firebase-adminsdk-fbsvc-9b3053a950.json'
with open(p, 'r', encoding='utf-8') as f:
    j = json.load(f)
raw = j['private_key']
raw = raw.replace('-----BEGIN PRIVATE KEY-----', '').replace('-----END PRIVATE KEY-----', '')
clean = ''.join(raw.split())
h = hashlib.sha256(clean.encode('utf-8')).hexdigest()
print('LOCAL_BASE64_CLEANED_SHA256=' + h)
