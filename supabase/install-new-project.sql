-- SOLO PARA UN PROYECTO NUEVO SIN TABLAS MYK2. Ejecutar una sola vez.
-- No contiene contraseñas ni claves privadas.
begin;
-- schema.sql
-- Ejecutar una vez en el SQL Editor de un proyecto Supabase nuevo.
create table public.admins(user_id uuid primary key references auth.users(id) on delete cascade);
alter table public.admins enable row level security;
revoke all on public.admins from anon, authenticated;
create function public.is_admin() returns boolean language sql stable security definer set search_path='' as $$ select exists(select 1 from public.admins where user_id=auth.uid()); $$;
revoke all on function public.is_admin() from public;
grant execute on function public.is_admin() to authenticated;
create table public.profiles(id uuid primary key references auth.users(id) on delete cascade,name text not null default '' check(length(name)<=100),company text not null default '' check(length(company)<=150),phone text not null default '' check(length(phone)<=30),settings jsonb not null default '{"dayHours":8,"schedule":["","16:00","16:00","17:00","17:00","17:00","12:00"]}',created_at timestamptz not null default now());
create table public.entries(id uuid primary key default gen_random_uuid(),user_id uuid not null references public.profiles(id) on delete cascade,date date not null,minutes integer not null check(minutes between 0 and 1440),payload jsonb not null,updated_at timestamptz not null default now(),unique(user_id,date));
create table public.rests(id uuid primary key default gen_random_uuid(),user_id uuid not null references public.profiles(id) on delete cascade,date date not null,minutes integer not null check(minutes between 1 and 1440),status text not null check(status in ('requested','approved','taken','cancelled')),payload jsonb not null,updated_at timestamptz not null default now());
create unique index one_active_rest_per_day on public.rests(user_id,date) where status<>'cancelled';
create index rests_user_date on public.rests(user_id,date);
create table public.audit_log(id bigint generated always as identity primary key,user_id uuid not null,actor uuid,table_name text not null,operation text not null,old_row jsonb,new_row jsonb,at timestamptz not null default now());
alter table public.profiles enable row level security;
alter table public.entries enable row level security;
alter table public.rests enable row level security;
alter table public.audit_log enable row level security;
create policy profile_read on public.profiles for select to authenticated using(id=auth.uid() or public.is_admin());
create policy profile_update on public.profiles for update to authenticated using(id=auth.uid() or public.is_admin()) with check(id=auth.uid() or public.is_admin());
create policy entries_access on public.entries for all to authenticated using(user_id=auth.uid() or public.is_admin()) with check(user_id=auth.uid() or public.is_admin());
create policy rests_access on public.rests for all to authenticated using(user_id=auth.uid() or public.is_admin()) with check(user_id=auth.uid() or public.is_admin());
create policy audit_read on public.audit_log for select to authenticated using(user_id=auth.uid() or public.is_admin());
revoke all on public.profiles,public.entries,public.rests,public.audit_log from anon,authenticated;
grant select,update on public.profiles to authenticated;
grant select,insert,update,delete on public.entries,public.rests to authenticated;
grant select on public.audit_log to authenticated;
create function public.new_user_profile() returns trigger language plpgsql security definer set search_path='' as $$ begin insert into public.profiles(id,name,company,phone) values(new.id,left(coalesce(new.raw_user_meta_data->>'name',''),100),left(coalesce(new.raw_user_meta_data->>'company',''),150),left(coalesce(new.raw_user_meta_data->>'phone',''),30));return new;end; $$;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.new_user_profile();
create function public.validate_time_record() returns trigger language plpgsql security definer set search_path='' as $$
declare uid uuid; earned bigint; spent bigint; start_min integer; end_min integer; pause_min integer; initial_time text; final_time text; kind text; delta_earned integer:=0; delta_spent integer:=0;
begin
 uid:=case when TG_OP='DELETE' then OLD.user_id else NEW.user_id end;
 perform pg_advisory_xact_lock(hashtextextended(uid::text,0));
 if TG_OP='UPDATE' and (NEW.user_id<>OLD.user_id or NEW.id<>OLD.id) then raise exception 'No se puede cambiar el propietario o identificador.';end if;
 if TG_OP<>'DELETE' then
  if length(coalesce(NEW.payload->>'comment',''))>1000 then raise exception 'Comentario demasiado largo.';end if;
  NEW.updated_at:=now();
  if TG_TABLE_NAME='entries' then
   if NEW.date>(now() at time zone 'America/Lima')::date then raise exception 'No se permiten jornadas futuras.';end if;
   kind:=NEW.payload->>'kind';
   if kind is null or kind not in ('ordinary','restday','holiday','special') then raise exception 'Tipo no válido.';end if;
   initial_time:=case when kind='ordinary' then NEW.payload->>'expected' else NEW.payload->>'start' end;
   final_time:=NEW.payload->>'end';
   if initial_time is null or final_time is null or initial_time !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' or final_time !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then raise exception 'Hora no válida.';end if;
   start_min:=split_part(initial_time,':',1)::int*60+split_part(initial_time,':',2)::int;
   end_min:=split_part(final_time,':',1)::int*60+split_part(final_time,':',2)::int+case when coalesce((NEW.payload->>'nextDay')::boolean,false) then 1440 else 0 end;
   pause_min:=coalesce((NEW.payload->>'pause')::int,0);
   if NEW.date::timestamp+make_interval(mins=>end_min)>(now() at time zone 'America/Lima') then raise exception 'La salida no puede ser futura.';end if;
   if (kind<>'ordinary' and end_min<=start_min) or end_min-start_min>1440 or pause_min<0 or pause_min>greatest(0,end_min-start_min) then raise exception 'Intervalo o pausa no válido.';end if;
   NEW.minutes:=greatest(0,end_min-start_min)-pause_min;
  else
   if NEW.status='taken' and NEW.date>(now() at time zone 'America/Lima')::date then raise exception 'El descanso futuro no puede estar gozado.';end if;
  end if;
 end if;
 select coalesce(sum(minutes),0) into earned from public.entries where user_id=uid;
 select coalesce(sum(minutes),0) into spent from public.rests where user_id=uid and status in ('approved','taken');
 if TG_TABLE_NAME='entries' then
  if TG_OP<>'INSERT' then delta_earned:=delta_earned-OLD.minutes;end if;
  if TG_OP<>'DELETE' then delta_earned:=delta_earned+NEW.minutes;end if;
 else
  if TG_OP<>'INSERT' and OLD.status in ('approved','taken') then delta_spent:=delta_spent-OLD.minutes;end if;
  if TG_OP<>'DELETE' and NEW.status in ('approved','taken') then delta_spent:=delta_spent+NEW.minutes;end if;
 end if;
 if earned+delta_earned-spent-delta_spent<0 then raise exception 'Saldo insuficiente para los descansos aprobados o gozados.';end if;
 if TG_OP='DELETE' then return OLD;else return NEW;end if;
end; $$;
create trigger entries_validate before insert or update or delete on public.entries for each row execute function public.validate_time_record();
create trigger rests_validate before insert or update or delete on public.rests for each row execute function public.validate_time_record();
create function public.audit_change() returns trigger language plpgsql security definer set search_path='' as $$ begin insert into public.audit_log(user_id,actor,table_name,operation,old_row,new_row) values(case when TG_OP='DELETE' then OLD.user_id else NEW.user_id end,auth.uid(),TG_TABLE_NAME,TG_OP,case when TG_OP<>'INSERT' then to_jsonb(OLD) end,case when TG_OP<>'DELETE' then to_jsonb(NEW) end);return null;end; $$;
create trigger entries_audit after insert or update or delete on public.entries for each row execute function public.audit_change();
create trigger rests_audit after insert or update or delete on public.rests for each row execute function public.audit_change();
revoke all on function public.new_user_profile(),public.validate_time_record(),public.audit_change() from public,anon,authenticated;
-- Después de registrarte y confirmar tu correo, ejecuta por separado:
-- insert into public.admins(user_id)
-- select id from auth.users where email='mespinozahse@gmail.com' and email_confirmed_at is not null
-- on conflict do nothing;
-- La cuenta nunca obtiene permisos por el correo enviado desde el navegador.

-- 002_admin_analytics.sql
-- Ejecutar después de schema.sql. Métricas de uso y directorio administrativo.
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

-- 003_identity_fields.sql
-- Ejecutar después de schema.sql y 002_admin_analytics.sql.
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

-- 004_admin_management.sql
-- Ejecutar después de 003_identity_fields.sql. Consolidados, aprobaciones y trazabilidad administrativa.
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

-- 005_company_roles.sql
-- Ejecutar después de 004_admin_management.sql. Roles y separación estricta por empresa.
create table public.companies(id uuid primary key default gen_random_uuid(),name text not null unique check(length(name) between 2 and 150),active boolean not null default true,created_at timestamptz not null default now());
alter table public.companies enable row level security;
create policy companies_read on public.companies for select to anon,authenticated using(active or exists(select 1 from public.admins where user_id=auth.uid()));
grant select on public.companies to anon,authenticated;
alter table public.profiles add column company_id uuid references public.companies(id);
create table public.access_roles(user_id uuid primary key references auth.users(id) on delete cascade,role text not null check(role in ('developer','admin','user')),company_id uuid references public.companies(id),check(role='developer' or company_id is not null));
alter table public.access_roles enable row level security;
revoke all on public.access_roles from anon,authenticated;
grant select on public.access_roles to authenticated;
create function public.is_developer() returns boolean language sql stable security definer set search_path='' as $$select exists(select 1 from public.access_roles where user_id=auth.uid() and role='developer')$$;
create function public.current_company_id() returns uuid language sql stable security definer set search_path='' as $$select company_id from public.access_roles where user_id=auth.uid()$$;
create function public.can_manage(p_user uuid) returns boolean language sql stable security definer set search_path='' as $$select exists(select 1 from public.access_roles me left join public.access_roles other on other.user_id=p_user where me.user_id=auth.uid() and (me.role='developer' or (me.role='admin' and me.company_id=other.company_id)))$$;
create or replace function public.is_admin() returns boolean language sql stable security definer set search_path='' as $$select exists(select 1 from public.access_roles where user_id=auth.uid() and role in ('developer','admin'))$$;
create function public.access_context() returns jsonb language sql stable security definer set search_path='' as $$select jsonb_build_object('role',r.role,'company_id',r.company_id,'company',c.name) from public.access_roles r left join public.companies c on c.id=r.company_id where r.user_id=auth.uid()$$;
create function public.list_companies() returns jsonb language sql stable security definer set search_path='' as $$select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name) order by name),'[]'::jsonb) from public.companies where active$$;
create function public.developer_create_company(p_name text) returns uuid language plpgsql security definer set search_path='' as $$declare cid uuid;begin if not public.is_developer() then raise exception 'Solo el desarrollador puede crear empresas.';end if;insert into public.companies(name) values(left(trim(p_name),150)) returning id into cid;return cid;end$$;
create function public.developer_assign_role(p_email text,p_role text,p_company uuid default null) returns void language plpgsql security definer set search_path='' as $$declare uid uuid;begin if not public.is_developer() then raise exception 'Solo el desarrollador puede asignar accesos.';end if;if p_role not in ('admin','user') then raise exception 'Rol no válido.';end if;if p_company is null then raise exception 'Selecciona una empresa.';end if;select id into uid from auth.users where lower(email)=lower(trim(p_email));if uid is null then raise exception 'El correo aún no tiene una cuenta confirmada.';end if;insert into public.access_roles(user_id,role,company_id) values(uid,p_role,p_company) on conflict(user_id) do update set role=excluded.role,company_id=excluded.company_id;update public.profiles set company_id=p_company,company=(select name from public.companies where id=p_company) where id=uid;end$$;
revoke all on function public.is_developer(),public.current_company_id(),public.can_manage(uuid),public.access_context(),public.developer_create_company(text),public.developer_assign_role(text,text,uuid) from public;
grant execute on function public.is_developer(),public.current_company_id(),public.can_manage(uuid),public.access_context(),public.developer_create_company(text),public.developer_assign_role(text,text,uuid) to authenticated;
revoke all on function public.list_companies() from public;grant execute on function public.list_companies() to anon,authenticated;
drop policy if exists profile_read on public.profiles;drop policy if exists profile_update on public.profiles;drop policy if exists entries_access on public.entries;drop policy if exists rests_access on public.rests;drop policy if exists audit_read on public.audit_log;
create policy profile_read on public.profiles for select to authenticated using(id=auth.uid() or public.can_manage(id));
create policy profile_update on public.profiles for update to authenticated using(id=auth.uid() or public.can_manage(id)) with check(id=auth.uid() or public.can_manage(id));
create policy entries_access on public.entries for all to authenticated using(user_id=auth.uid() or public.can_manage(user_id)) with check(user_id=auth.uid() or public.can_manage(user_id));
create policy rests_access on public.rests for all to authenticated using(user_id=auth.uid() or public.can_manage(user_id)) with check(user_id=auth.uid() or public.can_manage(user_id));
create policy audit_read on public.audit_log for select to authenticated using(user_id=auth.uid() or public.can_manage(user_id));
create policy roles_read on public.access_roles for select to authenticated using(user_id=auth.uid() or public.can_manage(user_id));
create or replace function public.new_user_profile() returns trigger language plpgsql security definer set search_path='' as $$declare cid uuid;declare assigned_role text;begin cid:=nullif(new.raw_user_meta_data->>'company_id','')::uuid;assigned_role:=case when lower(coalesce(new.email,''))='mespinozahse@gmail.com' then 'developer' else 'user' end;insert into public.profiles(id,name,first_name,last_name,company,company_id,document_type,document_number,phone,email) values(new.id,left(trim(concat(coalesce(new.raw_user_meta_data->>'first_name',''),' ',coalesce(new.raw_user_meta_data->>'last_name',''))),100),left(coalesce(new.raw_user_meta_data->>'first_name',''),80),left(coalesce(new.raw_user_meta_data->>'last_name',''),100),coalesce((select name from public.companies where id=cid),''),cid,case when new.raw_user_meta_data->>'document_type'='CE' then 'CE' else 'DNI' end,left(regexp_replace(coalesce(new.raw_user_meta_data->>'document_number',''),'[^0-9A-Za-z-]','','g'),15),left(coalesce(new.raw_user_meta_data->>'phone',''),30),coalesce(new.email,''));insert into public.access_roles(user_id,role,company_id) values(new.id,assigned_role,case when assigned_role='developer' then null else cid end);return new;end$$;
-- Si la cuenta del desarrollador ya existe, vincularla de forma segura.
insert into public.access_roles(user_id,role,company_id) select id,'developer',null from auth.users where lower(email)='mespinozahse@gmail.com' and email_confirmed_at is not null on conflict(user_id) do update set role='developer',company_id=null;
alter function public.admin_dashboard() rename to admin_dashboard_unfiltered;
revoke all on function public.admin_dashboard_unfiltered() from public,anon,authenticated;
create function public.admin_dashboard() returns jsonb language plpgsql stable security definer set search_path='' as $$declare d jsonb;declare cid uuid;begin if not public.is_admin() then raise exception 'Solo el administrador puede consultar las estadísticas.';end if;d:=public.admin_dashboard_unfiltered();if public.is_developer() then return d;end if;cid:=public.current_company_id();d:=jsonb_set(d,'{registered}',to_jsonb((select count(*) from public.access_roles where company_id=cid)));d:=jsonb_set(d,'{entries}',to_jsonb((select count(*) from public.entries e join public.access_roles r on r.user_id=e.user_id where r.company_id=cid)));d:=jsonb_set(d,'{earned}',to_jsonb((select coalesce(sum(e.minutes),0) from public.entries e join public.access_roles r on r.user_id=e.user_id where r.company_id=cid)));d:=jsonb_set(d,'{used}',to_jsonb((select coalesce(sum(x.minutes),0) from public.rests x join public.access_roles r on r.user_id=x.user_id where r.company_id=cid and x.status='taken')));d:=jsonb_set(d,'{reserved}',to_jsonb((select coalesce(sum(x.minutes),0) from public.rests x join public.access_roles r on r.user_id=x.user_id where r.company_id=cid and x.status='approved')));d:=jsonb_set(d,'{directory}',coalesce((select jsonb_agg(v) from jsonb_array_elements(d->'directory') v where public.can_manage((v->>'id')::uuid)),'[]'::jsonb));d:=jsonb_set(d,'{pending}',coalesce((select jsonb_agg(v) from jsonb_array_elements(d->'pending') v where public.can_manage((v->>'user_id')::uuid)),'[]'::jsonb));d:=jsonb_set(d,'{rests}',coalesce((select jsonb_agg(v) from jsonb_array_elements(d->'rests') v where public.can_manage((v->>'user_id')::uuid)),'[]'::jsonb));d:=jsonb_set(d,'{audit}',coalesce((select jsonb_agg(v) from jsonb_array_elements(d->'audit') v where public.can_manage((v->>'user_id')::uuid)),'[]'::jsonb));return d;end$$;
revoke all on function public.admin_dashboard() from public;grant execute on function public.admin_dashboard() to authenticated;

-- 006_access_hardening.sql
-- Ejecutar una vez, después de 005. Versión pública 1.
create or replace function public.is_developer() returns boolean language sql stable security definer set search_path='' as $$
select exists(select 1 from public.access_roles r join auth.users u on u.id=r.user_id where r.user_id=auth.uid() and r.role='developer' and u.email_confirmed_at is not null and lower(u.email)='mespinozahse@gmail.com')$$;
create or replace function public.is_admin() returns boolean language sql stable security definer set search_path='' as $$
select public.is_developer() or exists(select 1 from public.access_roles r join auth.users u on u.id=r.user_id join public.companies c on c.id=r.company_id where r.user_id=auth.uid() and r.role='admin' and u.email_confirmed_at is not null and c.active)$$;
create or replace function public.can_manage(p_user uuid) returns boolean language sql stable security definer set search_path='' as $$
select public.is_developer() or (public.is_admin() and exists(select 1 from public.access_roles r where r.user_id=p_user and r.company_id=public.current_company_id()))$$;
drop policy companies_read on public.companies;
create policy companies_read on public.companies for select to anon,authenticated using(active);
drop policy admin_visits on public.site_visits;
create policy admin_visits on public.site_visits for select to authenticated using(public.can_manage(user_id));
revoke update(company) on public.profiles from authenticated;

create or replace function public.developer_assign_role(p_email text,p_role text,p_company uuid default null) returns void language plpgsql security definer set search_path='' as $$
declare uid uuid;
begin
 if not public.is_developer() then raise exception 'Solo el desarrollador puede asignar accesos.';end if;
 if p_role is null or p_role not in ('admin','user') then raise exception 'Rol no válido.';end if;
 if not exists(select 1 from public.companies where id=p_company and active) then raise exception 'Selecciona una empresa activa.';end if;
 select id into uid from auth.users where lower(email)=lower(trim(p_email)) and email_confirmed_at is not null;
 if uid is null then raise exception 'El correo aún no tiene una cuenta confirmada.';end if;
 if exists(select 1 from public.access_roles where user_id=uid and role='developer') then raise exception 'No se puede reemplazar el acceso del desarrollador.';end if;
 -- No trasladar historiales laborales a otra empresa de forma implícita.
 if exists(select 1 from public.profiles where id=uid and company_id is distinct from p_company) and (exists(select 1 from public.entries where user_id=uid) or exists(select 1 from public.rests where user_id=uid)) then raise exception 'La cuenta tiene historial: no se puede cambiar su empresa.';end if;
 insert into public.access_roles(user_id,role,company_id) values(uid,p_role,p_company) on conflict(user_id) do update set role=excluded.role,company_id=excluded.company_id;
 update public.profiles set company_id=p_company,company=(select name from public.companies where id=p_company) where id=uid;
end$$;

create function public.validate_company_signup() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if lower(coalesce(new.email,'')) <> 'mespinozahse@gmail.com' and not exists(select 1 from public.companies where id=nullif(new.raw_user_meta_data->>'company_id','')::uuid and active) then raise exception 'Selecciona una empresa activa.';end if;
 return new;
end$$;
create trigger company_signup before insert on auth.users for each row execute function public.validate_company_signup();
revoke all on function public.validate_company_signup() from public,anon,authenticated;

create function public.authorize_rest_change() returns trigger language plpgsql security definer set search_path='' as $$
declare uid uuid;
begin
 uid:=case when TG_OP='DELETE' then old.user_id else new.user_id end;
 if not public.can_manage(uid) then
  if TG_OP<>'INSERT' and old.status in ('approved','taken') then raise exception 'Solo el administrador puede modificar un descanso confirmado.';end if;
  if TG_OP<>'DELETE' and new.status not in ('requested','cancelled') then raise exception 'Solo el administrador puede aprobar o confirmar descansos.';end if;
 end if;
 if TG_OP='DELETE' then return old;end if;return new;
end$$;
create trigger rests_authorize before insert or update or delete on public.rests for each row execute function public.authorize_rest_change();
revoke all on function public.authorize_rest_change() from public,anon,authenticated;

create function public.audit_access_change() returns trigger language plpgsql security definer set search_path='' as $$
begin
 insert into public.audit_log(user_id,actor,table_name,operation,old_row,new_row) values(new.user_id,auth.uid(),'access_roles',TG_OP,case when TG_OP='UPDATE' then to_jsonb(old) end,to_jsonb(new));return new;
end$$;
create trigger roles_audit after insert or update on public.access_roles for each row execute function public.audit_access_change();
revoke all on function public.audit_access_change() from public,anon,authenticated;
create or replace function public.admin_dashboard() returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 if not public.is_admin() then raise exception 'Solo el administrador puede consultar las estadísticas.';end if;
 with scoped_profiles as materialized (select * from public.profiles where public.can_manage(id)),
 scoped_entries as materialized (select * from public.entries where public.can_manage(user_id)),
 scoped_rests as materialized (select * from public.rests where public.can_manage(user_id)),
 scoped_site_visits as materialized (select * from public.site_visits where public.can_manage(user_id)),
 scoped_audit_log as materialized (select * from public.audit_log where public.can_manage(user_id))
 select jsonb_build_object(
 'registered',(select count(*) from scoped_profiles),'new30',(select count(*) from scoped_profiles where created_at>=now()-interval '30 days'),
 'active30',(select count(distinct user_id) from (select user_id from scoped_site_visits where started_at>=now()-interval '30 days' and user_id is not null union select user_id from scoped_entries where updated_at>=now()-interval '30 days') q),
 'sessions30',(select count(*) from scoped_site_visits where started_at>=now()-interval '30 days'),'visitors30',(select count(distinct visitor_id) from scoped_site_visits where started_at>=now()-interval '30 days'),
 'entries',(select count(*) from scoped_entries),'earned',(select coalesce(sum(minutes),0) from scoped_entries),'used',(select coalesce(sum(minutes),0) from scoped_rests where status='taken'),'reserved',(select coalesce(sum(minutes),0) from scoped_rests where status='approved'),
 'daily',(select coalesce(jsonb_agg(x order by x.day),'[]'::jsonb) from (select (started_at at time zone 'America/Lima')::date as day,count(*) as sessions,count(distinct visitor_id) as visitors from scoped_site_visits where started_at>=now()-interval '30 days' group by 1) x),
 'sources',(select coalesce(jsonb_agg(x),'[]'::jsonb) from (select source,count(*) as total from scoped_site_visits where started_at>=now()-interval '30 days' group by source order by total desc) x),
 'devices',(select coalesce(jsonb_agg(x),'[]'::jsonb) from (select device,count(*) as total from scoped_site_visits where started_at>=now()-interval '30 days' group by device order by total desc) x),
 'directory',(select coalesce(jsonb_agg(x order by x.created_at desc),'[]'::jsonb) from (select p.id,p.name,p.first_name,p.last_name,p.email,p.company,p.document_type,p.document_number,p.phone,p.created_at,(select count(*) from scoped_entries e where e.user_id=p.id) entries,(select coalesce(sum(minutes),0) from scoped_entries e where e.user_id=p.id) earned,(select coalesce(sum(minutes),0) from scoped_rests r where r.user_id=p.id and r.status='requested') requested,(select coalesce(sum(minutes),0) from scoped_rests r where r.user_id=p.id and r.status='approved') approved,(select coalesce(sum(minutes),0) from scoped_rests r where r.user_id=p.id and r.status='taken') used from scoped_profiles p) x),
 'pending',(select coalesce(jsonb_agg(x order by x.date,x.name),'[]'::jsonb) from (select r.id,r.user_id,r.date,r.minutes,r.status,r.payload->>'comment' comment,r.updated_at,p.name,p.company from scoped_rests r join scoped_profiles p on p.id=r.user_id where r.status='requested') x),
 'rests',(select coalesce(jsonb_agg(x order by x.date desc),'[]'::jsonb) from (select r.id,r.user_id,r.date,r.minutes,r.status,r.payload->>'comment' comment,r.updated_at,p.name from scoped_rests r join scoped_profiles p on p.id=r.user_id) x),
 'audit',(select coalesce(jsonb_agg(x order by x.at desc),'[]'::jsonb) from (select a.id,a.at,a.actor,a.user_id,a.table_name,a.operation,a.old_row->>'status' old_status,a.new_row->>'status' new_status,p.name user_name,coalesce(ap.name,'Administrador') actor_name from scoped_audit_log a left join scoped_profiles p on p.id=a.user_id left join scoped_profiles ap on ap.id=a.actor order by a.at desc limit 200) x)
 ) into result;return result;
end;$$;

commit;
