'use strict';
// THESIS: Four quiet notebooks behind the pond, sharing its type and paper.
// OWN-WORLD: Four pale papers, Song type, Pinyon script, fine rules, legible author labels.
// STORY: Read the current state, open a record, edit it, return to the water.
// FIRST VIEWPORT: Back control, page title, primary content, then ruled sections.
// FORM: User-pinned structure and screenshots; extension of the existing code-led preview.
// FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance
window.NotebooksReady=(async()=>{
  await PondReady;
  const load=async path=>{const r=await fetch(path);if(!r.ok)throw Error(path);return r.json()};
  const [state,tokens]=await Promise.all([load('spec/notebook-sample.json'),load('spec/tokens.json')]);
  const $=s=>document.querySelector(s),el=(tag,cls,text)=>{const e=document.createElement(tag);if(cls)e.className=cls;if(text!==undefined)e.textContent=text;return e};
  const button=(title,fn,cls='book-action')=>{const b=el('button',cls,title);b.type='button';b.onclick=fn;return b};
  const money=n=>new Intl.NumberFormat('zh-CN',{style:'currency',currency:'CNY',maximumFractionDigits:0}).format(n);
  const day=s=>s?.slice(5).replace('-','.');
  const pages={purse:['荷包','Bourse'],menu:['食单','Menu'],meds:['药盒','Remèdes'],notes:['纸条','Billets']};
  const routeByName={'荷包':'purse','食单':'menu','药盒':'meds','纸条':'notes'};
  let route='',returnScroll=0,returnFocus=null,deleted=null,statusTimer;
  const home=$('.phone'),book=el('main','phone notebook');book.hidden=true;home.after(book);
  const status=el('p','book-feedback');status.setAttribute('role','status');status.setAttribute('aria-live','polite');book.after(status);status.hidden=true;
  const showStatus=text=>{$('#saveStatus').textContent=text};
  function theme(){
    const palette=tokens.palettes[document.documentElement.dataset.palette]||tokens.palettes.ivory,c=tokens.colors.day;
    document.documentElement.dataset.appearance='day';
    const css={'paper':palette.dayPaper,'ink':c.textPrimary,'muted':c.textSecondary,'line':c.line,'surface':c.surface,'accent':c.accent,'on-accent':c.onAccent,'pink':c.periodFill,'period-text':c.periodText,'author-ke':c.authorKeText,'author-ke-bg':c.authorKeFill,'author-user':c.authorUserText,'author-user-bg':c.authorUserFill,'positive':c.positive,'negative':c.negative,'focus':c.focus};
    Object.entries(css).forEach(([key,value])=>document.documentElement.style.setProperty('--'+key,value));
    document.documentElement.style.setProperty('--progress-track',c.progressTrack);
    document.documentElement.style.setProperty('--saving-accent',c.savingAccent);
    Object.entries(tokens.typeScale).forEach(([role,spec])=>{const key=role.replace(/[A-Z]/g,m=>'-'+m.toLowerCase());document.documentElement.style.setProperty(`--type-${key}`,`${spec.size}px`);document.documentElement.style.setProperty(`--leading-${key}`,`${spec.lineHeight}px`)});
    const current=new URL(location.href);current.searchParams.delete('appearance');history.replaceState(null,'',current);
    document.querySelectorAll('.palette-options a').forEach(a=>{const u=new URL(a.href);u.searchParams.delete('appearance');a.href=u.href});
  }
  theme();
  function author(item){const tag=el('span','author-label '+(item.author==='ke'?'by-ke':'by-user'),item.author==='ke'?'柯记的':'我记的');if(item.edited)tag.append(el('small','',' · 我修改'));return tag}
  function heading(title,add){const h=el('div','book-section-heading');h.append(el('h2','',title));if(add)h.append(button('添加',add));return h}
  function section(title,items,render,add){const s=el('section','book-section');s.append(heading(title,add));if(!items.length)s.append(el('p','book-empty','还没有记录。'));items.forEach(item=>s.append(render(item)));book.append(s);return s}
  function row(item,group,meta='',detail=''){
    const b=button('',()=>edit(group,item),'record-row');b.dataset.id=item.id;b.setAttribute('aria-label',`修改${item.title}`);
    const line=el('span','record-line');line.append(el('span','record-title',item.title));if(meta)line.append(el('span','record-meta',meta));b.append(line,author(item));if(detail)b.append(el('span','record-detail',detail));return b;
  }
  function openEditor(title,description){
    $('#sheetTitle').textContent=title;$('#sheetText').textContent=description;$('#sheetExtra').replaceChildren();showStatus('');if(!$('#sheet').open)$('#sheet').showModal();$('#sheet').scrollTop=0;return $('#sheetExtra');
  }
  function field(form,title,key,type,value,options){
    const label=el('label','field-label'),input=el(type==='textarea'?'textarea':type==='select'?'select':'input');
    if(type==='select')for(const option of options){const o=el('option','',option);o.value=option;input.append(o)}
    else if(type==='textarea'){input.rows=3;input.maxLength=500}else input.type=type;
    input.name=key;input.value=value??'';
    if(['text','date'].includes(type))input.required=key==='title'||key==='date';
    if(type==='number'){input.min='0';input.max='10000000';input.step='1';input.required=true}
    if(type==='text')input.maxLength=80;
    label.append(el('span','',title),input);form.append(label);return input;
  }
  function edit(group,item=null){
    const configs={transactions:'流水',purchases:'问过柯的',meals:'一餐',promises:'想一起吃的',medicines:'药品',notes:'纸条',changes:'变动记录',budget:'每月上限',saving:'一起存'};
    const host=openEditor((item?'修改':'添加')+configs[group],item?'保留原记录人，修改后另作标记。':'这条会标为“我记的”。');
    if(item)host.append(author(item));
    const form=el('form','detail-form record-form');
    field(form,group==='medicines'?'药品名称':'名称','title','text',item?.title||'');
    if(['transactions','purchases','budget','saving'].includes(group))field(form,group==='saving'?'已存金额':'金额（元）','amount','number',item?.amount||0);
    if(group==='saving')field(form,'目标金额','target','number',item?.target||0);
    if(['transactions','meals','changes'].includes(group))field(form,'日期','date','date',item?.date||PondUI.controls.asOf);
    if(group==='purchases'){field(form,'状态','status','select',item?.status||'还没问',['还没问','柯点头了','先等等']);field(form,'柯的一句话','quote','textarea',item?.quote||'')}
    if(group==='meals'){field(form,'店名或在哪里吃的','place','text',item?.place||'');field(form,'感觉怎么样','rating','select',item?.rating||'好吃',['好吃','一般','踩雷']);field(form,'柯的一句话','quote','textarea',item?.quote||'')}
    if(group==='medicines'){
      field(form,'剂量（照原药单填写）','dose','text',item?.dose||'');field(form,'原记录中的时间','time','text',item?.time||'');field(form,'用法备注（照原记录填写）','note','textarea',item?.note||'');field(form,'当前状态','active','select',item?.active===false?'已停用':'正在吃',['正在吃','已停用']);
      form.append(el('p','field-hint','这里只整理药单，不建议剂量或改药。'));
    }
    if(group==='notes'){field(form,'内容','detail','textarea',item?.detail||'');field(form,'提醒时间（选填）','reminder','datetime-local',item?.reminder||'');form.append(el('p','field-hint','这里只预览提醒时间，不发送系统通知。'))}
    if(group==='changes')field(form,'变动说明','detail','textarea',item?.detail||'');
    const save=el('button','primary-action','保存');save.type='submit';form.append(save);
    form.onsubmit=e=>{
      e.preventDefault();const values=Object.fromEntries(new FormData(form));values.title=values.title.trim();if(!values.title){showStatus('请写一个名称。');return}
      for(const k of ['amount','target'])if(k in values)values[k]=Number(values[k]);
      if('active'in values)values.active=values.active==='正在吃';
      const record={...(item||{}),...values,id:item?.id||crypto.randomUUID(),author:item?.author||'user',edited:Boolean(item)};
      if(group==='medicines'){
        record.taken=item?.taken||false;
        const labels={title:'药名',dose:'剂量',time:'时间',note:'备注',active:'状态'};
        const showValue=(key,value)=>key==='active'?(value?'正在吃':'已停用'):String(value||'未填写');
        const changes=Object.keys(labels).filter(key=>!item||record[key]!==item[key]).map(key=>`${labels[key]}：${item?showValue(key,item[key])+' → ':''}${showValue(key,record[key])}`);
        if(changes.length)state.changes.unshift({id:crypto.randomUUID(),title:(item?'调整：':'新增：')+record.title,detail:changes.join('\n'),date:PondUI.controls.asOf,author:'user',before:item?{...item}:null,after:{...record}});
      }
      if(['notes','promises'].includes(group))record.done=item?.done||false;
      if(['budget','saving'].includes(group))state[group]=record;
      else if(item)state[group][state[group].findIndex(i=>i.id===item.id)]=record;
      else state[group].unshift(record);
      $('#sheet').close();render();announce('已更新示例记录。');
    };
    host.append(form);
    if(item&&!['budget','saving'].includes(group)){
      const remove=button('删除这条',()=>{
        remove.hidden=true;const confirm=el('div','delete-confirm');confirm.append(el('p','',`删除“${item.title}”？`),button('取消',()=>{confirm.remove();remove.hidden=false}),button('确认删除',()=>{
          deleted={group,item,index:state[group].findIndex(i=>i.id===item.id)};state[group]=state[group].filter(i=>i.id!==item.id);
          if(group==='medicines')state.changes.unshift({id:crypto.randomUUID(),title:'移除：'+item.title,detail:'已从当前药单移除',date:PondUI.controls.asOf,author:'user'});
          $('#sheet').close();render();announce('已删除示例记录。',true);
        },'delete-action'));host.append(confirm);
      },'delete-action');host.append(remove);
    }
  }
  function announce(text,undo=false){clearTimeout(statusTimer);status.replaceChildren(el('span','',text));status.hidden=false;if(undo)status.append(button('撤销',()=>{if(!deleted)return;state[deleted.group].splice(deleted.index,0,deleted.item);if(deleted.group==='medicines')state.changes.unshift({id:crypto.randomUUID(),title:'恢复：'+deleted.item.title,detail:'撤销移除',date:PondUI.controls.asOf,author:'user'});deleted=null;render();announce('已恢复。')}));else statusTimer=setTimeout(()=>{status.hidden=true},3000)}
  function purse(){
    const monthly=state.transactions.filter(item=>item.date.startsWith(state.month));
    const spent=monthly.reduce((sum,i)=>sum+i.amount,0),remaining=state.budget.amount-spent;
    const progress=(value,total,label,cls='')=>{
      const percent=total>0?Math.max(0,Math.min(100,value/total*100)):0;
      const track=el('div','money-progress '+cls),fill=el('span','money-progress-fill');
      track.setAttribute('role','progressbar');track.setAttribute('aria-label',label);
      track.setAttribute('aria-valuemin','0');track.setAttribute('aria-valuemax','100');
      track.setAttribute('aria-valuenow',String(Math.round(percent)));track.setAttribute('aria-valuetext',total>0?`${label}，${Math.round(percent)}%`:'尚未设置目标');
      fill.style.width=percent+'%';track.append(fill);return track;
    };
    const balance=el('section','balance-section balance-visual');
    balance.setAttribute('aria-label','本月余额与一起存');
    balance.append(el('p','balance-label',remaining<0?'这个月已超出':'这个月还能花'),el('p','balance-number'+(remaining<0?' over-budget':''),money(Math.abs(remaining))));
    balance.append(progress(remaining,state.budget.amount,'本月可用余额'));
    const footer=el('div','balance-footer');footer.append(el('span','',`已花 ${money(spent)}`),button(`每月上限 ${money(state.budget.amount)}`,()=>edit('budget',state.budget)));
    balance.append(footer,author(state.budget));
    if(state.budget.amount===0)balance.append(el('p','book-help','还没设置月上限，点上方金额即可设置。'));
    const saving=el('div','saving-summary'),openSaving=button('',()=>edit('saving',state.saving),'saving-edit');
    openSaving.setAttribute('aria-label','修改一起存：'+state.saving.title);
    openSaving.append(el('span','saving-name','一起存 · '+state.saving.title),el('span','saving-amount',`${money(state.saving.amount)} / ${money(state.saving.target)}`));
    saving.append(openSaving,progress(state.saving.amount,state.saving.target,'一起存目标进度','saving-progress'),author(state.saving));balance.append(saving);book.append(balance);
    book.append(el('p','book-help purse-help','柯记下的账，你也可以点开修改或删除。'));
    section('问过柯的',state.purchases,item=>{const b=row(item,'purchases',money(item.amount),item.quote?`柯：${item.quote}`:'');b.querySelector('.record-line').after(el('span','record-state',item.status));return b},()=>edit('purchases'));
    section('这个月的流水',monthly,item=>row(item,'transactions',`−${money(item.amount)}`,day(item.date)),()=>edit('transactions'));
  }
  function checklist(item,group,meta=''){
    const wrap=el('div','check-row'+(item.done?' completed':'')),label=el('label','check-target'),input=el('input');input.type='checkbox';input.checked=item.done;input.setAttribute('aria-label',`完成${item.title}`);
    input.onchange=()=>{item.done=input.checked;item.edited=true;render();announce(item.done?'已完成。':'已恢复待办。')};label.append(input);wrap.append(label,row(item,group,meta));return wrap;
  }
  function menu(){
    section('吃过的',state.meals,item=>{const b=row(item,'meals',day(item.date),item.quote?`柯：${item.quote}`:'');const detail=el('span','meal-caption');detail.append(el('span','rating rating-'+({'好吃':'good','一般':'normal','踩雷':'bad'}[item.rating]),item.rating),el('span','',item.place));b.querySelector('.record-line').after(detail);return b},()=>edit('meals'));
    section('柯的账本上欠着的',state.promises,item=>checklist(item,'promises'),()=>edit('promises'));
  }
  function meds(){
    const active=state.medicines.filter(i=>i.active),groups=Map.groupBy?Map.groupBy(active,item=>item.time||'未写时间'):active.reduce((m,item)=>{const key=item.time||'未写时间';m.set(key,[...(m.get(key)||[]),item]);return m},new Map());
    const today=el('section','book-section today-meds'),head=heading('今天');head.append(el('span','record-meta',day(PondUI.controls.asOf)));today.append(head);
    if(!active.length)today.append(el('p','book-empty','当前没有正在吃的药品。'));
    for(const [time,items] of groups){
      const count=items.filter(i=>i.taken).length,title=time==='早'?'早的药':time==='睡前'?'睡前的药':time+'的药';
      const wrap=el('div','medicine-dose-group'),label=el('label','dose-check'),input=el('input');input.type='checkbox';input.checked=count===items.length;input.indeterminate=count>0&&count<items.length;input.setAttribute('aria-label',`标记${title}已吃`);
      input.onchange=()=>{items.forEach(item=>item.taken=input.checked);render();announce(input.checked?'这组已记为吃了；可再点一下撤销。':'已撤销这组今天的标记。')};
      label.append(input,el('span','',title),el('small','',count===items.length?'吃了':count?'部分已记':'还没吃'));wrap.append(label,el('p','dose-names',items.map(i=>i.title).join(' · ')));
      const authors=el('div','dose-authors');[...new Set(items.map(i=>i.author))].forEach(a=>authors.append(author({author:a})));wrap.append(authors);today.append(wrap);
    }
    book.append(today);
    const current=section('现在在吃的',active,item=>row(item,'medicines',item.dose||'未填剂量',item.time),()=>edit('medicines'));
    current.querySelector('.book-section-heading').after(el('p','book-help','医生改了药，在这里更新。'));
    const stopped=state.medicines.filter(i=>!i.active);if(stopped.length){const disclosure=el('details','stopped-meds');disclosure.append(el('summary','',`已停用 · ${stopped.length}`));stopped.forEach(item=>disclosure.append(row(item,'medicines','已停用',item.note)));book.append(disclosure)}
    section('变动记录',state.changes,item=>row(item,'changes',day(item.date),item.detail),()=>edit('changes'));
  }
  function notes(){
    const pending=state.notes.filter(i=>!i.done),done=state.notes.filter(i=>i.done);
    book.append(el('p','book-lead',pending.length?`${pending.length} 件小事，慢慢来。`:'要做的小事都完成了。'));
    const s=section('待办',pending,item=>{const card=el('article','sticky-note '+(item.author==='ke'?'note-ke':'note-user'));card.append(checklist(item,'notes'));if(item.detail)card.append(el('p','note-detail',item.detail));if(item.reminder)card.append(el('p','note-time',item.reminder.replace('T',' ').slice(5)));return card},()=>edit('notes'));
    s.classList.add('notes-section');
    const disclosure=el('details','completed-notes');disclosure.append(el('summary','',`已完成 · ${done.length}`));done.forEach(item=>disclosure.append(checklist(item,'notes')));book.append(disclosure);
  }
  function render(){
    if(!route)return;book.replaceChildren();
    const top=el('header','book-top');top.append(button('返回水面',()=>{location.hash='pond'},'book-back'));book.append(top);
    const title=el('div','book-title');title.append(el('h1','',pages[route][0]),el('p','book-script',pages[route][1]));book.append(title);
    ({purse,menu,meds,notes}[route])();
    book.append(el('p','book-demo','示例内容 · 仅当前页面保留，刷新重置'));
  }
  function navigate(){
    const next=location.hash.slice(1),was=route;
    clearTimeout(statusTimer);status.hidden=true;
    if(pages[next]){
      if(!was){returnScroll=window.scrollY;returnFocus=document.activeElement}route=next;home.hidden=true;book.hidden=false;render();window.scrollTo(0,0);book.querySelector('h1').tabIndex=-1;book.querySelector('h1').focus({preventScroll:true});
    }else{route='';book.hidden=true;home.hidden=false;status.hidden=true;if(was){window.scrollTo(0,returnScroll);returnFocus?.focus({preventScroll:true})}}
  }
  const old=PondUI.openList;PondUI.openList=name=>{if(routeByName[name])location.hash=routeByName[name];else old(name)};
  window.addEventListener('hashchange',navigate);navigate();
})();
window.NotebooksReady.catch(()=>{document.querySelector('#pageStatus').classList.remove('sr-only');document.querySelector('#pageStatus').textContent='小本子示例没有加载成功，请刷新重试。'});
