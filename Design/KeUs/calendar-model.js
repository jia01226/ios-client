(function(root){
  'use strict';
  const stamp=s=>Date.parse(s+'T00:00:00Z');
  const valid=s=>/^\d{4}-\d{2}-\d{2}$/.test(s)&&Number.isFinite(stamp(s))&&new Date(stamp(s)).toISOString().slice(0,10)===s;
  const iso=key=>{const [y,m,d]=key.split('-').map(Number);return `${y}-${String(m+1).padStart(2,'0')}-${String(d).padStart(2,'0')}`};
  const isPeriod=(periods,date,today)=>periods.some(p=>date>=p.start&&(p.end?date<p.end:date<=today));
  function changePeriod(periods,date,kind,today){
    if(!valid(date)||date>today)return {error:'请选择今天或之前的日期。'};
    const next=periods.map(p=>({...p}));
    if(kind==='start'){
      if(next.some(p=>!p.end))return {error:'已经记了“来了”，结束时点“走了”就好。'};
      if(isPeriod(next,date,today)||next.some(p=>p.start>=date))return {error:'这个日期已有记录，请先撤销刚才的标记，或选择之后的日期。'};
      next.push({start:date,end:null});
    }else{
      const active=next.find(p=>!p.end);
      if(!active)return {error:'还没有开始记录，先点“来了”。'};
      if(date<active.start)return {error:'结束日期不能早于“来了”的日期。'};
      active.end=date;
    }
    return {periods:next};
  }
  function count(event,today){
    if(!event.annual){const days=Math.round((stamp(today)-stamp(event.date))/86400000);return {days:Math.abs(days),label:days<0?'还有':'已经'}};
    const [year]=today.split('-').map(Number),[,month,day]=event.date.split('-').map(Number);
    const occurrence=y=>{const last=new Date(Date.UTC(y,month,0)).getUTCDate();return Date.UTC(y,month-1,Math.min(day,last))};
    let target=occurrence(year);if(target<stamp(today))target=occurrence(year+1);
    return {days:Math.round((target-stamp(today))/86400000),label:'还有'};
  }
  const api={valid,iso,isPeriod,changePeriod,count};
  if(typeof module!=='undefined')module.exports=api;else root.PondCalendar=api;
})(typeof window!=='undefined'?window:globalThis);
