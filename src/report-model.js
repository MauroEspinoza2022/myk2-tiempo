import {totals,grouped,dayEquivalent,limaNow} from './core.js';
export function reportModel({records,rests,profile,mode='week',from='',to='',allRecords=records,allRests=rests}){
 const cutoff=to||[limaNow().date,...records.map(r=>r.date),...rests.map(r=>r.date)].sort().at(-1),prior=from?totals(allRecords.filter(r=>r.date<from),allRests.filter(r=>r.date<from)):{balance:0};
 const closing=totals(allRecords.filter(r=>r.date<=cutoff),allRests.filter(r=>r.date<=cutoff));const period=totals(records,rests);let running=prior.balance;
 const groups=grouped(records,rests,mode).map(g=>{running+=g.earned-g.used;return {...g,balance:running};});
 const movements=[...records.map(r=>({date:r.date,type:'Horas extra',credit:r.minutes,debit:0,comment:r.comment||''})),...rests.filter(r=>r.status==='taken').map(r=>({date:r.date,type:'Descanso gozado',credit:0,debit:r.minutes,comment:r.comment||''}))].sort((a,b)=>a.date.localeCompare(b.date)||b.credit-a.credit);running=prior.balance;for(const r of movements){running+=r.credit-r.debit;r.balance=running;}
 return {records:records.slice().sort((a,b)=>a.date.localeCompare(b.date)),rests:rests.slice().sort((a,b)=>a.date.localeCompare(b.date)),profile,mode,from,to:cutoff,opening:prior.balance,closing,period,groups,movements,equivalent:dayEquivalent(closing.balance,profile.dayHours),created:limaNow(),requested:rests.filter(r=>r.status==='requested').reduce((n,r)=>n+r.minutes,0),cancelled:rests.filter(r=>r.status==='cancelled').reduce((n,r)=>n+r.minutes,0)};
}
