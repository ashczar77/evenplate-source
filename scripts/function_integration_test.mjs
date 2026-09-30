// Exercises deployed handler control flow with isolated provider transports.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
const root = process.cwd();
const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'evenplate-handlers-'));
let handler;
let loadVersion=0;
let rpcCalls = [];
let reserve = { allowed: true, is_pro: false, remaining: 2, text_remaining: 19 };
let settleError = null;
let settleResult = {ok:true};
let missingUserError = null;
const deletedUsers = [];
const env = {USDA_API_KEY:'test', SUPABASE_URL:'https://test.invalid', SUPABASE_ANON_KEY:'public-test', SUPABASE_SERVICE_ROLE_KEY:'private-test', GEMINI_API_KEY:'test', REVENUECAT_WEBHOOK_SECRET:'test', REVENUECAT_ALLOW_SANDBOX:'true', ONESIGNAL_REST_API_KEY:'test', ONESIGNAL_APP_ID:'test', REVENUECAT_SECRET_API_KEY:'test' };
globalThis.Deno = {env:{get:(key)=>env[key]}};
globalThis.__serve = (callback)=>{handler=callback;};
globalThis.__createClient = ()=>({
 auth:{getUser:async(token)=>missingUserError ? {data:{user:null},error:missingUserError} : token==='valid' ? {data:{user:{id:'00000000-0000-4000-8000-000000000101'}}} : {data:{user:null},error:{message:'invalid'}},admin:{deleteUser:async(id)=>{deletedUsers.push(id);return {error:null};}}},
 rpc:async(name,args)=>{
  rpcCalls.push({name,args});
  if(name==='reserve_analysis_request')return {data:reserve};
  if(name==='settle_analysis_request')return {data:settleResult,error:settleError};
  return {data:{ok:true,status:'applied'}};
 },
});
const analysis = {mealName:'Bean bowl',components:['Beans'],pillars:Object.fromEntries(['anchor','net','buffer','spark'].map(name=>[name,{detected:name==='anchor',items:name==='anchor'?['Beans']:[],quality:name==='anchor'?'high':'low'}])),satietyScore:45,durationHours:3,crashRisk:'moderate',captureIssue:'none',hybridUpgrade:{instantAdd:'Greens',smartSwap:'Beans',digestiveCatalyst:'Water'}};
let gemini = analysis;
let providerCalls = [];
let responseQueue = [];
globalThis.fetch = async(url, options)=> {
 if(String(url).includes('generativelanguage.googleapis.com')) providerCalls.push({url, body: JSON.parse(options.body)});
 const output = responseQueue.length ? responseQueue.shift() : gemini;
 return new Response(JSON.stringify({candidates:[{content:{parts:[{text:JSON.stringify(output)}]},finishReason:'STOP'}]}),{status:200});
};
async function load(name){
 let source=fs.readFileSync(path.join(root,`supabase/functions/${name}/index.ts`),'utf8');
 source=source.replace(/import \{ serve \} from "[^"]+";/,'const serve = globalThis.__serve;').replace(/import \{ createClient \} from "[^"]+";/,'const createClient = globalThis.__createClient;');
 source=source.replace(/from ['"](\.\.?\/[^'"]+)['"]/g,(_,file)=>`from ${JSON.stringify(path.resolve(root,`supabase/functions/${name}`,file))}`);
 const entry=path.join(temp,name+'.ts'),out=path.join(temp,name+'-'+(++loadVersion)+'.mjs');fs.writeFileSync(entry,source);
 execFileSync('npx',['-y','esbuild@0.23.1',entry,'--bundle','--platform=node','--format=esm',`--outfile=${out}`,'--log-level=warning']);
 await import(out);
}
async function post(body,token='valid'){
 return handler(new Request('https://test.invalid',{method:'POST',headers:{Authorization:`Bearer ${token}`,'Content-Type':'application/json'},body:JSON.stringify(body)}));
}
let checks=0;
function check(condition,message){assert.ok(condition,message);checks++;}
try {
 for(const name of ['analyze-foods','analyze-plate']){
  await load(name);rpcCalls=[];
  const body=name==='analyze-foods'?{analysisConsent:true,foods:['Beans'],requestId:'00000000-0000-4000-8000-000000000201'}:{analysisConsent:true,imageBase64:'AA==',mimeType:'image/jpeg',requestId:'00000000-0000-4000-8000-000000000201'};
  check((await post(body,'invalid')).status===401,`${name} rejects invalid identity`);
  check(rpcCalls.length===0,`${name} never charges unauthorized caller`);
  check((await post({...body,analysisConsent:false})).status===403,`${name} requires consent before charging`);
  check((await post({...body,requestId:'bad'})).status===400,`${name} validates identity before charging`);
  reserve={allowed:false,reason:'complete',response:analysis};
  const replay=await post(body);check(replay.status===200 && (await replay.json()).mealName==='Bean bowl',`${name} replays settled result`);
  reserve={allowed:false,reason:'reserved'};check((await post(body)).status===409,`${name} reports processing without double charge`);
  reserve={allowed:true,is_pro:false,remaining:2,text_remaining:19};gemini={};rpcCalls=[];
  check((await post(body)).status===502,`${name} rejects incomplete model output`);
  check(rpcCalls.some(c=>c.name==='settle_analysis_request'&&c.args.p_success===false),`${name} refunds malformed result`);
  {
    providerCalls=[];responseQueue=[{},analysis];rpcCalls=[];
    check((await post(body)).status===200,`${name} malformed primary recovers through fallback`);
    check(providerCalls.length===2,`${name} malformed output retries only once`);
    check(providerCalls.every(call=>call.body.generationConfig.responseJsonSchema.required.includes('captureIssue')),`${name} every attempt enforces the response schema`);
    check(rpcCalls.filter(c=>c.name==='reserve_analysis_request').length===1,'fallback shares one credit reservation');
    check(!rpcCalls.some(c=>c.name==='settle_analysis_request'&&c.args.p_success===false),'recovered fallback does not refund a successful scan');
  }
  gemini=analysis;rpcCalls=[];
  check((await post(body)).status===200,`${name} returns valid result`);
  check(rpcCalls.some(c=>c.name==='settle_analysis_request'&&c.args.p_success===true),`${name} persists settlement before success`);
  const sourced=await (await post(body)).json();
  check(sourced.assessmentMethod==='gemini-meal-v1',`${name} identifies the scoring method`);
    check(sourced.durationHours===0 && sourced.satietyScore===analysis.satietyScore,`${name} preserves relative rating independently of optional range`);
    gemini={...analysis,fullnessEstimate:{minHours:2,maxHours:4,portion:'regular',basis:'model_regular_portion_v1'}};
    providerCalls=[];
    const estimated=await (await post(body)).json();
    check(estimated.fullnessEstimate?.maxHours===4 && estimated.satietyScore===analysis.satietyScore,`${name} retains separate regular-portion range without changing score`);
    check(providerCalls.length===1 && providerCalls[0].body.contents[0].parts.some(p=>p.text?.includes('ONE regular-sized meal')),`${name} estimate uses the same assessment request`);
    gemini={...gemini,fullnessEstimate:{...gemini.fullnessEstimate,maxHours:16}};
    const invalidRange=await (await post(body)).json();
    check(invalidRange.fullnessEstimate===null && invalidRange.satietyScore===analysis.satietyScore,`${name} drops invalid hours without breaking the successful score`);
    gemini=analysis;
  delete env.USDA_API_KEY;rpcCalls=[];
  check((await post(body)).status===200,`${name} has no USDA hot-path dependency`);
  env.USDA_API_KEY='test';
  settleResult={ok:false,reason:'missing_request'};
  check((await post(body)).status>=500,`${name} never reports success without durable settlement`);
  settleResult={ok:true};
 }
 await load('analyze-foods');
 rpcCalls=[];
 check((await post({analysisConsent:true,foods:Array.from({length:41},(_,i)=>'Food '+i)})).status===400,'oversized composition is rejected before charging');
 check((await post({analysisConsent:true,foods:['x'.repeat(61)]})).status===400,'oversized description is not silently truncated');
 check(rpcCalls.length===0,'invalid input cannot consume a credit');
 providerCalls=[];rpcCalls=[];gemini=analysis;
 const edit={analysisConsent:true,foods:['Beans'],originalAnalysis:{...analysis,assessmentNote:'Large bean bowl'},requestId:'00000000-0000-4000-8000-000000000203'};
 check((await post(edit)).status===200,'edited assessment succeeds with original context');
 check(providerCalls[0].body.contents[0].parts[0].text.includes('Large bean bowl'),'original portion observations are retained in the edit request');
 gemini={...analysis,components:['Unrelated food']};rpcCalls=[];
 check((await post(edit)).status===502,'a semantic composition mismatch is refused');
 check(rpcCalls.some(c=>c.name==='settle_analysis_request'&&c.args.p_success===false),'composition mismatch refunds the request');
 gemini={...analysis,satietyScore:1000};rpcCalls=[];
 check((await post(edit)).status===502,'out-of-range provider rating is refused');
 check(rpcCalls.some(c=>c.name==='settle_analysis_request'&&c.args.p_success===false),'invalid rating refunds the request');
 gemini=analysis;
 await load('revenuecat-webhook');rpcCalls=[];
 const event={id:'test-event',type:'NON_RENEWING_PURCHASE',environment:'PRODUCTION',event_timestamp_ms:Date.now(),app_user_id:'00000000-0000-4000-8000-000000000101',product_id:'scan_pack_25',transaction_id:'store-transaction',store:'APP_STORE'};
 const webhook=(value,authorization='Bearer test')=>handler(new Request('https://test.invalid',{method:'POST',headers:{Authorization:authorization},body:JSON.stringify({event:value})}));
 check((await webhook(event,'invalid')).status===401,'webhook rejects forged purchase');
 check(rpcCalls.length===0,'forged purchase never grants credits');
 check((await webhook({...event,type:'PRODUCT_CHANGE'})).status===200,'nonpurchase pack event acknowledged');
 check(rpcCalls.length===0,'nonpurchase never grants credits');
 check((await webhook(event)).status===200,'pack purchase accepted');
 check(rpcCalls.at(-1).args.p_transaction==='PRODUCTION:APP_STORE:store-transaction','pack idempotency follows store transaction');
 await webhook({...event,id:'refund-event',type:'CANCELLATION'});
 check(rpcCalls.at(-1).args.p_refund===true,'pack refund reverses rather than granting');
 globalThis.Deno.serve=globalThis.__serve;
 await load('legal');
 for(const document of ['privacy','terms','support']){
  const page=await handler(new Request(`https://test.invalid?document=${document}`));
  check(page.status===200 && (await page.text()).includes('evenplatesupport@gmail.com'),`${document} is readable without authentication`);
 }
 check((await handler(new Request('https://test.invalid?document=__proto__'))).status===404,'unknown policy names are rejected');
 check((await handler(new Request('https://test.invalid',{method:'POST'}))).status===405,'public pages reject writes');
 const head=await handler(new Request('https://test.invalid',{method:'HEAD'}));
 check(head.status===200 && (await head.text())==='','HEAD returns no document body');
 await load('delete-account');
 check((await post({},'invalid')).status===401,'account deletion rejects invalid authentication');
 const deleted=await post({});
 check(deleted.status===200 && (await deleted.json()).deleted===true,'account deletion completes vendor and Auth removal');
 check(deletedUsers.join(',')==='00000000-0000-4000-8000-000000000101','account deletion removes only its authenticated owner');
 missingUserError={code:'user_not_found',status:403};
 const claims={sub:'00000000-0000-4000-8000-000000000101',role:'authenticated',iss:'https://test.invalid/auth/v1'};
 const deletedToken=(payload)=>`${btoa('{}')}.${btoa(JSON.stringify(payload))}.validated-by-auth`;
 check((await post({},deletedToken(claims))).status===200,'deleted account can safely retry with its still-valid token');
 check(deletedUsers.length===1,'deletion retry cannot issue a second Auth removal');
 check((await post({},deletedToken({...claims,iss:'https://another-project.invalid/auth/v1'}))).status===401,'deletion retry rejects another issuer');
 check((await post({},'malformed')).status===401,'deletion retry rejects malformed claims');
 missingUserError={status:403,message:'User from sub claim in JWT does not exist'};
 check((await post({},deletedToken(claims))).status===200,'deletion retry supports legacy Auth error responses');
 missingUserError=null;
 console.log(`${checks} handler integration checks passed`);
}finally{fs.rmSync(temp,{recursive:true,force:true});}
