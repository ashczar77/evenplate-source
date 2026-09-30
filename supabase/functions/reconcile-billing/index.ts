import { reportAnalyzeIssue } from "../analyze-plate/sentry.ts";
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";
serve(async(req)=>{
 const json=(body:unknown,status:number)=>new Response(JSON.stringify(body),{status,headers:{"Content-Type":"application/json"}});
 if(req.method!=="POST")return json({error:"Method not allowed"},405);
 const key=Deno.env.get("REVENUECAT_SECRET_API_KEY");
 if(!key)return json({error:"Billing reconciliation unavailable"},503);
 const admin=createClient(Deno.env.get("SUPABASE_URL")!,Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
 const {data,error}=await admin.auth.getUser(req.headers.get("Authorization")?.replace(/^Bearer /,"")??"");
 if(error||!data.user)return json({error:"Unauthorized"},401);
 try {
  // Timestamp precedes the fetch, so a later webhook wins over this snapshot.
  const observedAt=Date.now();
  const response=await fetch(`https://api.revenuecat.com/v1/subscribers/${data.user.id}`,{headers:{Authorization:`Bearer ${key}`},signal:AbortSignal.timeout(6000)});
  if(!response.ok)return json({error:"Billing provider unavailable"},503);
  const info=await response.json();
  const entitlement=info.subscriber?.entitlements?.[Deno.env.get("REVENUECAT_ENTITLEMENT")??"evenplate_pro"];
  const expiry=entitlement?.expires_date??null;
  const pro=!!entitlement&&(expiry===null||Date.parse(expiry)>Date.now());
  const product=entitlement?.product_identifier;
  const sandbox=product&&info.subscriber?.subscriptions?.[product]?.is_sandbox===true;
  const environment=entitlement?(sandbox?"SANDBOX":"PRODUCTION"):"UNKNOWN";
  const {data:applied,error:applyError}=await admin.rpc("apply_revenuecat_event",{p_event_id:`reconcile:${data.user.id}:${observedAt}`,p_event_type:"RECONCILE",p_environment:environment,p_candidate_ids:[data.user.id],p_is_pro:pro,p_expires_at:expiry,p_event_ms:observedAt});
  if(applyError||applied?.status==="no_profile")return json({error:"Billing sync pending"},503);
  await admin.rpc("refresh_user_quota",{p_user_id:data.user.id});
  return json({ok:true},200);
 }catch{await reportAnalyzeIssue(Deno.env.get("SENTRY_DSN")??"",{feature:"billing.reconcile_failed",code:"RECONCILE_FAILED",source:"reconcile-billing"});return json({error:"Billing provider unavailable"},503);}
});
