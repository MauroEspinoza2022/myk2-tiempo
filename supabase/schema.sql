-- Ejecutar una vez en el SQL Editor de un proyecto Supabase nuevo.
begin;
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
commit;
-- Después de registrarte y confirmar tu correo, ejecuta por separado:
-- insert into public.admins(user_id)
-- select id from auth.users where email='mespinozahse@gmail.com' and email_confirmed_at is not null
-- on conflict do nothing;
-- La cuenta nunca obtiene permisos por el correo enviado desde el navegador.
