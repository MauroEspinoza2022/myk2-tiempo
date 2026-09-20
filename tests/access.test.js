import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {PGlite} from '@electric-sql/pglite';

test('Versión 1: permisos, empresas, aprobación y desarrollador confirmado',async()=>{
 const db=new PGlite();
 try {
 await db.exec(`create role anon;create role authenticated;create schema auth;create table auth.users(id uuid primary key,email text,email_confirmed_at timestamptz,raw_user_meta_data jsonb);create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;grant usage on schema auth to authenticated;grant execute on function auth.uid() to authenticated;`);
 for(const file of ['schema','002_admin_analytics','003_identity_fields','004_admin_management','005_company_roles','006_access_hardening'])await db.exec(await readFile(new URL(`../supabase/${file}.sql`,import.meta.url),'utf8'));
 const ids=Array.from({length:7},(_,i)=>`00000000-0000-4000-8000-${String(i+1).padStart(12,'0')}`);
 const [owner,admin,a,b,unconfirmed,ca,cb]=ids;
 const login=async id=>db.exec(`reset role;set role authenticated;set request.jwt.claim.sub='${id}';`);
 const root=async()=>db.exec('reset role;');
 const scalar=async sql=>(await db.query(sql)).rows[0].v;
 await db.query('insert into public.companies(id,name) values ($1,\'Empresa A\'),($2,\'Empresa B\')',[ca,cb]);
 for(const [id,email,company,confirmed] of [[owner,'mespinozahse@gmail.com',null,false],[admin,'admin@test.pe',ca,true],[a,'a@test.pe',ca,true],[b,'b@test.pe',cb,true],[unconfirmed,'pending@test.pe',ca,false]]){
  await db.query('insert into auth.users values($1,$2,$3,$4)',[id,email,confirmed?new Date().toISOString():null,JSON.stringify({company_id:company,first_name:email})]);
 }
 await login(owner);
 assert.equal(await scalar('select public.is_developer() v'),false);
 await assert.rejects(db.query("select public.developer_create_company('No autorizada')"),/Solo el desarrollador/);
 await root();await db.query('update auth.users set email_confirmed_at=now() where id=$1',[owner]);await login(owner);
 assert.equal(await scalar('select public.is_developer() v'),true);
 await db.query("select public.developer_assign_role('admin@test.pe','admin',$1)",[ca]);
 await assert.rejects(db.query("select public.developer_assign_role('pending@test.pe','admin',$1)",[ca]),/confirmada/);
 await assert.rejects(db.query("select public.developer_assign_role('mespinozahse@gmail.com','user',$1)",[ca]),/desarrollador/);
 const payload=JSON.stringify({kind:'ordinary',expected:'16:00',end:'20:00',pause:0,nextDay:false});
 await login(a);await db.query("insert into public.entries(user_id,date,minutes,payload) values($1,'2026-01-05',1,$2)",[a,payload]);
 await assert.rejects(db.query("insert into public.rests(user_id,date,minutes,status,payload) values($1,'2026-01-06',60,'approved','{}')",[a]),/Solo el administrador/);
 await db.query("insert into public.rests(user_id,date,minutes,status,payload) values($1,'2026-01-06',60,'requested','{}')",[a]);
 await assert.rejects(db.query("update public.profiles set company='B' where id=$1",[a]),/permission denied/);
 await login(b);await db.query("insert into public.entries(user_id,date,minutes,payload) values($1,'2026-01-05',1,$2)",[b,payload]);
 await db.query("select public.record_visit($1,$2,'social','mobile')",[b,cb]);
 await login(admin);
 assert.equal((await db.query('select * from public.entries')).rows.length,1);
 assert.equal((await db.query('select * from public.site_visits')).rows.length,0);
 assert.equal((await db.query('select * from public.profiles where id=$1',[b])).rows.length,0);
 assert.equal((await db.query('update public.entries set payload=payload where user_id=$1 returning id',[b])).rows.length,0);
 await db.query("update public.rests set status='approved' where user_id=$1",[a]);
 const d=await scalar('select public.admin_dashboard() v');
 assert.equal(d.earned,240);assert.equal(d.reserved,60);assert.equal(d.registered,3);assert.equal(d.sessions30,0);assert.equal(d.visitors30,0);assert.equal(d.new30,3);assert.equal(d.active30,1);
 assert.deepEqual(d.daily,[]);assert.deepEqual(d.sources,[]);assert.deepEqual(d.devices,[]);
 assert.ok(d.directory.every(u=>u.id!==b&&u.id!==owner));assert.ok(d.audit.every(x=>x.user_id!==b&&x.user_id!==owner));
 await assert.rejects(db.query("select public.developer_assign_role('b@test.pe','admin',$1)",[cb]),/Solo el desarrollador/);
 await login(a);await assert.rejects(db.query("update public.rests set status='cancelled' where user_id=$1",[a]),/confirmado/);
 await assert.rejects(db.query('delete from public.rests where user_id=$1',[a]),/confirmado/);
 await login(owner);assert.equal((await scalar('select public.admin_dashboard() v')).sessions30,1);
 await db.exec('reset role;set role anon;');assert.equal((await db.query('select * from public.companies')).rows.length,2);
 await assert.rejects(db.query('select public.admin_dashboard()'),/permission denied/);
 }finally{await db.close();}
});
