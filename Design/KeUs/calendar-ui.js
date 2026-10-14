'use strict';
window.PondReady=(async()=>{
  const load=async path=>{const response=await fetch(path);if(!response.ok)throw Error(path);return response.json()};
  const [data,controls]=await Promise.all([load('spec/sample-data.json'),load('spec/preview-controls.json')]);
  const $=s=>document.querySelector(s),model=PondCalendar;
  const el=(tag,cls,text)=>{const e=document.createElement(tag);if(cls)e.className=cls;if(text!==undefined)e.textContent=text;return e};
  const action=(text,fn,cls='secondary-action')=>{const b=el('button',cls,text);b.type='button';b.onclick=fn;return b};
  const field=(title,input)=>{const label=el('label','field-label');label.append(el('span','',title),input);return label};
  const state={days:Object.fromEntries(data.calendar.days.map(d=>[d.date,{...d}])),periods:controls.periods,shifts:controls.shifts,events:controls.anniversaries};
  let undoPeriod=null,selectedEvent=0;
  const notice=text=>{$('#saveStatus').textContent=text};
  function show(title,description){
    $('#sheetTitle').textContent=title;$('#sheetText').textContent=description;$('#sheetExtra').replaceChildren();notice('');
    if(!$('#sheet').open)$('#sheet').showModal();$('#sheet').scrollTop=0;return $('#sheetExtra');
  }
  function getDay(key){
    const date=model.iso(key),entry=state.days[date]||{};
    return {...entry,shift:entry.shift==='休'?'':entry.shift||'',period:model.isPeriod(state.periods,date,controls.asOf),note:entry.note||'',anniversary:state.events.some(e=>e.annual?e.date.slice(5)===date.slice(5):e.date===date)};
  }
  function openDay(key,label,onSave){
    const date=model.iso(key),host=show(label,'点一下就记好。'),day=state.days[date]||(state.days[date]={});
    const update=message=>{onSave();$('#pageStatus').textContent=message};
    const group=el('section','day-section');group.append(el('h3','','班表'));
    const choices=el('div','quick-shifts');
    function drawShifts(){
      choices.replaceChildren();
      for(const name of state.shifts){const b=action(name,()=>{day.shift=day.shift===name?'':name;drawShifts();update(day.shift?`已选${name}`:'已清空班次');notice(day.shift?`已选${name}`:'已清空班次')},'quick-choice');b.setAttribute('aria-pressed',String(day.shift===name));choices.append(b)}
    }
    drawShifts();group.append(choices);
    const custom=el('details','custom-shift');custom.append(el('summary','','添加自己的时间'));
    const form=el('form','detail-form'),name=el('input'),start=el('input'),end=el('input');
    name.placeholder='例如：下午班';name.maxLength=12;start.type=end.type='time';start.required=end.required=true;
    const times=el('div','time-fields');times.append(field('开始',start),field('结束',end));
    const submit=el('button','primary-action','添加并选用');submit.type='submit';
    form.append(field('名称（选填）',name),times,submit);
    form.onsubmit=e=>{e.preventDefault();const text=`${name.value.trim()?name.value.trim()+' ':''}${start.value}–${end.value}`;if(!state.shifts.includes(text))state.shifts.push(text);day.shift=text;drawShifts();custom.open=false;update('已添加班次');notice('已选用，之后也可以直接点选。')};custom.append(form);
    group.append(custom,action('清空班次',()=>{day.shift='';drawShifts();update('班次已留空');notice('日历上留空，不显示休息。')}));
    host.append(group);
    const period=el('section','day-section period-section');period.append(el('h3','','月经'));
    const status=el('p','period-state'),buttons=el('div','period-actions');period.append(status,buttons);
    function drawPeriod(){
      buttons.replaceChildren();const active=state.periods.find(p=>!p.end);
      status.textContent=active?`${active.start.slice(5).replace('-','月')}日来了，结束时点“走了”。`:'来了记一下，走了再记一下。';
      for(const [kind,title] of [['start','来了'],['end','走了']]){
        const b=action(title,()=>{const result=model.changePeriod(state.periods,date,kind,controls.asOf);if(result.error){notice(result.error);return}undoPeriod=state.periods;state.periods=result.periods;drawPeriod();update('月经标记已更新');notice(kind==='start'?'已标粉色，不预测结束日期。':'已结束；从这一天起不再标粉色。')},'period-button');
        b.disabled=date>controls.asOf||(kind==='start'?Boolean(active):!active||date<active.start);buttons.append(b);
      }
      if(undoPeriod)buttons.append(action('撤销',()=>{state.periods=undoPeriod;undoPeriod=null;drawPeriod();update('已撤销');notice('已撤销刚才的月经标记。')}));
    }
    drawPeriod();host.append(period);
    const notes=el('details','custom-shift');notes.append(el('summary','','当天记事'));
    const note=el('textarea');note.rows=2;note.maxLength=500;note.value=day.note||'';note.onchange=()=>{day.note=note.value;update('记事已更新')};notes.append(field('记事',note));host.append(notes);
  }
  $('.script').textContent=data.verse.en;$('.verse-cn').textContent=data.verse.zh;
  const anniversary=el('div','anniversary-panel');$('.together').replaceWith(anniversary);
  const wheel=el('div','anniversary-wheel');wheel.setAttribute('role','group');wheel.setAttribute('aria-label','上下滑动切换纪念日，点击选中项可修改');wheel.tabIndex=0;
  const counter=el('div','anniversary-count'),prefix=el('span','count-prefix'),number=el('strong','rolling-number'),suffix=el('span','','天');number.setAttribute('aria-hidden','true');counter.append(prefix,number,suffix);
  const add=action('添加',()=>editEvent(null),'add-anniversary');add.dataset.id='anniversary-add';
  anniversary.append(wheel,counter,add);
  let lastCount='',scrollTimer;
  function renderCount(){
    const event=state.events[selectedEvent],value=model.count(event,controls.asOf),text=String(value.days);
    prefix.textContent=value.label;counter.setAttribute('aria-label',`${event.title}，${value.label}${value.days}天`);
    if(text===lastCount)return;
    number.getAnimations({subtree:true}).forEach(a=>a.cancel());number.replaceChildren();
    for(let i=0;i<text.length;i++){
      const slot=el('span','digit-slot'),strip=el('span','digit-strip'),previous=lastCount.padStart(text.length,'0')[i]||text[i];
      strip.append(el('span','',previous),el('span','',text[i]));slot.append(strip);number.append(slot);
      strip.style.transform='translateY(-50%)';
      if(lastCount&&!matchMedia('(prefers-reduced-motion: reduce)').matches)strip.animate([{transform:'translateY(0)'},{transform:'translateY(-50%)'}],{duration:320+i*35,easing:'cubic-bezier(.16,1,.3,1)'});
    }
    lastCount=text;
  }
  function select(index){selectedEvent=Math.max(0,Math.min(state.events.length-1,index));wheel.querySelectorAll('button').forEach((b,i)=>{b.setAttribute('aria-pressed',String(i===selectedEvent))});renderCount()}
  function drawWheel(){
    wheel.replaceChildren();
    state.events.forEach((event,i)=>{const b=action(event.title,()=>{if(i===selectedEvent)editEvent(event);else wheel.scrollTo({top:i*44,behavior:matchMedia('(prefers-reduced-motion: reduce)').matches?'instant':'smooth'})},'wheel-item');b.dataset.id=`anniversary-${event.id}`;wheel.append(b)});
    wheel.scrollTop=selectedEvent*44;select(selectedEvent);
  }
  wheel.addEventListener('scroll',()=>{clearTimeout(scrollTimer);scrollTimer=setTimeout(()=>select(Math.round(wheel.scrollTop/44)),90)});
  wheel.addEventListener('keydown',e=>{if(e.target!==wheel||!['ArrowDown','ArrowUp','Home','End','Enter'].includes(e.key))return;e.preventDefault();if(e.key==='Enter'){editEvent(state.events[selectedEvent]);return}const next=e.key==='Home'?0:e.key==='End'?state.events.length-1:selectedEvent+(e.key==='ArrowDown'?1:-1);select(next);wheel.scrollTo({top:selectedEvent*44,behavior:matchMedia('(prefers-reduced-motion: reduce)').matches?'instant':'smooth'})});
  function editEvent(event){
    const host=show(event?'修改纪念日':'添加纪念日','日期为示例，只用于体验。'),form=el('form','detail-form');
    const title=el('input'),date=el('input'),annual=el('input');title.required=true;title.maxLength=16;title.value=event?.title||'';date.type='date';date.required=true;date.value=event?.date||controls.asOf;annual.type='checkbox';annual.checked=event?.annual||false;
    const repeat=el('label','annual-choice');repeat.append(annual,el('span','','每年纪念（生日等）'));
    const save=el('button','primary-action',event?'保存':'添加');save.type='submit';form.append(field('名称',title),field('日期',date),repeat,save);
    form.onsubmit=e=>{e.preventDefault();if(!title.value.trim()||!model.valid(date.value)){notice('请填写名称和有效日期。');return}const item={id:event?.id||crypto.randomUUID(),title:title.value.trim(),date:date.value,annual:annual.checked};if(event)state.events[selectedEvent]=item;else{state.events.push(item);selectedEvent=state.events.length-1}drawWheel();document.dispatchEvent(new Event('pond-calendar-change'));$('#sheet').close()};host.append(form);
  }
  drawWheel();
  document.querySelectorAll('.water-entry').forEach((b,i)=>{const entry=data.entries[i];b.dataset.id=entry.id;b.dataset.name=entry.title;b.querySelector('span').textContent=entry.title;b.querySelector('.reflection').textContent=entry.title;b.querySelector('em').textContent=entry.sub});
  const openList=name=>show(name,`将打开：${name}`);
  window.PondUI={getDay,openDay,openList,openCollection:()=>openList('柯的'),data,controls};
  return window.PondUI;
})();
window.PondReady.catch(()=>{document.querySelector('#pageStatus').classList.remove('sr-only');document.querySelector('#pageStatus').textContent='示例数据没有加载成功，请刷新网页重试。'});
