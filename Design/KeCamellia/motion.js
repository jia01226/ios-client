(() => {
  'use strict';
  const phone = document.querySelector('.phone');
  const garden = document.querySelector('.garden');
  const butterfly = document.querySelector('.butterfly');
  const buttons = [...document.querySelectorAll('.flower')];
  const pauseButton = document.getElementById('pause');
  const selection = document.getElementById('selection');
  const media = matchMedia('(prefers-reduced-motion: reduce)');
  const flowers = [{x:.81,y:.142,name:'日记'}, {x:.66,y:.27,name:'梦'}, {x:.47,y:.403,name:'抽屉'}, {x:.83,y:.462,name:'塔罗'}, {x:.26,y:.578,name:'朋友圈'}, {x:.30,y:.272,name:'记忆'}];
  const visitingOrder = [0,5,1,2,3,4];
  let selected=1, paused=false, visible=true, flight=null, time=0, last=0, nextFlight=6500;
  let position = point(1);
  function point(index) { const f=flowers[index]; return {x:f.x-.065,y:f.y-.029}; }
  function place(p) { butterfly.style.transform=`translate3d(${p.x*garden.clientWidth-butterfly.clientWidth/2}px,${p.y*garden.clientHeight-butterfly.clientHeight/2}px,0)`; }
  function announce(index) { buttons.forEach((b,i)=>b.setAttribute('aria-pressed',String(i===index))); selection.textContent=`蝴蝶${flight?'正飞向':'停在'}${flowers[index].name}上`; }
  function go(index, instant=false) {
    selected=index;
    const end=point(index);
    if(media.matches || instant) {position=end;flight=null;butterfly.classList.remove('flying');place(position);}
    else {flight={start:{...position},end,startTime:time,duration:3000,side:index%2===0?-1:1};butterfly.classList.add('flying');}
    nextFlight=time+9500;
    announce(index);
  }
  function syncPause() {phone.classList.toggle('paused',paused||document.hidden||!visible); phone.classList.toggle('reduced',media.matches);pauseButton.textContent=paused?'继续动效':'暂停动效';pauseButton.setAttribute('aria-pressed',String(paused));}
  buttons.forEach((b,i)=>b.addEventListener('click',event=>go(i,event.detail===0 || paused)));
  pauseButton.addEventListener('click',()=>{paused=!paused;syncPause();});
  document.addEventListener('visibilitychange',syncPause);
  new IntersectionObserver(entries=>{visible=entries[0].isIntersecting;syncPause();}).observe(phone);
  media.addEventListener('change',()=>{go(selected,true);syncPause();});
  new ResizeObserver(()=>place(position)).observe(garden);
  function frame(now) {
    const delta=last?Math.min(now-last,50):0;last=now;
    if(!paused&&!document.hidden&&visible&&!media.matches){
      time+=delta;
      if(flight){
        const raw=Math.min(1,(time-flight.startTime)/flight.duration);
        const t=raw*raw*(3-2*raw), arc=Math.sin(t*Math.PI);
        position={x:flight.start.x+(flight.end.x-flight.start.x)*t+flight.side*.105*arc,y:flight.start.y+(flight.end.y-flight.start.y)*t-.06*arc};
        place(position);
        if(raw===1){flight=null;butterfly.classList.remove('flying');announce(selected);}
      }else if(time>nextFlight){go(visitingOrder[(visitingOrder.indexOf(selected)+1)%visitingOrder.length]);}
    }
    requestAnimationFrame(frame);
  }
  place(position);announce(selected);syncPause();requestAnimationFrame(frame);
})();
