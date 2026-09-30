import {appleDeviceRequest,deviceJWT,validDeviceToken} from '../supabase/functions/device-access/apple.ts';
function check(ok:unknown,label:string){if(!ok)throw new Error(label);console.log(`PASS ${label}`);}
async function rejects(work:()=>Promise<unknown>,label:string){let rejected=false;try{await work();}catch{rejected=true;}check(rejected,label);}
const pair = await crypto.subtle.generateKey({name:'ECDSA',namedCurve:'P-256'},true,['sign','verify']);
const der = new Uint8Array(await crypto.subtle.exportKey('pkcs8',pair.privateKey));
const pem = `-----BEGIN PRIVATE KEY-----\n${btoa(String.fromCharCode(...der))}\n-----END PRIVATE KEY-----`;
const jwt=await deviceJWT(btoa(pem),'TESTKEY','TESTTEAM',1700000000000);
const pieces=jwt.split('.');
const decode=(s:string)=>Uint8Array.from(atob(s.replace(/-/g,'+').replace(/_/g,'/')),c=>c.charCodeAt(0));
check(await crypto.subtle.verify({name:'ECDSA',hash:'SHA-256'},pair.publicKey,decode(pieces[2]),new TextEncoder().encode(pieces.slice(0,2).join('.'))),'Apple JWT has a valid ES256 signature');
check(JSON.parse(new TextDecoder().decode(decode(pieces[1]))).iat===1700000000,'JWT uses seconds rather than milliseconds');
check(!validDeviceToken('secret\n')&&!validDeviceToken('A'.repeat(16385)),'invalid and excessive tokens are rejected');
let request:Record<string,unknown>={};
const transport=async(url:unknown,options?:RequestInit)=>{request={url:String(url),body:JSON.parse(options?.body as string)};return new Response('{}');};
await appleDeviceRequest(jwt,'production','update_two_bits','dG9rZW4=',0,transport as typeof fetch);
const payload=request.body as Record<string,unknown>;
check(payload.bit0===true && !('bit1' in payload),'first slot update never resets the second slot');
check(String(request.url).startsWith('https://api.devicecheck.apple.com/'),'production endpoint cannot be supplied by a client');
await appleDeviceRequest(jwt,'development','update_two_bits','dG9rZW4=',1,transport as typeof fetch);
check((request.body as Record<string,unknown>).bit1===true && !('bit0' in (request.body as Record<string,unknown>)),'second slot update never resets the first slot');
const missing=await appleDeviceRequest(jwt,'production','query_two_bits','dG9rZW4=',undefined,(async()=>new Response('Bit State Not Found')) as typeof fetch);
check(missing?.bit0===false&&missing?.bit1===false,'new Apple devices begin with two unused slots');
const variant=await appleDeviceRequest(jwt,'production','query_two_bits','dG9rZW4=',undefined,(async()=>new Response('Failed to find bit state')) as typeof fetch);
check(variant?.bit0===false&&variant?.bit1===false,'observed Apple empty-state wording begins with two unused slots');
await rejects(()=>appleDeviceRequest(jwt,'production','query_two_bits','dG9rZW4=',undefined,(async()=>new Response('Failed to find bit state',{status:503})) as typeof fetch),'empty-state wording on a failed request cannot grant a slot');
await rejects(()=>appleDeviceRequest(jwt,'production','query_two_bits','dG9rZW4=',undefined,(async()=>new Response('{}')) as typeof fetch),'malformed Apple bits cannot grant a slot');
await rejects(()=>appleDeviceRequest(jwt,'production','update_two_bits','dG9rZW4=',0,(async()=>new Response('failure',{status:503})) as typeof fetch),'Apple outages do not imply successful writes');
await rejects(()=>appleDeviceRequest(jwt,'production','validate_device_token','dG9rZW4=',undefined,(async()=>{throw new Error('private response');}) as typeof fetch),'transport errors are sanitized');
console.log('DeviceCheck helper checks passed.');
