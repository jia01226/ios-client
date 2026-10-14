'use strict';
const pondFrames=[...document.querySelectorAll('iframe')];
window.addEventListener('message',event=>{
  if(event.origin!==location.origin||event.data?.type!=='pond-height')return;
  const frame=pondFrames.find(item=>item.contentWindow===event.source);
  if(frame&&Number.isFinite(event.data.height))frame.style.height=`${Math.max(200,Math.min(3000,event.data.height))}px`;
});
const motionButton=document.querySelector('#motion');
let paused=matchMedia('(prefers-reduced-motion: reduce)').matches;
function updateMotionLabel(){motionButton.textContent=paused?'继续动效':'暂停动效';motionButton.setAttribute('aria-pressed',String(paused))}
updateMotionLabel();
motionButton.addEventListener('click',()=>{for(const frame of pondFrames)frame.contentWindow.postMessage({type:'pond-toggle-motion'},location.origin);paused=!paused;updateMotionLabel()});
