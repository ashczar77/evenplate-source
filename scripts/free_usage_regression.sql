-- Run in a transaction and roll back. No customer accounts are modified.
do $$ begin
 if exists(select 1 from auth.users where id in ('00000000-0000-4000-8000-000000000301','00000000-0000-4000-8000-000000000302','00000000-0000-4000-8000-000000000303')) then raise exception 'Usage fixture IDs already exist'; end if;
 if has_schema_privilege('authenticated','private','usage') or has_function_privilege('authenticated','private.quota_identity(text,uuid)','execute') then raise exception 'Private quota identity accessible to client'; end if;
 if private.quota_identity('a.b+fixture@gmail.com',null)<>private.quota_identity('ab+other@googlemail.com',null) then raise exception 'Gmail aliases not grouped'; end if;
 if private.quota_identity('ab+fixture@company.example',null)=private.quota_identity('ab@company.example',null) then raise exception 'Custom-domain plus address incorrectly merged'; end if;
 if private.quota_identity('a.b@company.example',null)=private.quota_identity('ab@company.example',null) then raise exception 'Custom-domain dots incorrectly merged'; end if;
end $$;
insert into auth.users(id,email) values('00000000-0000-4000-8000-000000000301','evenplate.quota.fixture+one@gmail.com');
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000301',true);
select public.consume_scan_credit();
select public.consume_food_score_credit();
insert into auth.users(id,email) values('00000000-0000-4000-8000-000000000302','evenplatequotafixture+two@googlemail.com');
do $$ begin
 if (select free_scans_remaining from public.profiles where id='00000000-0000-4000-8000-000000000302')<>2 then raise exception 'Alias received fresh photo allowance'; end if;
 if (select text_included_remaining from public.profiles where id='00000000-0000-4000-8000-000000000302')<>19 then raise exception 'Alias received fresh text allowance'; end if;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000302',true);
select public.consume_scan_credit();
select public.refund_scan_credit('00000000-0000-4000-8000-000000000302',false);
select public.consume_scan_credit();
delete from auth.users where id='00000000-0000-4000-8000-000000000301';
insert into auth.users(id,email) values('00000000-0000-4000-8000-000000000303','evenplate.quota.fixture@gmail.com');
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000303',true);
do $$ declare q jsonb; identity text; begin
 q:=public.get_my_quota();
 if (q->>'free_scans_remaining')::int<>1 or (q->>'text_included_remaining')::int<>19 then raise exception 'Deletion and re-registration reset credits: %',q; end if;
 q:=public.reserve_analysis_request('00000000-0000-4000-8000-000000000401','photo');
 if q->>'allowed'<>'true' then raise exception 'Last shared credit unavailable'; end if;
 perform public.settle_analysis_request('00000000-0000-4000-8000-000000000303','00000000-0000-4000-8000-000000000401',true,'{}');
 q:=public.consume_scan_credit();
 if q->>'allowed'<>'false' then raise exception 'Shared allowance overspent'; end if;
 identity:=private.quota_identity('evenplatequotafixture@gmail.com',null);
 if (select photo_used from private.free_week_usage where identity_key=identity and quota_week=date_trunc('week',now() at time zone 'UTC')::date)<>3 then raise exception 'Shared usage not durable'; end if;
 update public.profiles set is_pro=true,subscription_expires_at=now()+interval '1 day',free_scans_remaining=75,text_included_remaining=100 where id='00000000-0000-4000-8000-000000000303';
 q:=public.consume_scan_credit();
 if q->>'allowed'<>'true' or (q->>'photo_remaining')::int<>74 then raise exception 'Free protection affected paid allowance'; end if;
 update public.profiles set is_pro=false,subscription_expires_at=now()-interval '1 second',free_scans_remaining=3,text_included_remaining=20,photo_purchased=1 where id='00000000-0000-4000-8000-000000000303';
 q:=public.consume_scan_credit();
 if q->>'allowed'<>'true' or q->>'used_purchased'<>'true' then raise exception 'Free protection affected purchased credits'; end if;
 insert into private.free_week_usage(identity_key,quota_week,expires_at) values(identity,current_date-21,now()-interval '1 hour');
 perform public.expire_free_usage();
 if exists(select 1 from private.free_week_usage where expires_at<=now()) then raise exception 'Expired identity records not removed'; end if;
 if not exists(select 1 from private.free_week_usage where identity_key=identity and quota_week=date_trunc('week',now() at time zone 'UTC')::date) then raise exception 'Current usage expired early'; end if;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000302',true);
do $$ declare q jsonb; begin
 q:=public.get_my_quota();
 if (q->>'free_scans_remaining')::int<>0 then raise exception 'Other alias retained stale spendable allowance'; end if;
 q:=public.consume_scan_credit();
 if q->>'allowed'<>'false' then raise exception 'Other alias bypassed shared limit'; end if;
end $$;
