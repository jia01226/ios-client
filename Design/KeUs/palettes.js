'use strict';
const pondPalettes=[['mist','浅雾蓝'],['white','冷白'],['ivory','暖白'],['cream','浅米色']];
const pondParams=new URLSearchParams(location.search);
const pondPalette=pondPalettes.some(([key])=>key===pondParams.get('palette'))?pondParams.get('palette'):'ivory';
document.documentElement.dataset.palette=pondPalette;
if(pondParams.has('embed'))document.documentElement.dataset.embedded='';
const paletteNav=document.createElement('nav');paletteNav.className='palette-options';paletteNav.setAttribute('aria-label','水面底色');
for(const [key,label] of pondPalettes){const a=document.createElement('a');a.href=`index.html?palette=${key}`;a.textContent=label;if(key===pondPalette)a.setAttribute('aria-current','page');paletteNav.append(a)}
const compareLink=document.createElement('a');compareLink.href='compare.html';compareLink.textContent='四款并排';paletteNav.append(compareLink);
document.querySelector('.preview-tools').append(paletteNav);
if(pondParams.has('embed')){
  const reportHeight=()=>parent.postMessage({type:'pond-height',height:Math.ceil(document.querySelector('.phone').getBoundingClientRect().height)},location.origin);
  new ResizeObserver(reportHeight).observe(document.querySelector('.phone'));
  window.addEventListener('message',event=>{if(event.origin!==location.origin||event.source!==parent)return;if(event.data?.type==='pond-toggle-motion')document.querySelector('#motionToggle').click()});
}
