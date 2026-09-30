export const endpoint = 'https://dioynjwmaehzpsctlioj.supabase.co';
export function readLink(search) {
  const p = new URLSearchParams(search);
  const type = p.get('type');
  const hash = p.get('token_hash');
  if (!['email', 'recovery'].includes(type) || !hash || !/^[a-zA-Z0-9_-]{20,256}$/.test(hash)) return null;
  let native = null;
  try {
    const url = new URL(p.get('confirmation_url'));
    if (url.origin === endpoint && url.pathname === '/auth/v1/verify' &&
        ['email', 'signup', 'recovery'].includes(url.searchParams.get('type')) &&
        (type === 'recovery') === (url.searchParams.get('type') === 'recovery') &&
        url.searchParams.get('redirect_to') === 'evenplate://auth-callback' &&
        !url.username && !url.password) native = url.href;
  } catch (_) { /* Browser flow can still work without a native link. */ }
  return {type, hash, native};
}
export function passwordError(password, confirmation) {
  if (password.length < 10 || !/[A-Z]/.test(password) || !/[a-z]/.test(password) || !/[0-9]/.test(password) || !/[^A-Za-z0-9]/.test(password))
    return 'Use 10+ characters, with upper and lowercase, a number, and a symbol.';
  return password === confirmation ? null : 'The passwords do not match.';
}
export function createAuth(apiKey, fetcher = fetch) {
  async function request(path, method, body, token) {
    const response = await fetcher(endpoint + '/auth/v1/' + path, {
      method, headers: {'Content-Type': 'application/json', apikey: apiKey,
        ...(token ? {Authorization: 'Bearer ' + token} : {})},
      body: JSON.stringify(body), signal: AbortSignal.timeout(20000),
      cache: 'no-store', referrerPolicy: 'no-referrer', credentials: 'omit',
    });
    const data = await response.json();
    if (!response.ok) {
      const error = new Error('Request rejected');
      error.code = data.code || data.error_code;
      throw error;
    }
    return data;
  }
  return {
    verify: link => request('verify', 'POST', {token_hash: link.hash, type: link.type}),
    update: (password, token) => request('user', 'PUT', {password}, token),
    logout: token => request('logout?scope=local', 'POST', {}, token).catch(() => {}),
  };
}
