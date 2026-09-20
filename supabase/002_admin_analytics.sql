-- Ejecutar después de schema.sql. Métricas de uso y directorio administrativo.
begin;
alter table public.profiles add column if not exists email text not null default '';
update public.profiles p set email=u.email from auth.users u where p.id=u.id;
revoke update on public.profiles from authenticated;
grant update(name,company,phone,settings) on public.profiles to authenticated;
create or replace function public.new_user_profile() returns trigger language plpgsql security definer set search_path='' as $$ begin insert into public.profiles(id,name,company,phone,email) values(new.id,left(coalesce(new.raw_user_meta_data->>'name',''),100),left(coalesce(new.raw_user_meta_data->>'company',''),150),left(coalesce(new.raw_user_meta_data->>'phone',''),30),coalesce(new.email,''));return new;end; $$;
create or replace function public.sync_profile_email() returns trigger language plpgsql security definer set search_path='' as $$begin update public.profiles set email=coalesce(new.email,'') where id=new.id;return new;end;$$;
create trigger profile_email_updated after update of email on auth.users for each row execute function public.sync_profile_email();
create table public.site_visits(session_id uuid primary key,visitor_id uuid not null,user_id uuid references auth.users(id) on delete set null,source text not null check(source in ('direct','search','social','github','other')),device text not null check(device in ('mobile','tablet','desktop')),started_at timestamptz not null default now());
create index visits_started on public.site_visits(started_at);
create index visits_user_started on public.site_visits(user_id,started_at);
create index visits_visitor_started on public.site_visits(visitor_id,started_at);
alter table public.site_visits enable row level security;
revoke all on public.site_visits from anon,authenticated;
grant select on public.site_visits to authenticated;
create policy admin_visits on public.site_visits for select to authenticated using(public.is_admin());
create function public.record_visit(p_session uuid,p_visitor uuid,p_source text,p_device text) returns void language plpgsql security definer set search_path='' as $$begin
 if p_session is null or p_visitor is null or p_source is null or p_device is null or p_source not in ('direct','search','social','github','other') or p_device not in ('mobile','tablet','desktop') then return;end if;
 if exists(select 1 from public.site_visits where session_id=p_session) then
  if auth.uid() is not null then update public.site_visits set user_id=auth.uid() where session_id=p_session and visitor_id=p_visitor and user_id is null;end if;return;
 end if;
 if (select count(*) from public.site_visits where visitor_id=p_visitor and started_at>now()-interval '1 day')>=20 then return;end if;
 insert into public.site_visits(session_id,visitor_id,user_id,source,device) values(p_session,p_visitor,auth.uid(),p_source,p_device) on conflict do nothing;
end;$$;
revoke all on function public.record_visit(uuid,uuid,text,text) from public;
grant execute on function public.record_visit(uuid,uuid,text,text) to anon,authenticated;
create function public.admin_dashboard() returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 if not public.is_admin() then raise exception 'Solo el administrador puede consultar las estadísticas.';end if;
 select jsonb_build_object(
 'registered',(select count(*) from public.profiles),
 'new30',(select count(*) from public.profiles where created_at>=now()-interval '30 days'),
 'active30',(select count(distinct user_id) from (select user_id from public.site_visits where started_at>=now()-interval '30 days' and user_id is not null union select user_id from public.entries where updated_at>=now()-interval '30 days') q),
 'sessions30',(select count(*) from public.site_visits where started_at>=now()-interval '30 days'),
 'visitors30',(select count(distinct visitor_id) from public.site_visits where started_at>=now()-interval '30 days'),
 'entries',(select count(*) from public.entries),
 'earned',(select coalesce(sum(minutes),0) from public.entries),
 'used',(select coalesce(sum(minutes),0) from public.rests where status='taken'),
 'reserved',(select coalesce(sum(minutes),0) from public.rests where status='approved'),
 'daily',(select coalesce(jsonb_agg(x order by x.day),'[]'::jsonb) from (select (started_at at time zone 'America/Lima')::date as day,count(*) as sessions,count(distinct visitor_id) as visitors from public.site_visits where started_at>=now()-interval '30 days' group by 1) x),
 'sources',(select coalesce(jsonb_agg(x),'[]'::jsonb) from (select source,count(*) as total from public.site_visits where started_at>=now()-interval '30 days' group by source order by total desc) x),
 'devices',(select coalesce(jsonb_agg(x),'[]'::jsonb) from (select device,count(*) as total from public.site_visits where started_at>=now()-interval '30 days' group by device order by total desc) x),
 'directory',(select coalesce(jsonb_agg(x order by x.created_at desc),'[]'::jsonb) from (select p.id,p.name,p.email,p.company,p.phone,p.created_at,(select count(*) from public.entries e where e.user_id=p.id) as entries,(select coalesce(sum(minutes),0) from public.entries e where e.user_id=p.id) as earned,(select coalesce(sum(minutes),0) from public.rests r where r.user_id=p.id and r.status='taken') as used,(select max(started_at) from public.site_visits v where v.user_id=p.id) as last_visit from public.profiles p) x)
 ) into result;return result;
end;$$;
revoke all on function public.admin_dashboard() from public;
grant execute on function public.admin_dashboard() to authenticated;
revoke all on function public.sync_profile_email() from public,anon,authenticated;
commit;
