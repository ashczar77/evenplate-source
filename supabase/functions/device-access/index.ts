import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";
import { reportAnalyzeIssue } from '../analyze-plate/sentry.ts';
import { appleDeviceRequest, deviceJWT, DeviceEnvironment, DeviceProviderError, validDeviceToken } from './apple.ts';

serve(async (req) => {
  const json = (body:unknown,status=200) => new Response(JSON.stringify(body),{status,headers:{'Content-Type':'application/json','Cache-Control':'no-store'}});
  if (req.method !== 'POST') return json({code:'METHOD_NOT_ALLOWED'},405);
  const admin = createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,{auth:{persistSession:false,autoRefreshToken:false}});
  const {data:{user},error} = await admin.auth.getUser(req.headers.get('Authorization')?.replace(/^Bearer /,'')??'');
  if (error || !user || !user.email_confirmed_at) return json({code:'AUTH',error:'Confirm your email before verifying this device.'},401);
  let operation: string | null = null;
  let stage = "status";
  try {
    const text = await req.text();
    if (text.length>20000) return json({code:'BAD_REQUEST'},400);
    let body;
    try { body=JSON.parse(text); } catch { return json({code:'BAD_REQUEST'},400); }
    if (!body || typeof body !== 'object') return json({code:'BAD_REQUEST'},400);
    if (!['status','claim','verify'].includes(body.action)) return json({code:'BAD_REQUEST'},400);
    const statusResult = await admin.rpc('device_access_status',{p_user_id:user.id});
    if (statusResult.error || !statusResult.data) throw new Error('STATUS_UNAVAILABLE');
    const state = statusResult.data;
    const environment: DeviceEnvironment = state.environment;
    if (environment !== 'production' && environment !== 'development') throw new Error('ENVIRONMENT_UNAVAILABLE');
    if (body.action === 'status') return json(state);
    if (body.action === 'claim' && (!state.enabled || state.eligible || state.paid)) return json({...state,ok:true});
    if (!validDeviceToken(body.token)) return json({code:'BAD_REQUEST'},400);
    const key = Deno.env.get('DEVICECHECK_PRIVATE_KEY_BASE64');
    const keyId = Deno.env.get('DEVICECHECK_KEY_ID');
    const teamId = Deno.env.get('DEVICECHECK_TEAM_ID');
    if (!key || !keyId || !teamId) return json({code:'DEVICE_UNAVAILABLE',error:'Device verification is temporarily unavailable. Please retry.'},503);
    const attempt = await admin.rpc('take_device_verification_attempt',{p_user_id:user.id});
    if (attempt.error) throw new Error('ATTEMPT_UNAVAILABLE');
    if (attempt.data !== true) return json({code:'DEVICE_BUSY',error:'Too many verification attempts. Please retry later or contact support.'},429);
    stage = 'validate';
    const jwt = await deviceJWT(key,keyId,teamId);
    await appleDeviceRequest(jwt,environment,'validate_device_token',body.token);
    if (body.action === 'verify') {
      stage = 'query';
      await appleDeviceRequest(jwt,environment,'query_two_bits',body.token);
      const result = await admin.rpc('record_device_verification',{p_user_id:user.id,p_environment:environment});
      if (result.error) throw new Error('RECEIPT_UNAVAILABLE');
      return json({ok:true,environment});
    }
    stage = 'begin';
    const started = await admin.rpc('begin_device_admission',{p_user_id:user.id,p_token:body.token,p_environment:environment});
    if (started.error || !started.data) throw new Error(`ADMISSION_${started.error?.code??'UNAVAILABLE'}`);
    const claim = started.data;
    if (claim.status === 'eligible') return json({ok:true,eligible:true});
    if (claim.status === 'busy') return json({code:'DEVICE_BUSY',error:'Device verification is processing. Please try again shortly.'},503);
    if (claim.status === 'support') return json({code:'DEVICE_SUPPORT',error:'Please contact evenplatesupport@gmail.com to recover free access.'},409);
    if (claim.status !== 'claim') throw new Error('ADMISSION_UNAVAILABLE');
    operation = claim.operation;
    let bit = claim.bit;
    if (bit === null) {
      stage = 'query';
      const bits = await appleDeviceRequest(jwt,environment,'query_two_bits',claim.token);
      if (!bits || (bits.bit0 && bits.bit1)) {
        await admin.rpc('abort_device_admission',{p_operation:operation});
        return json({code:'DEVICE_LIMIT',error:'This iPhone has already qualified two free accounts. Paid access is still available. Contact support if you need help.'},403);
      }
      stage = 'select';
      const selected = await admin.rpc('select_device_admission_bit',{p_operation:operation,p_bit:bits.bit0?1:0});
      if (selected.error || ![0,1].includes(selected.data)) throw new Error('ADMISSION_UNAVAILABLE');
      bit = selected.data;
    }
    stage = 'update';
    await appleDeviceRequest(jwt,environment,'update_two_bits',claim.token,bit);
    stage = 'finish';
    const finished = await admin.rpc('finish_device_admission',{p_operation:operation});
    if (finished.error) throw new Error('SETTLEMENT_UNAVAILABLE');
    if (finished.data !== true) {
      const retry = await admin.rpc('device_access_status',{p_user_id:user.id});
      if (retry.error || retry.data?.eligible !== true) throw new Error('SETTLEMENT_UNAVAILABLE');
    }
    return json({ok:true,eligible:true});
  } catch (error) {
    const diagnostic = error instanceof DeviceProviderError ? error.code : error instanceof Error && /^[A-Z_0-9]{1,64}$/.test(error.message) ? error.message : "UNEXPECTED";
    console.warn(`DeviceCheck ${stage}: ${diagnostic}`);
    // Token and provider-response contents must never enter logs or diagnostics.
    const aborted = operation ? await admin.rpc('abort_device_admission',{p_operation:operation}) : null;
    await reportAnalyzeIssue(Deno.env.get('SENTRY_DSN')??'',{feature:'device.verification',code:operation && aborted?.data !== true?'DEVICE_ADMISSION_UNCERTAIN':'DEVICE_VERIFICATION_FAILED',source:'device-access',detail:`${stage}:${diagnostic}`});
    return json({code:'DEVICE_UNAVAILABLE',error:'Device verification is temporarily unavailable. Please retry, or contact support.'},503);
  }
});
