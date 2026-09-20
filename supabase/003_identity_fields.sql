-- Ejecutar después de schema.sql y 002_admin_analytics.sql.
begin;
alter table public.profiles add column if not exists first_name text not null default '' check(length(first_name)<=80);
alter table public.profiles add column if not exists last_name text not null default '' check(length(last_name)<=100);
alter table public.profiles add column if not exists document_type text not null default 'DNI' check(document_type in ('DNI','CE'));
alter table public.profiles add column if not exists document_number text not null default '' check(document_number ~ '^[0-9A-Za-z-]{0,15}$');
update public.profiles set first_name=split_part(name,' ',1),last_name=trim(substr(name,length(split_part(name,' ',1))+1)) where first_name='';
revoke update on public.profiles from authenticated;
grant update(name,first_name,last_name,company,document_type,document_number,phone,settings) on public.profiles to authenticated;
create or replace function public.new_user_profile() returns trigger language plpgsql security definer set search_path='' as $$ begin
 insert into public.profiles(id,name,first_name,last_name,company,document_type,document_number,phone,email)
 values(new.id,left(trim(concat(coalesce(new.raw_user_meta_data->>'first_name',''),' ',coalesce(new.raw_user_meta_data->>'last_name',''))),100),left(coalesce(new.raw_user_meta_data->>'first_name',''),80),left(coalesce(new.raw_user_meta_data->>'last_name',''),100),left(coalesce(new.raw_user_meta_data->>'company',''),150),case when new.raw_user_meta_data->>'document_type'='CE' then 'CE' else 'DNI' end,left(regexp_replace(coalesce(new.raw_user_meta_data->>'document_number',''),'[^0-9A-Za-z-]','','g'),15),left(coalesce(new.raw_user_meta_data->>'phone',''),30),coalesce(new.email,''));return new;
end; $$;
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
 'directory',(select coalesce(jsonb_agg(x order by x.created_at desc),'[]'::jsonb) from (select p.id,p.name,p.first_name,p.last_name,p.email,p.company,p.document_type,p.document_number,p.phone,p.created_at,(select count(*) from public.entries e where e.user_id=p.id) as entries,(select coalesce(sum(minutes),0) from public.entries e where e.user_id=p.id) as earned,(select coalesce(sum(minutes),0) from public.rests r where r.user_id=p.id and r.status='taken') as used,(select max(started_at) from public.site_visits v where v.user_id=p.id) as last_visit from public.profiles p) x)
 ) into result;return result;
end;$$;
revoke all on function public.admin_dashboard() from public;
grant execute on function public.admin_dashboard() to authenticated;
commit;

