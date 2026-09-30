-- Run after schema.sql inside a transaction that is always rolled back.
do $$ begin
  if exists(select 1 from auth.users where id in (
    '00000000-0000-4000-8000-000000000103',
    '00000000-0000-4000-8000-000000000104',
    '00000000-0000-4000-8000-000000000105'
  )) then raise exception 'Promo fixture IDs already exist'; end if;
end $$;

insert into auth.users(id,email) values
  ('00000000-0000-4000-8000-000000000103','promo-fixture-a@invalid.example'),
  ('00000000-0000-4000-8000-000000000104','promo-fixture-b@invalid.example'),
  ('00000000-0000-4000-8000-000000000105','promo-fixture-c@invalid.example');

insert into public.promo_codes(code_hash,label,max_redemptions,grants_days,expires_at) values
  (encode(extensions.digest('FIXTURE-PROMO-CAP','sha256'),'hex'),'promo-cap-fixture',2,90,now()+interval '1 day'),
  (encode(extensions.digest('FIXTURE-PROMO-EXPIRED','sha256'),'hex'),'promo-expiry-fixture',2,90,now()-interval '1 second');

select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000103',true);
do $$ declare q jsonb; first_until timestamptz; begin
  q := public.redeem_promo_code('FIXTURE-PROMO-EXPIRED');
  if q->>'redeemed'<>'false' then raise exception 'Expired code accepted'; end if;
  q := public.redeem_promo_code('FIXTURE-PROMO-WRONG');
  if q->>'redeemed'<>'false' then raise exception 'Wrong code accepted'; end if;
  if exists(select 1 from public.promo_codes where label in ('promo-cap-fixture','promo-expiry-fixture') and redemption_count<>0) then
    raise exception 'Failed attempt consumed redemption capacity';
  end if;
  q := public.redeem_promo_code('  fixture-promo-cap  ');
  first_until := (q->>'until')::timestamptz;
  if q->>'redeemed'<>'true' or first_until<>now()+interval '90 days' then
    raise exception 'Normalized code did not grant 90 days';
  end if;
  update public.profiles set free_scans_remaining=10,text_included_remaining=20
    where id=auth.uid();
  q := public.redeem_promo_code('FIXTURE-PROMO-CAP');
  if q->>'duplicate'<>'true' or (q->>'until')::timestamptz<>first_until then
    raise exception 'Repeat redemption extended grant';
  end if;
  if (select redemption_count from public.promo_codes where label='promo-cap-fixture')<>1 then
    raise exception 'Repeat redemption consumed another slot';
  end if;
  if (select free_scans_remaining<>10 or text_included_remaining<>20 from public.profiles where id=auth.uid()) then
    raise exception 'Repeat redemption refilled credits';
  end if;
end $$;

select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000104',true);
do $$ declare q jsonb; begin
  q := public.redeem_promo_code('FIXTURE-PROMO-CAP');
  if q->>'redeemed'<>'true' then raise exception 'Last available slot rejected'; end if;
end $$;

select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000105',true);
do $$ declare q jsonb; begin
  q := public.redeem_promo_code('FIXTURE-PROMO-CAP');
  if q->>'redeemed'<>'false' then raise exception 'Exhausted code accepted new account'; end if;
  if (select redemption_count from public.promo_codes where label='promo-cap-fixture')<>2 then
    raise exception 'Exhausted code exceeded capacity';
  end if;
  if (select promo_pro_until is not null from public.profiles where id=auth.uid()) then
    raise exception 'Rejected account received Pro';
  end if;
end $$;

select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000103',true);
do $$ declare q jsonb; begin
  q := public.redeem_promo_code('FIXTURE-PROMO-CAP');
  if q->>'redeemed'<>'true' or q->>'duplicate'<>'true' then
    raise exception 'Existing recipient rejected at capacity';
  end if;
  update public.promo_redemptions set redeemed_at=now()-interval '91 days'
    where user_id=auth.uid() and code_id=(select id from public.promo_codes where label='promo-cap-fixture');
  q := public.redeem_promo_code('FIXTURE-PROMO-CAP');
  if q->>'redeemed'<>'false' then raise exception 'Expired grant renewed by repeat redemption'; end if;
end $$;
