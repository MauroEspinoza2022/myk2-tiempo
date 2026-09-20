import {test} from 'node:test';import assert from 'node:assert/strict';import {readFile} from 'node:fs/promises';import {PGlite} from '@electric-sql/pglite';
test('Esquema, cálculo en servidor, aislamiento de usuarios, administrador y saldo',async()=>{
const db=new PGlite();await db.exec(`create role anon;create role authenticated;create schema auth;create table auth.users(id uuid primary key,email text,email_confirmed_at timestamptz,raw_user_meta_data jsonb);create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;grant usage on schema auth to authenticated;grant execute on function auth.uid() to authenticated;`);
await db.exec(await readFile(new URL('../supabase/schema.sql',import.meta.url),'utf8'));
await db.exec(await readFile(new URL('../supabase/002_admin_analytics.sql',import.meta.url),'utf8'));
await db.exec(await readFile(new URL('../supabase/003_identity_fields.sql',import.meta.url),'utf8'));
await db.exec(await readFile(new URL('../supabase/004_admin_management.sql',import.meta.url),'utf8'));
const a='11111111-1111-4111-8111-111111111111',b='22222222-2222-4222-8222-222222222222',entry='33333333-3333-4333-8333-333333333333';
await db.query(`insert into auth.users(id,email,raw_user_meta_data) values ($1,'a@example.test','{"first_name":"Prueba","last_name":"A","company":"Empresa A","document_type":"DNI","document_number":"12345678","phone":"975721020"}'),($2,'b@example.test','{"first_name":"Prueba","last_name":"B","company":"Empresa B","document_type":"CE","document_number":"ABC123456","phone":"975721021"}')`,[a,b]);
await db.exec(`set role authenticated;set request.jwt.claim.sub='${a}';`);
const payload={kind:'ordinary',expected:'16:00',end:'20:00',pause:0,nextDay:false,comment:'Prueba'};
await db.query(`insert into public.entries(id,user_id,date,minutes,payload) values ($1,$2,'2026-01-05',999,$3)`,[entry,a,JSON.stringify(payload)]);
assert.equal((await db.query('select minutes from public.entries')).rows[0].minutes,240);
await db.query(`insert into public.rests(user_id,date,minutes,status,payload) values ($1,'2026-01-06',120,'taken','{}')`,[a]);
await assert.rejects(db.query(`insert into public.rests(user_id,date,minutes,status,payload) values ($1,'2026-01-07',180,'approved','{}')`,[a]),/Saldo insuficiente/);
await assert.rejects(db.query('delete from public.entries where id=$1',[entry]),/Saldo insuficiente/);
await assert.rejects(db.query(`insert into public.entries(user_id,date,minutes,payload) values ($1,'2026-01-08',240,$2)`,[b,JSON.stringify(payload)]),/row-level security/);
await assert.rejects(db.query('insert into public.admins(user_id) values ($1)',[a]),/permission denied/);
await assert.rejects(db.query('select public.admin_dashboard()'),/Solo el administrador/);
await db.query("select public.record_visit('44444444-4444-4444-8444-444444444444','55555555-5555-4555-8555-555555555555','direct','mobile')");
assert.equal((await db.query('select * from public.site_visits')).rows.length,0);
await db.exec(`set request.jwt.claim.sub='${b}';`);assert.equal((await db.query('select * from public.entries')).rows.length,0);assert.equal((await db.query('select * from public.profiles')).rows.length,1);
await db.exec('reset role;');await db.query('insert into public.admins values ($1)',[b]);await db.exec(`set role authenticated;`);assert.equal((await db.query('select * from public.entries')).rows.length,1);assert.equal((await db.query('select * from public.profiles')).rows.length,2);assert.equal((await db.query('select * from public.audit_log')).rows.length,2);
const stats=(await db.query('select public.admin_dashboard() as stats')).rows[0].stats;assert.equal(stats.registered,2);assert.equal(stats.sessions30,1);assert.equal(stats.earned,240);assert.equal(stats.directory.find(u=>u.id===a).email,'a@example.test');assert.equal(stats.directory.find(u=>u.id===a).document_number,'12345678');assert.equal(stats.directory.find(u=>u.id===a).used,120);assert.equal(stats.audit.length,2);
await db.exec('reset role;set role anon;');await assert.rejects(db.query('select * from public.profiles'),/permission denied/);await assert.rejects(db.query('select public.admin_dashboard()'),/permission denied/);await db.query("select public.record_visit('66666666-6666-4666-8666-666666666666','77777777-7777-4777-8777-777777777777','search','desktop')");
await db.close();
});

