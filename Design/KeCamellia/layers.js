(() => {
 'use strict';
 const L=window.KE_CAMELLIA_LAYOUT;
 const phone=document.querySelector('.phone'), garden=document.querySelector('.garden');
 const pause=document.getElementById('pause'), selection=document.getElementById('selection');
 const media=matchMedia('(prefers-reduced-motion: reduce)');
 const asset=id=>L.assets[id].file;
 const setFrame=(el,f)=>Object.assign(el.style,{left:f.x*100+'%',top:f.y*100+'%',width:f.width*100+'%',height:f.height*100+'%'});
 const img=(id,cls,parent,frame)=>{
  const el=document.createElement('img');el.src=asset(id);el.alt='';el.className=cls;
  if(frame)setFrame(el,frame);parent.append(el);return el;
 };
 const bg=img('background','atmosphere',phone,L.background.frame);phone.prepend(bg);
 garden.replaceChildren();
 img('stem','branch',garden,L.branch.frame);
 const buttons=[];
 for(const f of L.flowers){
  img(f.asset,'sprite-flower',garden,f.frame);
  img(f.tag.asset,'tag-sprite',garden,f.tag.frame);
  const line=document.createElement('div');line.className='tag-string';
  Object.assign(line.style,{left:f.tag.string.x*100+'%',top:f.tag.string.top*100+'%',height:(f.tag.string.bottom-f.tag.string.top)*100+'%'});garden.append(line);
  const label=document.createElement('span');label.className='tag-text';label.textContent=f.label;setFrame(label,f.tag.frame);garden.append(label);
  const b=document.createElement('button');b.className='flower';b.style.transform='none';
  b.dataset.id=f.id;b.setAttribute('aria-label',f.label+'，选择该入口的演示内容');
  // Include the hanging tag in the same accessible hit target.
  const x=Math.min(f.hitFrame.x,f.tag.frame.x),y=Math.min(f.hitFrame.y,f.tag.frame.y);
  const right=Math.max(f.hitFrame.x+f.hitFrame.width,f.tag.frame.x+f.tag.frame.width);
  const bottom=Math.max(f.hitFrame.y+f.hitFrame.height,f.tag.frame.y+f.tag.frame.height);
  setFrame(b,{x,y,width:right-x,height:bottom-y});garden.append(b);buttons.push(b);
 }
 const butterfly=document.createElement('div');butterfly.className='butterfly';
 const shape=document.createElement('div');shape.className='butterfly-shape';butterfly.append(shape);garden.append(butterfly);
 img('wing-left','wing left',shape);img('wing-right','wing right',shape);img('body','body',shape);
 const fixtures={
  diary:{title:'柯刚刚写下',excerpt:'今晚的月色，让我想起你。'},
  dream:{title:'柯留下一个梦',excerpt:'梦里有一扇开着的窗。'},
  drawer:{title:'抽屉里多了一件收藏',excerpt:'把这一刻，轻轻收好。'},
  tarot:{title:'一张牌，等你翻开',excerpt:'留一点好奇给明天。'},
  moments:{title:'柯刚刚分享',excerpt:'窗边的山茶，今天开了。'},
  memory:{title:'柯记起一个片段',excerpt:'有些平常的日子，一直记得。'}
 };
 let time=0,last=0,paused=false,visible=true,flight=null,serial=0,nextPetal=5500;
 let current='diary',position={...L.flowers[0].butterflyPerch.center};
 const petals=[];
 function place(){butterfly.style.transform='translate3d('+(position.x*garden.clientWidth-butterfly.clientWidth/2)+'px,'+(position.y*garden.clientHeight-butterfly.clientHeight/2)+'px,0)';}
 function commit(event){
  current=event.kind;
  document.querySelector('.diary h1').textContent=event.title;
  document.querySelector('.diary p').textContent=event.excerpt;
  document.querySelector('.diary time').textContent='离线示例';
  document.querySelector('.photo div').style.backgroundImage='url('+asset(event.kind)+')';
  document.querySelector('.photo div').style.backgroundSize='100% auto';
  document.querySelector('.photo div').style.backgroundPosition='center';
  selection.textContent='蝴蝶停在'+L.flowers.find(f=>f.id===current).label+'，卡片内容已同步';
  for(const b of buttons)b.setAttribute('aria-pressed',String(b.dataset.id===current));
 }
 function select(kind,instant=false){
  const f=L.flowers.find(f=>f.id===kind);if(!f)return;
  const event={id:'demo-'+(++serial),kind,...fixtures[kind]};
  if(media.matches||paused||instant){flight=null;position={...f.butterflyPerch.center};butterfly.classList.remove('flying');commit(event);place();return;}
  flight={from:{...position},to:{...f.butterflyPerch.center},start:time,event};
  butterfly.classList.add('flying');selection.textContent='蝴蝶正飞向'+f.label+'；落下后同步卡片';
 }
 function sync(){
  phone.classList.toggle('paused',paused||document.hidden||!visible);
  phone.classList.toggle('reduced',media.matches);
  pause.textContent=paused?'继续动效':'暂停动效';pause.setAttribute('aria-pressed',String(paused));
 }
 for(const b of buttons)b.addEventListener('click',e=>select(b.dataset.id,e.detail===0));
 for(const b of document.querySelectorAll('[data-demo]'))b.addEventListener('click',()=>select(b.dataset.demo));
 pause.addEventListener('click',()=>{paused=!paused;sync();});
 document.addEventListener('visibilitychange',sync);
 new IntersectionObserver(es=>{visible=es[0].isIntersecting;sync();}).observe(phone);
 new ResizeObserver(place).observe(garden);
 media.addEventListener('change',()=>{if(flight)select(flight.event.kind,true);sync();});
 function spawn(){
  if(petals.length>=3)return;
  const n=Math.floor(time/5500),el=img(L.petals.assets[n%3],'falling-petal',phone);
  Object.assign(el.style,{left:(70+n%3*10)+'%',top:'18%',width:(3.5+n%3)+'%'});
  petals.push({el,expires:time+11000});
 }
 function frame(now){
  const dt=last?Math.min(now-last,50):0;last=now;
  if(!paused&&!document.hidden&&visible&&!media.matches){
   time+=dt;
   if(flight){
    const t0=Math.min(1,(time-flight.start)/3000),t=t0*t0*(3-2*t0),arc=Math.sin(Math.PI*t);
    position={x:flight.from.x+(flight.to.x-flight.from.x)*t+.08*arc,y:flight.from.y+(flight.to.y-flight.from.y)*t-.06*arc};place();
    if(t0===1){const event=flight.event;flight=null;butterfly.classList.remove('flying');commit(event);}
   }
   for(let i=petals.length-1;i>=0;i--)if(petals[i].expires<=time){petals[i].el.remove();petals.splice(i,1);}
   if(time>=nextPetal){spawn();nextPetal=time+5500;}
  }
  requestAnimationFrame(frame);
 }
 select('diary',true);sync();requestAnimationFrame(frame);
})();
