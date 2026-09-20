-- Ejecutar después de 003_identity_fields.sql. Consolidados, aprobaciones y trazabilidad administrativa.
begin;
create or replace function public.admin_dashboard() returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 if not public.is_admin() then raise exception 'Solo el administrador puede consultar las estadísticas.';end if;
 select jsonb_build_object(
 'registered',(select count(*) from public.profiles),'new30',(select count(*) from public.profiles where created_at>=now()-interval '30 days'),
 'active30',(select count(distinct user_id) from (select user_id from public.site_visits where started_at>=now()-interval '30 days' and user_id is not null union select user_id from public.entries where updated_at>=now()-interval '30 days') q),
 'sessions30',(select count(*) from public.site_visits where started_at>=now()-interval '30 days'),'visitors30',(select count(distinct visitor_id) from public.site_visits where started_at>=now()-interval '30 days'),
 'entries',(select count(*) from public.entries),'earned',(select coalesce(sum(minutes),0) from public.entries),'used',(select coalesce(sum(minutes),0) from public.rests where status='taken'),'reserved',(select coalesce(sum(minutes),0) from public.rests where status='approved'),
 'daily',(select coalesce(jsonb_agg(x order by x.day),'[]'::jsonb) from (select (started_at at time zone 'America/Lima')::date as day,count(*) as sessions,count(distinct visitor_id) as visitors from public.site_visits where started_at>=now()-interval '30 days' group by 1) x),
 'sources',(select coalesce(jsonb_agg(x),'[]'::jsonb) from (select source,count(*) as total from public.site_visits where started_at>=now()-interval '30 days' group by source order by total desc) x),
 'devices',(select coalesce(jsonb_agg(x),'[]'::jsonb) from (select device,count(*) as total from public.site_visits where started_at>=now()-interval '30 days' group by device order by total desc) x),
 'directory',(select coalesce(jsonb_agg(x order by x.created_at desc),'[]'::jsonb) from (select p.id,p.name,p.first_name,p.last_name,p.email,p.company,p.document_type,p.document_number,p.phone,p.created_at,(select count(*) from public.entries e where e.user_id=p.id) entries,(select coalesce(sum(minutes),0) from public.entries e where e.user_id=p.id) earned,(select coalesce(sum(minutes),0) from public.rests r where r.user_id=p.id and r.status='requested') requested,(select coalesce(sum(minutes),0) from public.rests r where r.user_id=p.id and r.status='approved') approved,(select coalesce(sum(minutes),0) from public.rests r where r.user_id=p.id and r.status='taken') used from public.profiles p) x),
 'pending',(select coalesce(jsonb_agg(x order by x.date,x.name),'[]'::jsonb) from (select r.id,r.user_id,r.date,r.minutes,r.status,r.payload->>'comment' comment,r.updated_at,p.name,p.company from public.rests r join public.profiles p on p.id=r.user_id where r.status='requested') x),
 'rests',(select coalesce(jsonb_agg(x order by x.date desc),'[]'::jsonb) from (select r.id,r.user_id,r.date,r.minutes,r.status,r.payload->>'comment' comment,r.updated_at,p.name from public.rests r join public.profiles p on p.id=r.user_id) x),
 'audit',(select coalesce(jsonb_agg(x order by x.at desc),'[]'::jsonb) from (select a.id,a.at,a.actor,a.user_id,a.table_name,a.operation,a.old_row->>'status' old_status,a.new_row->>'status' new_status,p.name user_name,coalesce(ap.name,'Administrador') actor_name from public.audit_log a left join public.profiles p on p.id=a.user_id left join public.profiles ap on ap.id=a.actor order by a.at desc limit 200) x)
 ) into result;return result;
end;$$;
revoke all on function public.admin_dashboard() from public;
grant execute on function public.admin_dashboard() to authenticated;
commit;

