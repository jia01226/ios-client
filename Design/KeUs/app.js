'use strict';
(async()=>{
await window.PondReady;
const $=s=>document.querySelector(s);
const monthNames=['一月','二月','三月','四月','五月','六月','七月','八月','九月','十月','十一月','十二月'];
const [initialYear,initialMonth]=PondUI.data.calendar.month.split('-').map(Number);
const exampleToday=PondUI.controls.asOf;
let year=initialYear,month=initialMonth-1,selected=Number(exampleToday.slice(8));
const key=()=>`${year}-${month}-${selected}`;
const editSelectedDay=()=>PondUI.openDay(key(),`${year}年${month+1}月${selected}日`,renderCalendar);
function renderCalendar(){
  $('#monthLabel').textContent=`${year} · ${monthNames[month]}`;
  $('#days').replaceChildren();
  const offset=(new Date(year,month,1).getDay()+6)%7;
  const count=new Date(year,month+1,0).getDate();
  const slots=Math.max(35,Math.ceil((offset+count)/7)*7);
  for(let i=0;i<slots;i++){
    const d=i-offset+1;
    if(d<1||d>count){$('#days').append(document.createElement('span'));continue}
    const b=document.createElement('button');b.className='date';
    const dateISO=PondCalendar.iso(`${year}-${month}-${d}`);
    const entry=PondUI.getDay(`${year}-${month}-${d}`);
    if(entry.period)b.classList.add('period');
    if(dateISO===exampleToday){b.classList.add('today');b.setAttribute('aria-current','date')}
    if(d===selected)b.classList.add('selected');
    const shift=entry.shift;
    b.setAttribute('aria-label',`${year}年${month+1}月${d}日${shift?'，'+shift:''}${entry.period?'，月经':''}${entry.note?'，有备注':''}`);
    b.dataset.id=`calendar-${dateISO}`;
    b.setAttribute('aria-pressed',String(d===selected));
    const n=document.createElement('span');n.className='number';n.textContent=d;b.append(n);
    if(shift){const s=document.createElement('small');s.textContent=shift;b.append(s)}
    if(entry.note){const dot=document.createElement('i');dot.className='note-mark';dot.setAttribute('aria-hidden','true');b.append(dot)}
    if(entry.anniversary){const m=document.createElement('span');m.className='mark';m.textContent='☾';m.setAttribute('aria-hidden','true');b.append(m)}
    b.addEventListener('click',()=>{selected=d;renderCalendar();$('#days .selected').focus({preventScroll:true});editSelectedDay()});$('#days').append(b);
  }
  $('#dayNote').textContent=`${selected}日 · ${PondCalendar.iso(key())===exampleToday?'今日':'当日'}记事`;
}
document.addEventListener('pond-calendar-change',renderCalendar);
function moveMonth(delta){const d=new Date(year,month+delta,1);year=d.getFullYear();month=d.getMonth();selected=Math.min(selected,new Date(year,month+1,0).getDate());renderCalendar()}
$('#previousMonth').onclick=()=>moveMonth(-1);$('#nextMonth').onclick=()=>moveMonth(1);renderCalendar();
const sheet=$('#sheet');
$('.close').onclick=()=>sheet.close();sheet.addEventListener('click',e=>{if(e.target===sheet){const r=sheet.getBoundingClientRect();if(e.clientX<r.left||e.clientX>r.right||e.clientY<r.top||e.clientY>r.bottom)sheet.close()}});
document.querySelectorAll('.water-entry').forEach(b=>{b.setAttribute('aria-label',`打开${b.dataset.name}`);b.onclick=()=>PondUI.openList(b.dataset.name)});
document.querySelectorAll('[data-tab]').forEach(b=>b.onclick=()=>{if(b.dataset.tab==='柯')PondUI.openList('草稿');else if(b.dataset.tab==='柯的')PondUI.openCollection()});
$('#dayNote').onclick=editSelectedDay;
$('#schedule').onclick=editSelectedDay;

// A continuous body wave includes the head, then grows through the tail.
// Each strip follows the local tangent; slow yaw and speed changes alternate
// strokes and glides. Each fish has its own stroke rhythm and gently varying path.
const canvas=$('#water'),ctx=canvas.getContext('2d');
const fish=new Image();fish.src='assets/koi.png';
const petal=new Image();petal.src='assets/petal-water-v2.png';
let width=0,height=0,clock=0,last=0,raf=0,visible=true,manualPause=false;
const reduced=matchMedia('(prefers-reduced-motion: reduce)');
let reducedPause=reduced.matches;
const rippleEvents=[];
// Composed negative-space lanes keep petals away from the four entry labels.
// A small paired arrival is followed by a longer breath; there is no full reset.
let randomSeed=7319,nextPetalAt=1.8,arrival=0;
const random=()=>{randomSeed=(Math.imul(1664525,randomSeed)+1013904223)>>>0;return randomSeed/4294967296};
const petalPool=[];
const smooth=n=>{const p=Math.max(0,Math.min(1,n));return p*p*(3-2*p)};
const petalRoutes=[
  [[.47,-.08],[.38,.18],[.56,.41],.138],
  [[.94,.10],[.92,.30],[.935,.58],.112],
  [[.56,.29],[.49,.48],[.47,.86],.145],
  [[.055,.12],[.085,.31],[.067,.63],.105]
];
const routeOrder=[0,2,1,3,2,0,3,1];
const arrivalGaps=[3.0,1.8,3.6,2.5,3.2,2.0,3.8,2.7];
function newPetal(start){
  const route=petalRoutes[routeOrder[arrival++%routeOrder.length]];
  return {start,route,phase:random()*Math.PI*2,size:route[3]*(.94+random()*.12),
    fall:7.5+random()*3,rest:1.6+random()*1.6,fade:3.5+random()*1.5,
    rotation:(random()-.5)*.4,flutter:.55+random()*.3,landed:false};
}
[-2,-8].forEach(start=>petalPool.push(newPetal(start)));
function addRipple(x,y,source){
  rippleEvents.push({x,y,time:clock,source});
  if(rippleEvents.length>16)rippleEvents.shift();
}
function resize(){const r=canvas.getBoundingClientRect();width=r.width;height=r.height;const dpr=Math.min(devicePixelRatio||1,2);canvas.width=Math.round(width*dpr);canvas.height=Math.round(height*dpr);ctx.setTransform(dpr,0,0,dpr,0,0);draw()}
function ring(x,y,rx,alpha){ctx.beginPath();ctx.ellipse(x,y,rx,rx*.27,-.08,0,Math.PI*2);ctx.strokeStyle=`rgba(126,167,194,${alpha})`;ctx.lineWidth=.7;ctx.stroke();ctx.beginPath();ctx.ellipse(x,y-1,rx*.93,rx*.245,-.08,0,Math.PI*2);ctx.strokeStyle=`rgba(255,255,255,${alpha*2.6})`;ctx.stroke()}
function drawFish(index){
  if(!fish.complete||!fish.naturalWidth)return;
  const h=width*(index?.235:.28),w=h*fish.naturalWidth/fish.naturalHeight;
  const slices=80,sh=fish.naturalHeight/slices,dh=h/slices;
  const pose=PondFishMotion.pose(clock,index,width,height,h,slices);
  ctx.save();ctx.translate(pose.x,pose.y);ctx.rotate(pose.angle);ctx.globalAlpha=index?.77:.86;
  for(let j=0;j<slices;j++){
    const f=j/slices,a=pose.points[j],b=pose.points[j+1];
    const fins=Math.exp(-Math.pow((f-.31)/.09,2));
    const breadth=w*(1+fins*.045*Math.sin(pose.beat-.8));
    // Shared strip boundaries stay joined; independently rotated slices leave seams.
    ctx.save();ctx.transform(1,0,(b.x-a.x)/dh,(b.y-a.y)/dh,a.x,a.y);
    ctx.drawImage(fish,0,j*sh,fish.naturalWidth,Math.min(sh+1,fish.naturalHeight-j*sh),-breadth/2,0,breadth,dh+.18);ctx.restore();
  }
  ctx.restore();
  // Submerged fish do not continuously emit surface circles.
}
function draw(){
  if(!width)return;ctx.clearRect(0,0,width,height);
  drawFish(0);drawFish(1);
  if(clock>=nextPetalAt){if(petalPool.length<7)petalPool.push(newPetal(clock));nextPetalAt=clock+arrivalGaps[arrival%arrivalGaps.length]+random()*.35}
  for(let i=petalPool.length-1;i>=0;i--){
    const p=petalPool[i],age=clock-p.start,total=p.fall+p.rest+p.fade;
    if(age>=total){petalPool.splice(i,1);continue}
    const f=Math.min(age/p.fall,1),air=1-smooth(f),landed=Math.max(0,age-p.fall);
    const travel=smooth(f),one=1-travel,[a,b,c]=p.route;
    const sway=Math.sin(age*p.flutter+p.phase)*.007*air;
    const x=width*(one*one*a[0]+2*one*travel*b[0]+travel*travel*c[0]+sway+Math.sin(landed*.25)*.002);
    const y=height*(one*one*a[1]+2*one*travel*b[1]+travel*travel*c[1]);
    const opacity=.75*smooth(age/2)*(1-smooth((age-p.fall-p.rest)/p.fade));
    if(f===1&&!p.landed){
      p.landed=true;
      addRipple(x/width,(y+width*p.size*.09)/height,'petal');
    }
    if(!petal.complete||!petal.naturalWidth)continue;
    ctx.save();ctx.translate(x,y);ctx.rotate(p.rotation+Math.sin(age*p.flutter+p.phase)*.18*air);
    ctx.scale(1,.77+air*(.12+.06*Math.cos(age*p.flutter+p.phase)));
    ctx.globalAlpha=opacity;ctx.drawImage(petal,-width*p.size/2,-width*p.size/2,width*p.size,width*p.size);ctx.restore();
  }
  for(let i=rippleEvents.length-1;i>=0;i--){
    const r=rippleEvents[i],age=clock-r.time,duration=r.source==='petal'?4.2:3.4;
    if(age>duration){rippleEvents.splice(i,1);continue}
    for(let wave=0;wave<3;wave++){
      const elapsed=age-wave*.38;
      if(elapsed<0)continue;
      const progress=Math.min(1,elapsed/duration);
      const reach=r.source==='petal'?.095:.15;
      const strength=(r.source==='petal'?.26:.32)*(1-wave*.20);
      ring(r.x*width,r.y*height,width*(.012+reach*(1-Math.pow(1-progress,1.6))),strength*smooth(elapsed/.22)*Math.pow(1-progress,1.5));
    }
  }
}
function isPaused(){return manualPause||reducedPause||document.hidden||!visible||sheet.open}
function tick(now){raf=0;if(isPaused()){last=0;return}if(last)clock+=Math.min((now-last)/1000,.05);last=now;draw();raf=requestAnimationFrame(tick)}
function sync(){cancelAnimationFrame(raf);raf=0;last=0;draw();document.documentElement.classList.toggle('motion-paused',isPaused());if(!isPaused())raf=requestAnimationFrame(tick);const stopped=manualPause||reducedPause;$('#motionToggle').textContent=stopped?'继续动效':'暂停动效';$('#motionToggle').setAttribute('aria-pressed',String(stopped))}
$('#motionToggle').onclick=()=>{if(manualPause||reducedPause){manualPause=false;reducedPause=false}else manualPause=true;sync()};
reduced.addEventListener('change',()=>{reducedPause=reduced.matches;sync()});document.addEventListener('visibilitychange',sync);
sheet.addEventListener('close',sync);
new IntersectionObserver(([entry])=>{visible=entry.isIntersecting;sync()},{threshold:0}).observe(canvas);
new ResizeObserver(resize).observe(canvas);fish.onload=draw;petal.onload=draw;
canvas.addEventListener('click',e=>{if(isPaused())return;const r=canvas.getBoundingClientRect();addRipple((e.clientX-r.left)/r.width,(e.clientY-r.top)/r.height,'tap')});
sync();
})().catch(error=>{console.error('预览未启动',error.message)});
