import {memories as demoMemories,project,makeDust,meteorDelay,meteorPath,starPulse} from './model.mjs';
const allMemories=demoMemories;
let memories=[...allMemories],category='全部';

const $=id=>document.getElementById(id),world=$('universe');
const sky=$('sky'),light=$('light'),canvas=$('galaxy');
const bg=sky.getContext('2d'),fx=light.getContext('2d');
const reduced=matchMedia('(prefers-reduced-motion: reduce)');
const camera={angle:0,tilt:.58,zoom:1,x:0,y:0};
let target={...camera},savedCamera=null,width=430,height=932,dpr=1,time=0,lastTime=0;
let paused=reduced.matches,selected=null,noticeTimer,returnFocus=null,frameId=0,previousGesture=false;
const pointers=new Map(),loved=new Set();
let pinching=null,dragging=null,momentum={x:0,y:0},meteors=[],nextMeteor=1.2,meteorCount=0;
let gl=null,program=null,uniforms={},count=0,renderFailed=false;
const controls=[...document.querySelectorAll('header,footer,#star-targets,#settings')];

function initGL(){
 gl=canvas.getContext('webgl',{alpha:true,antialias:false,premultipliedAlpha:false,preserveDrawingBuffer:true,powerPreference:'low-power'});
 if(!gl)throw new Error('WebGL unavailable');
 const vertex=`
 attribute vec3 aPosition; attribute vec4 aStyle;
 uniform vec2 uResolution; uniform vec2 uOffset; uniform float uAngle; uniform float uTilt; uniform float uZoom; uniform float uDpr;
 varying vec4 vColor;
 void main(){
 float c=cos(uAngle),s=sin(uAngle);
 float ry=aPosition.x*s+aPosition.y*c,st=sqrt(1.-uTilt*uTilt);
 float depth=ry*st+aPosition.z*uTilt,perspective=1./(1.-depth*.29),parallax=1.+depth*.36;
 vec2 p=vec2(aPosition.x*c-aPosition.y*s,ry*uTilt-aPosition.z*st);
 float cr=cos(-.19),sr=sin(-.19);p=vec2(p.x*cr-p.y*sr,p.x*sr+p.y*cr);
 p=p*uResolution.x*.47*uZoom*perspective+uResolution*vec2(.5,.555)+uOffset*parallax;
 gl_Position=vec4(p.x/uResolution.x*2.-1.,1.-p.y/uResolution.y*2.,0.,1.);
 gl_PointSize=aStyle.x*uDpr*min(uZoom,1.6)*perspective;
 vec3 cool=mix(vec3(.68,.74,.86),vec3(.82,.68,.76),aStyle.z*.58);
 vec3 warm=mix(cool,vec3(1.,.94,.84),1.-smoothstep(.02,.38,aStyle.w));
 vColor=vec4(warm,aStyle.y*clamp(.83+depth*.40,.36,1.25));
 }`;
 const fragment=`precision mediump float;varying vec4 vColor;void main(){vec2 p=gl_PointCoord-.5;float r=length(p);if(r>.5)discard;float a=exp(-r*r*10.)*vColor.a;gl_FragColor=vec4(vColor.rgb,a);}`;
 const compile=(type,source)=>{const shader=gl.createShader(type);gl.shaderSource(shader,source);gl.compileShader(shader);if(!gl.getShaderParameter(shader,gl.COMPILE_STATUS))throw new Error(gl.getShaderInfoLog(shader));return shader;};
 program=gl.createProgram();gl.attachShader(program,compile(gl.VERTEX_SHADER,vertex));gl.attachShader(program,compile(gl.FRAGMENT_SHADER,fragment));gl.linkProgram(program);
 if(!gl.getProgramParameter(program,gl.LINK_STATUS))throw new Error(gl.getProgramInfoLog(program));
 gl.useProgram(program);const data=makeDust();count=data.length/7;
 const buffer=gl.createBuffer();gl.bindBuffer(gl.ARRAY_BUFFER,buffer);gl.bufferData(gl.ARRAY_BUFFER,data,gl.STATIC_DRAW);
 for(const [name,size,offset] of [['aPosition',3,0],['aStyle',4,12]]){const a=gl.getAttribLocation(program,name);gl.enableVertexAttribArray(a);gl.vertexAttribPointer(a,size,gl.FLOAT,false,28,offset);}
 for(const name of ['uResolution','uOffset','uAngle','uTilt','uZoom','uDpr'])uniforms[name]=gl.getUniformLocation(program,name);
 gl.enable(gl.BLEND);gl.blendFunc(gl.SRC_ALPHA,gl.ONE);gl.clearColor(0,0,0,0);
}
function resize(){
 const box=world.getBoundingClientRect();width=box.width;height=box.height;dpr=Math.min(window.devicePixelRatio||1,3);
 for(const c of [sky,light,canvas]){c.width=Math.round(width*dpr);c.height=Math.round(height*dpr);}
 bg.setTransform(dpr,0,0,dpr,0,0);fx.setTransform(dpr,0,0,dpr,0,0);
 if(gl)gl.viewport(0,0,canvas.width,canvas.height);
}
function glow(ctx,x,y,r,color,alpha){
 const g=ctx.createRadialGradient(x,y,0,x,y,r);g.addColorStop(0,`rgba(${color},${alpha})`);g.addColorStop(.2,`rgba(${color},${alpha*.42})`);g.addColorStop(1,`rgba(${color},0)`);ctx.fillStyle=g;ctx.fillRect(x-r,y-r,r*2,r*2);
}
function drawSky(){
 bg.clearRect(0,0,width,height);bg.fillStyle='#05070d';bg.fillRect(0,0,width,height);
 const core=project([0,0,0],camera,width,height);
 glow(bg,core.x,core.y,width*.65,'91,107,140',.10);
 glow(bg,core.x-width*.19,core.y+height*.065,width*.35,'137,104,127',.075);
 glow(bg,core.x,core.y,100*camera.zoom,'207,200,191',.22);
 const distant={...camera,x:camera.x*.15,y:camera.y*.15,zoom:.94+(camera.zoom-1)*.15};
 for(const [position,radius,rgb,alpha] of [
  [[-.65,.1,-.35],.32,'91,105,144',.075],[[.65,-.3,-.2],.34,'130,99,119',.06],[[.05,.5,-.4],.42,'101,108,127',.07]
 ]){const p=project(position,distant,width,height);glow(bg,p.x,p.y,width*radius,rgb,alpha);}
}
function drawGalaxy(){
 if(!gl||renderFailed)return;gl.clear(gl.COLOR_BUFFER_BIT);gl.useProgram(program);
 gl.uniform2f(uniforms.uResolution,width,height);gl.uniform2f(uniforms.uOffset,camera.x,camera.y);gl.uniform1f(uniforms.uAngle,camera.angle);gl.uniform1f(uniforms.uTilt,camera.tilt);gl.uniform1f(uniforms.uZoom,camera.zoom);gl.uniform1f(uniforms.uDpr,dpr);gl.drawArrays(gl.POINTS,0,count);
}
function star(x,y,size,pulse,isLoved=false,isSelected=false,rays=true){
 const rgb=isLoved?'237,197,207':'206,218,240';glow(fx,x,y,size*(5+2*pulse),rgb,.19*pulse);glow(fx,x,y,size*2.3,rgb,.39*pulse);
 fx.save();fx.translate(x,y);fx.scale(.88+.12*pulse,.88+.12*pulse);fx.globalAlpha*=Math.min(1,.55+.4*pulse);fx.beginPath();
 if(rays){fx.moveTo(0,-size*1.5);fx.bezierCurveTo(size*.12,-size*.18,size*.18,-size*.12,size,0);fx.bezierCurveTo(size*.18,size*.12,size*.12,size*.18,0,size*1.5);fx.bezierCurveTo(-size*.12,size*.18,-size*.18,size*.12,-size,0);fx.bezierCurveTo(-size*.18,-size*.12,-size*.12,-size*.18,0,-size*1.5);}
 else{fx.arc(0,0,size*.28,0,Math.PI*2);}
 fx.fillStyle='#f5f6fa';fx.fill();
 if(isSelected){fx.strokeStyle='#e1c8fa88';fx.lineWidth=.8;fx.beginPath();fx.arc(0,0,size*3.3,0,Math.PI*2);fx.stroke();}fx.restore();
}
let starButtons=[];
function buildMemoryUI(){
 memories=allMemories.filter(m=>category==='全部'||m.category===category);
 $('star-targets').replaceChildren();$('list-items').replaceChildren();
 $('memory-count').textContent=`${memories.length} 颗记忆`;
 $('list-open').firstChild.textContent=`查看 ${memories.length} 颗记忆 `;
 $('empty-memory').hidden=memories.length>0;
 $('empty-memory').textContent='这个分类还没有可显示的示例。';
 starButtons=memories.map((memory,i)=>{
 const b=document.createElement('button');b.className='star-target';b.dataset.memoryId=memory.id;b.setAttribute('aria-label',`查看记忆：${memory.title}`);
 if(i===0||i===2||i===6){const label=document.createElement('span');label.className='star-label';label.textContent=memory.title;b.append(label);}
 b.addEventListener('click',e=>{if(previousGesture&&e.detail!==0){e.preventDefault();return;}openMemory(memory,b);});$('star-targets').append(b);return b;
});
 for(const m of [...memories].reverse()){const b=document.createElement('button');b.className='list-item';const name=document.createElement('span'),date=document.createElement('small');name.textContent=m.title;date.textContent=`${m.category} · ${m.day||'日期未记'}`;b.append(name,date);b.addEventListener('click',()=>openMemory(m,$('list-open')));$('list-items').append(b);}
}
function buildCategories(){
 $('categories').replaceChildren();
 for(const label of ['全部',...new Set(allMemories.filter(m=>m.state!=='withered').map(m=>m.category))]){
  const b=document.createElement('button');b.textContent=label;b.setAttribute('aria-pressed',String(category===label));b.addEventListener('click',()=>{category=label;buildCategories();buildMemoryUI();target={angle:camera.angle,tilt:.58,zoom:1,x:0,y:0};});$('categories').append(b);
 }
}
function drawLights(){
 fx.clearRect(0,0,width,height);const c=project([0,0,0],camera,width,height);
 const coreBreath=.94+.06*starPulse(time,3);
 glow(fx,c.x,c.y,66*camera.zoom,'229,222,212',.34*coreBreath);glow(fx,c.x,c.y,29*camera.zoom,'251,240,226',.63*coreBreath);glow(fx,c.x,c.y,11*camera.zoom,'255,250,242',.9);
 const projected=memories.map((m,i)=>({m,i,p:project(m.position,camera,width,height)})).sort((a,b)=>a.p.depth-b.p.depth);
 for(const {m,i,p} of projected){
  const pulse=m.state==='fallen'?.7:starPulse(time,i),dim=m.author==='other'?.43:m.state==='fallen'?.5:1;
  fx.globalAlpha=dim*Math.max(.55,Math.min(1,.8+p.depth*.35));
  const size=(m.central?7.5:m.importance?2.5+m.importance*.22:i%3===0?4.9:3.9)*Math.min(camera.zoom,1.6)*p.perspective;
  star(p.x,p.y,size,pulse,loved.has(m.id),selected===m,!m.central&&m.author!=='other'&&i%3!==1);fx.globalAlpha=1;
  const b=starButtons[i];b.style.left=`${p.x}px`;b.style.top=`${p.y}px`;b.style.zIndex=String(Math.round((p.depth+2)*100));b.style.visibility=p.x<18||p.x>width-18||p.y<215||p.y>height-125?'hidden':'visible';if(b.firstChild)b.firstChild.style.opacity=selected?'0':'.85';
 }
 for(const m of meteors){
  const age=time-m.start,t=age/1.9;if(t<0||t>1)continue;const x=m.x+m.dx*t,y=m.y+m.dy*t,tail=.26;
  const tx=x-m.dx*tail,ty=y-m.dy*tail,intensity=Math.sin(t*Math.PI);
  const g=fx.createLinearGradient(tx,ty,x,y);g.addColorStop(0,'rgba(171,190,220,0)');g.addColorStop(.65,`rgba(204,218,238,${.5*intensity})`);g.addColorStop(1,`rgba(250,249,246,${intensity})`);fx.strokeStyle=g;fx.lineWidth=1.4;fx.beginPath();fx.moveTo(tx,ty);fx.lineTo(x,y);fx.stroke();glow(fx,x,y,7,'219,232,252',.65*intensity);
 }
 meteors=meteors.filter(m=>time-m.start<1.9);
}
function meteor(manual=false){
 if(paused||reduced.matches){if(manual)notice('动态已暂停，恢复后就能看流星');return;}
 meteors.push({...meteorPath(width,height),start:time});meteorCount++;world.dataset.meteors=String(meteorCount);if(manual)notice('抬头，有一颗流星');
}
function tick(stamp){
 const dt=Math.min(.04,(stamp-lastTime)/1000||0);lastTime=stamp;
 if(!paused)time+=dt;
 if(!paused&&!selected&&!pointers.size){target.angle+=dt*.013;target.x+=momentum.x*dt;target.y+=momentum.y*dt;momentum.x*=Math.exp(-dt*6);momentum.y*=Math.exp(-dt*6);clampCamera();}
 const ease=reduced.matches||pointers.size?1:1-Math.exp(-dt*8);
 for(const k of Object.keys(camera))camera[k]+=(target[k]-camera[k])*ease;
 if(!paused&&time>=nextMeteor){meteor();nextMeteor=time+meteorDelay();}
 drawSky();drawGalaxy();drawLights();world.dataset.zoom=camera.zoom.toFixed(2);world.dataset.angle=camera.angle.toFixed(3);
 frameId=requestAnimationFrame(tick);
}
function clampCamera(){target.zoom=Math.max(.8,Math.min(1.85,target.zoom));target.x=Math.max(-width*.48,Math.min(width*.48,target.x));target.y=Math.max(-height*.22,Math.min(height*.22,target.y));target.tilt=Math.max(.34,Math.min(.82,target.tilt));}
world.addEventListener('pointerdown',e=>{
 if(selected||!$('memory-list').hidden||e.target.closest('header,footer,#settings,.notice'))return;
 if(e.pointerType==='mouse'&&e.button!==0)return;
 previousGesture=false;momentum={x:0,y:0};pointers.set(e.pointerId,{x:e.clientX,y:e.clientY});
 if(pointers.size===1){dragging={x:e.clientX,y:e.clientY,lastX:e.clientX,lastY:e.clientY,t:e.timeStamp};target={...camera};}
 if(pointers.size===2){const [a,b]=[...pointers.values()];pinching={distance:Math.hypot(a.x-b.x,a.y-b.y),zoom:camera.zoom};previousGesture=true;}
});
world.addEventListener('pointermove',e=>{
 if(!pointers.has(e.pointerId))return;
 pointers.set(e.pointerId,{x:e.clientX,y:e.clientY});
 if(pointers.size===2&&pinching){const[a,b]=[...pointers.values()];target.zoom=pinching.zoom*Math.hypot(a.x-b.x,a.y-b.y)/Math.max(1,pinching.distance);clampCamera();return;}
 if(!dragging)return;const dx=e.clientX-dragging.lastX,dy=e.clientY-dragging.lastY;
 if(Math.hypot(e.clientX-dragging.x,e.clientY-dragging.y)>7){previousGesture=true;world.setPointerCapture(e.pointerId);target.x+=dx;target.y+=dy;target.tilt+=dy*.00065;const dt=Math.max(.008,(e.timeStamp-dragging.t)/1000);momentum={x:dx/dt*.42,y:dy/dt*.42};clampCamera();}
 dragging.lastX=e.clientX;dragging.lastY=e.clientY;dragging.t=e.timeStamp;
});
function endPointer(e){pointers.delete(e.pointerId);if(pointers.size<2)pinching=null;if(!pointers.size)dragging=null;else{const p=[...pointers.values()][0];dragging={x:p.x,y:p.y,lastX:p.x,lastY:p.y,t:e.timeStamp};}}
world.addEventListener('pointerup',endPointer);world.addEventListener('pointercancel',e=>{endPointer(e);momentum={x:0,y:0};previousGesture=true;});
world.addEventListener('wheel',e=>{if(selected||!$('memory-list').hidden||e.target.closest('#settings'))return;e.preventDefault();target.zoom*=Math.exp(-e.deltaY*.0013);clampCamera();},{passive:false});
function notice(message){$('notice').textContent=message;$('notice').classList.add('visible');clearTimeout(noticeTimer);noticeTimer=setTimeout(()=>$('notice').classList.remove('visible'),2300);}
function closeSettings(){ $('settings').hidden=true;$('menu-toggle').setAttribute('aria-expanded','false');}
function setModal(open){for(const el of controls)el.inert=open;}
function updateLove(){const value=selected&&loved.has(selected.id);$('love-toggle').setAttribute('aria-pressed',String(!!value));$('love-toggle').querySelector('span').textContent=value?'已喜欢 · 仅本次预览':'这颗我很喜欢';}
function openMemory(memory,source){
 closeSettings();$('memory-list').hidden=true;returnFocus=source||$('list-open');if(!selected)savedCamera={...camera};selected=memory;momentum={x:0,y:0};
 target={...camera,zoom:Math.min(1.65,camera.zoom*1.22),x:0,y:0};const p=project(memory.position,target,width,height);target.x=(width*.5-p.x)/p.parallax;target.y=(height*.30-p.y)/p.parallax;
 $('memory-title').textContent=memory.title;$('memory-category').textContent=memory.category;$('memory-body').textContent=memory.body;$('memory-quote').textContent=memory.quote;
 $('memory-date').textContent=`10 月 ${Number(memory.day.split('.')[1])} 日 · 示例`;
 $('memory-order').textContent=`${memories.indexOf(memory)+1} / ${memories.length}`;
 $('memory-prev').disabled=memories.indexOf(memory)===0;$('memory-next').disabled=memories.indexOf(memory)===memories.length-1;
 updateLove();$('memory-card').hidden=false;setModal(true);$('memory-close').focus({preventScroll:true});
}
function closeMemory(){if(!selected)return;$('memory-card').hidden=true;selected=null;if(savedCamera)target={...savedCamera};setModal(false);returnFocus?.focus({preventScroll:true});}
$('memory-close').addEventListener('click',closeMemory);
$('love-toggle').addEventListener('click',()=>{if(!selected)return;loved.has(selected.id)?loved.delete(selected.id):loved.add(selected.id);updateLove();});
$('menu-toggle').addEventListener('click',()=>{const open=$('settings').hidden;$('settings').hidden=!open;$('menu-toggle').setAttribute('aria-expanded',String(open));});
world.addEventListener('click',e=>{if(!e.target.closest('#settings,#menu-toggle'))closeSettings();});
function motionLabel(){ $('motion-toggle').textContent=paused?'恢复星河动态':'暂停星河动态';$('motion-toggle').setAttribute('aria-pressed',String(paused));world.dataset.paused=String(paused);}
$('motion-toggle').addEventListener('click',()=>{if(reduced.matches){notice('已跟随系统减弱动态效果');return;}paused=!paused;meteors=[];momentum={x:0,y:0};motionLabel();});
reduced.addEventListener('change',()=>{paused=reduced.matches;meteors=[];motionLabel();});
$('meteor-trigger').addEventListener('click',()=>{closeSettings();meteor(true);});
$('zoom-in').addEventListener('click',()=>{target.zoom+=.2;clampCamera();});$('zoom-out').addEventListener('click',()=>{target.zoom-=.2;clampCamera();});
$('reset-camera').addEventListener('click',()=>{target={angle:0,tilt:.58,zoom:1,x:0,y:0};momentum={x:0,y:0};closeSettings();});
function closeList(){ $('memory-list').hidden=true;setModal(false);$('list-open').focus();}
$('list-open').addEventListener('click',()=>{closeSettings();$('memory-list').hidden=false;setModal(true);$('list-close').focus();});$('list-close').addEventListener('click',closeList);
$('memory-prev').addEventListener('click',()=>{const m=memories[memories.indexOf(selected)-1];if(m)openMemory(m,$('list-open'));});
$('memory-next').addEventListener('click',()=>{const m=memories[memories.indexOf(selected)+1];if(m)openMemory(m,$('list-open'));});
buildCategories();buildMemoryUI();
document.addEventListener('keydown',e=>{
 if(e.key==='Escape'){if(selected)closeMemory();else if(!$('memory-list').hidden)closeList();else closeSettings();}
 const modal=selected?$('memory-card'):!$('memory-list').hidden?$('memory-list'):null;
 if(e.key==='Tab'&&modal){const buttons=[...modal.querySelectorAll('button:not(:disabled)')],first=buttons[0],last=buttons.at(-1);if(e.shiftKey&&document.activeElement===first){e.preventDefault();last.focus();}else if(!e.shiftKey&&document.activeElement===last){e.preventDefault();first.focus();}}
});
document.addEventListener('visibilitychange',()=>{if(document.hidden){cancelAnimationFrame(frameId);frameId=0;}else if(!frameId){lastTime=performance.now();frameId=requestAnimationFrame(tick);}});
canvas.addEventListener('webglcontextlost',e=>{e.preventDefault();renderFailed=true;$('render-error').hidden=false;});
canvas.addEventListener('webglcontextrestored',()=>{try{initGL();resize();renderFailed=false;$('render-error').hidden=true;}catch{$('render-error').hidden=false;}});
try{initGL();}catch(error){renderFailed=true;$('render-error').hidden=false;console.error(error);}
new ResizeObserver(resize).observe(world);resize();motionLabel();frameId=requestAnimationFrame(tick);
