export type DeviceEnvironment = 'production' | 'development';
export class DeviceProviderError extends Error {
  constructor(public readonly code: string) { super(code); }
}
const encoder = new TextEncoder();
const base64url = (value: Uint8Array) => btoa(String.fromCharCode(...value)).replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_');
export async function deviceJWT(pemBase64: string, keyId: string, teamId: string, now = Date.now()): Promise<string> {
  const pem = atob(pemBase64);
  const body = pem.replace(/-----[A-Z ]+-----/g, '').replace(/\s/g, '');
  const key = await crypto.subtle.importKey('pkcs8', Uint8Array.from(atob(body), c => c.charCodeAt(0)), {name:'ECDSA',namedCurve:'P-256'}, false, ['sign']);
  const header = base64url(encoder.encode(JSON.stringify({alg:'ES256',kid:keyId})));
  const claims = base64url(encoder.encode(JSON.stringify({iss:teamId,iat:Math.floor(now/1000)})));
  const message = `${header}.${claims}`;
  const signature = await crypto.subtle.sign({name:'ECDSA',hash:'SHA-256'},key,encoder.encode(message));
  return `${message}.${base64url(new Uint8Array(signature))}`;
}
export function validDeviceToken(value: unknown): value is string {
  return typeof value === 'string' && value.length > 0 && value.length <= 16384 && /^[A-Za-z0-9+/]+={0,2}$/.test(value);
}
export async function appleDeviceRequest(jwt: string, environment: DeviceEnvironment, endpoint: 'validate_device_token'|'query_two_bits'|'update_two_bits', token: string, bit?: number, transport: typeof fetch = fetch): Promise<{bit0:boolean;bit1:boolean}|null> {
  if (!validDeviceToken(token)) throw new DeviceProviderError('INVALID_TOKEN');
  const payload: Record<string,unknown> = {device_token:token,transaction_id:crypto.randomUUID(),timestamp:Date.now()};
  if (endpoint === 'update_two_bits') {
    if (bit !== 0 && bit !== 1) throw new DeviceProviderError('INVALID_BIT');
    // Never write false: delayed writes cannot reopen a previously consumed slot.
    payload[`bit${bit}`] = true;
  }
  const host = environment === 'production' ? 'api.devicecheck.apple.com' : 'api.development.devicecheck.apple.com';
  let response: Response;
  try {
    response = await transport(`https://${host}/v1/${endpoint}`, {method:'POST',headers:{Authorization:`Bearer ${jwt}`,'Content-Type':'application/json'},body:JSON.stringify(payload),signal:AbortSignal.timeout(6000)});
  } catch { throw new DeviceProviderError('APPLE_UNAVAILABLE'); }
  if (!response.ok) throw new DeviceProviderError(`APPLE_${endpoint.toUpperCase()}_HTTP_${response.status}`);
  if (endpoint !== 'query_two_bits') return null;
  const text = await response.text();
  // Apple returns either wording for a device without saved bit state.
  if (text.trim() === 'Bit State Not Found' || text.trim() === 'Failed to find bit state') return {bit0:false,bit1:false};
  try {
    const bits = JSON.parse(text);
    if (typeof bits.bit0 === 'boolean' && typeof bits.bit1 === 'boolean') return {bit0:bits.bit0,bit1:bits.bit1};
  } catch { /* Malformed provider responses fail closed. */ }
  throw new DeviceProviderError('APPLE_MALFORMED');
}
