import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {execFileSync} from 'node:child_process';
import {webcrypto} from 'node:crypto';
globalThis.crypto ??= webcrypto;
const dir=fs.mkdtempSync(path.join(os.tmpdir(),'ep-device-handler-'));
const pair=await crypto.subtle.generateKey({name:'ECDSA',namedCurve:'P-256'},true,['sign','verify']);
const pem=`-----BEGIN PRIVATE KEY-----\n${Buffer.from(await crypto.subtle.exportKey('pkcs8',pair.privateKey)).toString('base64')}\n-----END PRIVATE KEY-----`;
const env={SUPABASE_URL:'https://test.invalid',SUPABASE_SERVICE_ROLE_KEY:'test',DEVICECHECK_PRIVATE_KEY_BASE64:Buffer.from(pem).toString('base64'),DEVICECHECK_KEY_ID:'TEST',DEVICECHECK_TEAM_ID:'TEAM'};
globalThis.Deno={env:{get:key=>env[key]}};
let handler,claim,eligible=new Set(),enabled=true,paid=false,confirmed=true,bits={bit0:false,bit1:false},updateFail=false,queryMalformed=false,calls=[],updates=[];
globalThis.__serve=fn=>handler=fn;
globalThis.__createClient=()=>({auth:{getUser:async token=>token==='bad'?{data:{user:null},error:{}}:{data:{user:{id:token,email_confirmed_at:confirmed?'date':null}}}},rpc:async(name,args)=>{
 calls.push(name);
 if(name==='device_access_status')return {data:{enabled,paid,eligible:!enabled||eligible.has(args.p_user_id),environment:'production'}};
 if(name==='take_device_verification_attempt')return {data:true};
 if(name==='record_device_verification')return {data:null};
 if(name==='begin_device_admission'){
  if(eligible.has(args.p_user_id))return {data:{status:'eligible'}};
  if(claim&&claim.user!==args.p_user_id)return {data:{status:'busy'}};
  claim??={user:args.p_user_id,operation:'operation',bit:null,token:args.p_token};
  return {data:{...claim,status:'claim'}};
 }
 if(name==='select_device_admission_bit'){claim.bit??=args.p_bit;return {data:claim.bit};}
 if(name==='finish_device_admission'){eligible.add(claim.user);claim=null;return {data:true};}
 if(name==='abort_device_admission'){if(claim?.bit===null){claim=null;return {data:true};}return {data:false};}
 throw new Error(name);
}});
globalThis.fetch=async(url,options)=>{
 const body=JSON.parse(options.body);
 if(String(url).endsWith('validate_device_token'))return new Response('');
 if(String(url).endsWith('query_two_bits'))return new Response(JSON.stringify(queryMalformed?{}:bits));
 if(String(url).endsWith('update_two_bits')){
  updates.push(body);
  if(updateFail)return new Response('failure',{status:503});
  if(body.bit0===true)bits.bit0=true;
  if(body.bit1===true)bits.bit1=true;
  return new Response('');
 }
 throw new Error('unexpected transport');
};
try{
 let source=fs.readFileSync('supabase/functions/device-access/index.ts','utf8').replace(/import \{ serve \} from "[^"]+";/,'const serve=globalThis.__serve;').replace(/import \{ createClient \} from "[^"]+";/,'const createClient=globalThis.__createClient;').replace(/from ['"](\.\.?\/[^'"]+)['"]/g,(_,file)=>`from ${JSON.stringify(path.resolve('supabase/functions/device-access',file))}`);
 const entry=path.join(dir,'entry.ts'),out=path.join(dir,'handler.mjs');fs.writeFileSync(entry,source);
 execFileSync('npx',['-y','esbuild@0.23.1',entry,'--bundle','--platform=node','--format=esm',`--outfile=${out}`,'--log-level=warning']);await import(out);
 let count=0;
 const check=(value,label)=>{assert.ok(value,label);count++;};
 const post=(action='claim',user='one',token='dG9rZW4=')=>handler(new Request('https://test.invalid',{method:'POST',headers:{Authorization:`Bearer ${user}`},body:JSON.stringify({action,token})}));
 check((await post('claim','bad')).status===401,'unauthenticated calls denied');
 confirmed=false;check((await post()).status===401,'unconfirmed accounts cannot consume device slots');confirmed=true;
 check((await post('unknown')).status===400,'unknown action rejected');
 check((await post('claim','one','invalid token')).status===400,'invalid token does not begin admission');
 check(!claim,'invalid requests never acquire admission');
 enabled=false;check((await post()).status===200&&!updates.length,'disabled controls never consume Apple slots');enabled=true;
 paid=true;check((await post()).status===200&&!updates.length,'paid entitlement bypasses device admission');paid=false;
 check((await post('verify')).status===200&&!updates.length&&!eligible.size,'verification-only proves a token without granting or spending a slot');
 check((await post()).status===200&&bits.bit0&&!bits.bit1,'first mailbox qualifies first slot');
 check((await post()).status===200&&updates.length===1,'repeat qualification does not consume another slot');
 check((await post('claim','two')).status===200&&bits.bit1,'second mailbox qualifies second slot');
 check((await post('claim','three')).status===403&&!eligible.has('three'),'third mailbox denied free qualification');
 check(updates.every(body=>!Object.values(body).includes(false)),'updates never reset either bit');
 eligible=new Set();bits={bit0:false,bit1:false};queryMalformed=true;
 check((await post()).status===503&&!claim,'malformed Apple state fails closed and releases unselected admission');queryMalformed=false;
 updateFail=true;check((await post()).status===503&&claim?.bit===0,'uncertain update remains durable');
 check((await post('claim','two')).status===503&&!eligible.has('two'),'other mailbox cannot pass an uncertain admission');
 updateFail=false;check((await post()).status===200&&eligible.has('one')&&!claim,'same mailbox recovers pending update idempotently');
 console.log(`${count} DeviceCheck handler checks passed.`);
}finally{fs.rmSync(dir,{recursive:true,force:true});}
