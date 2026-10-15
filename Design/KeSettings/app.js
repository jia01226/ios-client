'use strict';
(async()=>{
  const $=s=>document.querySelector(s),make=(tag,cls,text)=>{const e=document.createElement(tag);if(cls)e.className=cls;if(text!==undefined)e.textContent=text;return e};
  const load=async file=>{const response=await fetch(file);if(!response.ok)throw Error(file);return response.json()};
  const [data,tokens,layout,motion]=await Promise.all(['sample-data','tokens','layout','motion'].map(name=>load('spec/'+name+'.json')));
  const cfg=motion.drawer,state=data.settings,phone=$('#phone'),drawer=$('#drawer'),overlay=$('#overlay'),base=$('#base-page'),scroll=$('#drawer-scroll');
  let palette=data.palette,route='',page='chat',position=0,velocity=0,target=0,raf=0,last=0,drag=null,restoreFocus=null,toastTimer,guideTimer,suppressClickUntil=0,directoryScrollTop=0;
  const reduced=matchMedia('(prefers-reduced-motion: reduce)');
  const icon=name=>{const svg=document.createElementNS('http://www.w3.org/2000/svg','svg'),use=document.createElementNS(svg.namespaceURI,'use');use.setAttribute('href','#'+name+'-icon');svg.append(use);svg.setAttribute('aria-hidden','true');return svg};
  const announce=text=>{clearTimeout(toastTimer);$('#toast').textContent=text;$('#toast').hidden=false;toastTimer=setTimeout(()=>$('#toast').hidden=true,3500)};
  function setPalette(key){
    palette=key;const colors=tokens.colors.day,paper=tokens.palettes[key];
    const vars={paper:paper.dayPaper,ink:colors.textPrimary,muted:colors.textSecondary,line:colors.line,accent:colors.accent,'on-accent':colors.onAccent,focus:colors.focus};
    Object.entries(vars).forEach(([k,v])=>document.documentElement.style.setProperty('--'+k,v));document.documentElement.dataset.palette=key;
  }
  document.documentElement.style.setProperty('--drawer-width',layout.drawer.widthRatio*100+'%');
  $('#edge-handle').style.width=layout.drawer.edgeHitPx+'px';$('#directory').style.minHeight=layout.drawer.minimumDirectoryHeight+'px';
  setPalette(palette);
  function renderHome(){
    const info=data.shells.find(s=>s.id===page),content=$('#home-content');$('#home-title').textContent=info.name;content.replaceChildren(make('p','',info.subtitle));
    if(page==='chat')content.append(make('div','chat-line','今天想怎么过？'),make('div','chat-line mine','陪我慢一点。'),make('div','chat-line','好，听你的。'));
    if(page==='us'){content.append(make('p','script','With you, ordinary days shine.'),make('div','shell-note','在一起'),make('p','shell-count','111 天'),make('p','','日历与记事，留在原来的页面。'))}
    if(page==='ke'){const flower=make('img','shell-flower');flower.src='assets/flower@3x.png';flower.alt='';content.append(make('p','script','Just with you.'),make('p','shell-note','日记 · 梦 · 朋友圈'),flower)}
    content.append(make('p','detail-note','底页为示意，内容均为示例。'));
    document.querySelectorAll('[data-page]').forEach(b=>{if(b.dataset.page===page)b.setAttribute('aria-current','page');else b.removeAttribute('aria-current')});
  }
  renderHome();document.querySelectorAll('[data-page]').forEach(b=>b.onclick=()=>{page=b.dataset.page;renderHome()});
  for(const art of layout.art){const img=make('img','art art-'+art.id);img.src='assets/'+art.file;img.alt='';img.draggable=false;for(const key of ['left','top','width','height'])img.style[key]=art[key]*100+'%';img.style.opacity=art.opacity;$('#botanical').append(img)}
  const butterfly=make('span','butterfly');const bf=layout.butterfly;Object.assign(butterfly.style,{left:bf.left*100+'%',top:bf.top*100+'%',width:bf.widthPx+'px',height:bf.heightPx+'px',opacity:bf.opacity});
  for(const part of ['wing-left','wing-right','body']){const img=make('img');img.src='assets/'+part+'@3x.png';img.alt='';img.draggable=false;butterfly.append(img)}$('#botanical').append(butterfly);
  $('.directory-title h2').textContent=data.drawerTitle;$('.directory-title p').textContent=layout.title.poem;
  for(const item of data.entries){const place=layout.entries.find(e=>e.id===item.id),b=make('button','directory-link');b.dataset.id='settings-'+item.id;b.dataset.side=place.side;b.style.left=place.left*100+'%';b.style.top=place.top*100+'%';b.setAttribute('aria-label',item.title+' · '+item.label);b.append(make('strong','',item.title),make('small','',item.label));b.onclick=()=>showDetail(item.id);$('#directory-links').append(b)}
  function group(title){const section=make('section','setting-group');if(title)section.append(make('h3','',title));$('#detail').append(section);return section}
  function toggle(section,title,key){const row=make('label','setting-row'),input=make('input');input.type='checkbox';input.setAttribute('role','switch');input.checked=state[key];input.dataset.id=key;input.onchange=()=>{state[key]=input.checked;announce('已更改预览，不影响 App。')};row.append(make('span','',title),input);section.append(row);return input}
  function select(section,title,key,options){const row=make('label','setting-row stack'),input=make('select');input.dataset.id=key;for(const value of options){const option=make('option','',value);option.value=value;input.append(option)}input.value=state[key];input.onchange=()=>{state[key]=input.value;announce('已更改预览，不影响 App。')};row.append(make('span','',title),input);section.append(row)}
  function time(section,title,key){const row=make('label','setting-row'),input=make('input');input.type='time';input.value=state[key];input.dataset.id=key;input.onchange=()=>{if(input.value)state[key]=input.value};row.append(make('span','',title),input);section.append(row)}
  function action(section,title,fn){const button=make('button','setting-row action');button.append(make('span','',title),icon('arrow'));button.onclick=fn;section.append(button)}
  function note(section,text){section.append(make('p','row-note',text))}
  function showDetail(id){
    directoryScrollTop=scroll.scrollTop;route=id;const entry=data.entries.find(e=>e.id===id),detail=$('#detail');$('#directory').hidden=true;detail.hidden=false;$('#back-directory').hidden=false;$('#drawer-caption').textContent=entry.label;
    detail.replaceChildren(make('h2','detail-title',entry.title+' · '+entry.label),make('p','detail-script',entry.en));
    if(id==='chat'){const s=group('说话的样子');select(s,'气泡','bubble',['轻透','纸笺','素净']);select(s,'壁纸','wallpaper',['沿用纸色','淡淡花影','不显示图案']);select(group('对话模型'),'用哪个模型','model',['沿用 App 设置','示例模型 A','示例模型 B']);note(detail,'模型选项为示例，真实可用模型由 App 提供。')}
    if(id==='visits'){const s=group('他来找你的时候');toggle(s,'允许柯主动来找你','visits');select(s,'来找你的多少','frequency',['少一点','适中','多一点']);const quiet=group('不打扰');toggle(quiet,'开启安静时段','quiet');time(quiet,'从','quietStart');time(quiet,'到','quietEnd');note(quiet,'结束时间早于开始时间时，表示跨到第二天。')}
    if(id==='reminders'){for(const [title,key,timeKey] of [['吃药','medicine','medicineTime'],['到家','home','homeTime'],['睡前','bedtime','bedtimeTime']]){const s=group(title);toggle(s,'开启提醒',key);time(s,'提醒时间',timeKey)}note(detail,'这里只预览提醒时间，不修改药单，也不发送通知。')}
    if(id==='palette'){const field=make('fieldset','palette-list');field.append(make('legend','','选一款纸色'));for(const [key,paper] of Object.entries(tokens.palettes)){const label=make('label','palette-choice'),input=make('input'),swatch=make('span','swatch');input.type='radio';input.name='palette';input.value=key;input.checked=palette===key;input.onchange=()=>{setPalette(key);announce('已换纸色，底页和抽屉一起变化。')};swatch.style.background=paper.dayPaper;swatch.setAttribute('aria-hidden','true');label.append(input,make('span','',paper.label),swatch);field.append(label)}detail.append(field);note(detail,'做进 App 后统一作用于全部页面。此处只改变三个示例底页与设置抽屉，不提供夜晚模式。')}
    if(id==='notifications'){const s=group('想收到哪些通知');toggle(s,'柯的新消息','notifyMessages');toggle(s,'日记和朋友圈','notifyDiary');toggle(s,'日常提醒','notifyReminders');toggle(s,'有新版本','notifyUpdates');note(detail,'不会请求浏览器通知权限；真实推送由 App 接入。')}
    if(id==='privacy'){const s=group('只给你看');toggle(s,'面容解锁','faceID');toggle(s,'启用私密空间','privateSpace');action(s,'打开私密空间',()=>announce('演示：将打开私密空间，不读取真实内容。'));note(detail,'开关仅演示样式，不提供真实身份验证或隐私保护。')}
    if(id==='updates'){detail.append(make('p','balance-label','当前版本'),make('p','version-number',data.version));action(group(''),'打开更新页',()=>announce('演示：将打开 App 更新页，地址由 Claude 接入。'));note(detail,'这里不下载、不安装、不检查真实更新。')}
    if(id==='about'){note(detail,'柯 · 私人陪伴');detail.append(make('p','version-number',data.version));const label=make('label','message-label'),area=make('textarea');area.value=state.message;area.maxLength=500;area.placeholder='想说的、想改的，都可以写下来。';area.oninput=()=>state.message=area.value;label.append(make('span','','给 Claude 留话'),area);const save=make('button','primary-button','留在本页');save.onclick=()=>announce(state.message.trim()?'留言已留在当前预览；未发送给 Claude，刷新会清空。':'先写一点想说的话。');detail.append(label,save);note(detail,'不发送到外部，也不保存真实个人信息。')}
    detail.append(make('p','detail-note','示例设置 · 刷新后重置'));scroll.scrollTop=0;const title=detail.querySelector('h2');title.tabIndex=-1;title.focus({preventScroll:true});
    if(!reduced.matches)detail.animate([{opacity:.5,transform:`translateX(${motion.detail.translatePx}px)`},{opacity:1,transform:'translateX(0)'}],{duration:motion.detail.enterMs,easing:'cubic-bezier(.16,1,.3,1)'});
  }
  function directory(focus=true){const old=route;route='';$('#detail').hidden=true;$('#directory').hidden=false;$('#back-directory').hidden=true;$('#drawer-caption').textContent='设置';scroll.scrollTop=focus?directoryScrollTop:0;if(focus&&old){const entry=document.querySelector(`[data-id="settings-${old}"]`);entry?.focus({preventScroll:true});entry?.scrollIntoView({block:'nearest',inline:'nearest'})}}
  $('#back-directory').onclick=()=>directory();
  function paint(){drawer.style.transform=`translateX(${(1-position)*100}%)`;$('#scrim').style.opacity=String(DrawerMotion.clamp(position)*cfg.scrimOpacity)}
  function mount(){if(overlay.hidden){restoreFocus=document.activeElement;overlay.hidden=false;base.inert=true;$('#edge-handle').inert=true;$('#open-drawer').setAttribute('aria-expanded','true');drawer.focus({preventScroll:true})}}
  function finish(){if(target===0){overlay.hidden=true;base.inert=false;$('#edge-handle').inert=false;$('#open-drawer').setAttribute('aria-expanded','false');directory(false);(restoreFocus?.isConnected?restoreFocus:$('#open-drawer')).focus({preventScroll:true})}}
  function tick(now){const dt=last?Math.min((now-last)/1000,cfg.maxFrameStepSeconds):1/60;last=now;const step=DrawerMotion.step(position,velocity,target,dt,cfg);position=step.position;velocity=step.velocity;
    if(Math.abs(position-target)<cfg.positionEpsilon&&Math.abs(velocity)<cfg.velocityEpsilon){position=target;velocity=0;raf=0;paint();finish();return}paint();raf=requestAnimationFrame(tick)}
  function settle(to,v=velocity){target=to;velocity=v;cancelAnimationFrame(raf);raf=0;last=0;if(to||position>0)mount();if(reduced.matches){position=target;velocity=0;paint();finish()}else raf=requestAnimationFrame(tick)}
  function open(){clearTimeout(guideTimer);$('#gesture-demo').hidden=true;settle(1)}
  $('#open-drawer').onclick=open;$('#edge-handle').onclick=open;$('#moon-demo').onclick=open;$('#close-drawer').onclick=()=>settle(0);$('#scrim').onclick=()=>settle(0);
  $('#edge-demo').onclick=()=>{settle(0);$('#gesture-demo').hidden=false;clearTimeout(guideTimer);guideTimer=setTimeout(open,reduced.matches?0:1100)};
  function begin(e,kind){if(e.button!==0||e.target.closest('input,select,textarea,label'))return;drag={id:e.pointerId,x:e.clientX,y:e.clientY,start:position,active:false,kind,source:e.currentTarget,history:[{x:e.clientX,t:performance.now()}]};}
  $('#edge-handle').addEventListener('pointerdown',e=>begin(e,'open'));drawer.addEventListener('pointerdown',e=>begin(e,'close'));$('#scrim').addEventListener('pointerdown',e=>begin(e,'close'));
  phone.addEventListener('pointermove',e=>{
    if(!drag||drag.id!==e.pointerId)return;const dx=e.clientX-drag.x,dy=e.clientY-drag.y;
    if(!drag.active){if(Math.abs(dy)>cfg.dragThresholdPx&&Math.abs(dy)>Math.abs(dx)){drag=null;return}if(Math.abs(dx)<cfg.dragThresholdPx||Math.abs(dx)<Math.abs(dy)*cfg.horizontalIntentRatio)return;if(drag.kind==='open'&&dx>0){drag=null;return}
      drag.active=true;cancelAnimationFrame(raf);raf=0;drag.start=position;mount();drag.source.setPointerCapture(e.pointerId)}
    e.preventDefault();position=DrawerMotion.clamp(drag.start-dx/drawer.getBoundingClientRect().width);paint();const now=performance.now();drag.history.push({x:e.clientX,t:now});drag.history=drag.history.filter(p=>now-p.t<=cfg.velocityWindowMs);
  });
  function release(e,cancel=false){if(!drag||drag.id!==e.pointerId)return;const current=drag;drag=null;if(!current.active)return;const history=current.history,first=history[0],lastPoint=history.at(-1);const age=performance.now()-lastPoint.t;const v=age>cfg.velocityWindowMs||lastPoint.t===first.t?0:-(lastPoint.x-first.x)/(lastPoint.t-first.t)*1000/drawer.getBoundingClientRect().width;suppressClickUntil=performance.now()+250;settle(cancel?target:DrawerMotion.release(position,v,cfg),cancel?0:v)}
  phone.addEventListener('pointerup',e=>release(e));phone.addEventListener('pointercancel',e=>release(e,true));phone.addEventListener('click',e=>{if(performance.now()<suppressClickUntil){e.preventDefault();e.stopImmediatePropagation()}},true);
  drawer.addEventListener('keydown',e=>{if(e.key==='Escape'){e.preventDefault();if(route)directory();else settle(0)}if(e.key==='Tab'){const nodes=[...drawer.querySelectorAll('button,input,select,textarea,[tabindex="0"]')].filter(n=>!n.disabled&&n.getClientRects().length);const first=nodes[0],lastNode=nodes.at(-1);if(e.shiftKey&&(document.activeElement===first||document.activeElement===drawer)){e.preventDefault();lastNode?.focus()}else if(!e.shiftKey&&(document.activeElement===lastNode||document.activeElement===drawer)){e.preventDefault();first?.focus()}}});
  reduced.addEventListener('change',()=>{if(reduced.matches){cancelAnimationFrame(raf);position=target;velocity=0;paint();finish()}});
  document.addEventListener('visibilitychange',()=>{if(document.hidden){cancelAnimationFrame(raf);raf=0;position=target;velocity=0;paint();finish()}});
  $('#load-status').hidden=true;paint();if(new URLSearchParams(location.search).get('open')!=='0')settle(1);
})().catch(()=>{const status=document.querySelector('#load-status');status.textContent='预览数据未加载。请通过本地 HTTP 服务打开，再刷新重试。';status.hidden=false});
