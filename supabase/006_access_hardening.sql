-- Ejecutar una vez, después de 005. Versión pública 1.
begin;
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
