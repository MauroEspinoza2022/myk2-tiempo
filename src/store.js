import {createClient} from '@supabase/supabase-js';
import {defaults} from './core.js';
const url=import.meta.env.VITE_SUPABASE_URL,key=import.meta.env.VITE_SUPABASE_ANON_KEY;
export const cloud=url&&key?createClient(url,key):null;
const LOCAL_KEY='myk2-tiempo-v1';
export let user=null,admin=false,target=null;
export let data={profile:{...defaults},records:[],rests:[]};
export async function init(){if(cloud){const {data:s,error}=await cloud.auth.getSession();if(error)throw error;user=s.session?.user||null;if(user){target=user.id;await load();}}else{const raw=localStorage.getItem(LOCAL_KEY);if(raw){const parsed=JSON.parse(raw);data={profile:{...defaults,...parsed.profile},records:parsed.records||[],rests:parsed.rests||[]};}}}
async function allRows(table){let rows=[],offset=0;while(true){const {data:part,error}=await cloud.from(table).select('*').eq('user_id',target).order('id').range(offset,offset+999);if(error)throw error;rows.push(...part);if(part.length<1000)return rows;offset+=1000;}}
export async function load(){const [p,r,s,a]=await Promise.all([cloud.from('profiles').select('*').eq('id',target).single(),allRows('entries'),allRows('rests'),cloud.rpc('is_admin')]);if(p.error)throw p.error;if(a.error)throw a.error;admin=a.data===true;data={profile:{...defaults,...p.data.settings,name:p.data.name,company:p.data.company,phone:p.data.phone},records:r.map(x=>({...x.payload,id:x.id,date:x.date,minutes:x.minutes})),rests:s.map(x=>({...x.payload,id:x.id,date:x.date,minutes:x.minutes,status:x.status}))};}
export async function selectUser(id){target=id;await load();}
function persist(next){localStorage.setItem(LOCAL_KEY,JSON.stringify(next));data=next;}
export async function saveProfile(profile){if(cloud){const {error}=await cloud.from('profiles').update({name:profile.name,company:profile.company,phone:profile.phone,settings:{dayHours:profile.dayHours,schedule:profile.schedule}}).eq('id',target);if(error)throw error;data.profile=profile;}else persist({...data,profile});}
export async function saveItem(collection,item){const next={...data,[collection]:[...data[collection].filter(r=>r.id!==item.id),item].sort((a,b)=>a.date.localeCompare(b.date))};if(cloud){const {error}=await cloud.from(collection==='records'?'entries':'rests').upsert({id:item.id,user_id:target,date:item.date,minutes:item.minutes,...(collection==='rests'?{status:item.status}:{}),payload:item});if(error)throw error;data=next;}else persist(next);}
export async function removeItem(collection,id){if(cloud){const {error}=await cloud.from(collection==='records'?'entries':'rests').delete().eq('id',id).eq('user_id',target);if(error)throw error;data={...data,[collection]:data[collection].filter(r=>r.id!==id)};}else persist({...data,[collection]:data[collection].filter(r=>r.id!==id)});}
export async function users(){const {data,error}=await cloud.from('profiles').select('id,name,company').order('name');if(error)throw error;return data;}
export async function signout(){if(cloud){await cloud.auth.signOut();user=null;admin=false;target=null;data={profile:{...defaults},records:[],rests:[]};}}
