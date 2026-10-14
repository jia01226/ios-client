'use strict';
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict'),vm=require('node:vm');
const sharp=require('sharp');
const root=path.resolve(__dirname,'..');
const read=p=>fs.readFileSync(path.join(root,p),'utf8');
(async()=>{
 const L=JSON.parse(read('spec/layout.json')),M=JSON.parse(read('spec/motion.json'));
 const sandbox={window:{}};vm.runInNewContext(read('spec/layout.js'),sandbox);
 assert.equal(JSON.stringify(sandbox.window.KE_CAMELLIA_LAYOUT),JSON.stringify(L));
 assert.equal(Object.keys(L.assets).length,21);
 assert.deepEqual(L.flowers.map(f=>[f.id,f.label]),[['diary','日记'],['dream','梦'],['drawer','抽屉'],['tarot','塔罗'],['moments','朋友圈'],['memory','记忆']]);
 let partialCount=0;
 for(const [id,a] of Object.entries(L.assets)){
  const file=path.join(root,a.file),meta=await sharp(file).metadata();
  assert.equal(meta.width,a.logicalSize.width*3,id);assert.equal(meta.height,a.logicalSize.height*3,id);
  assert(meta.hasAlpha,id+' alpha');
  const {data}=await sharp(file).ensureAlpha().raw().toBuffer({resolveWithObject:true});
  let clear=0,partial=0;
  for(let i=3;i<data.length;i+=4){if(data[i]===0)clear++;if(data[i]>0&&data[i]<255)partial++;}
  assert(clear>0,id+' transparency');assert.equal(clear,a.alpha.transparentPixels);
  assert.equal(partial,a.alpha.partialPixels);partialCount+=partial>0?1:0;
 }
 for(const f of L.flowers){
  for(const r of [f.frame,f.tag.frame,f.hitFrame])for(const v of Object.values(r))assert(v>=0&&v<=1);
  assert(L.assets[f.asset]);assert(L.assets[f.tag.asset]);
  assert.equal(f.butterflyPerch.center.x,Math.round((f.center.x-.065)*1e6)/1e6);
  assert.equal(f.butterflyPerch.center.y,Math.round((f.center.y-.029)*1e6)/1e6);
 }
 const textFiles=['index.html','style.css','motion.js','layers.html','layers.css','layers.js'];
 for(const file of textFiles){
  const body=read(file);assert(!/https?:\/\//.test(body),file+' external dependency');
  assert(!/fetch\s*\(|XMLHttpRequest|WebSocket|localStorage/.test(body),file+' online/storage');
  if(file.endsWith('.js'))new vm.Script(body,{filename:file});
  for(const m of body.matchAll(/(?:src|href)="([^"#]+)"|url\(([^)'"]+)\)/g)){
   const ref=m[1]||m[2];assert(fs.existsSync(path.join(root,ref)),file+' missing '+ref);
  }
 }
 assert.equal(M.proposedProduction.autoTour,false);
 assert.equal(M.proposedPageExpansion.implemented,false);
 assert.equal(M.implementedFrozenPreview.pageExpansion,false);
 const generator=read('tools/export-assets.cjs');
 assert(!/<text(?:\s|>)/.test(generator),'PNG geometry generator must have no text nodes');
 const report={date:'2026-10-14',result:'pass',transparent3xPNGs:21,assetsWithPartialAlpha:partialCount,
  checks:['all @3x dimensions','real transparent pixels','six stable IDs and final labels','normalized flower/tag/hit/perch coordinates','JSON and offline JS manifest identical','local HTML/CSS references exist','no network or storage in previews','JavaScript parse','tag/frame native shapes contain no text nodes'],
  limitations:['Imagegen layers are reconstructed, not lossless original-layer extraction.','No native app build or device testing.','File-open execution not automated in browser; previews use classic local scripts without fetch/modules.','This report is static validation, not a performance benchmark.']};
 fs.writeFileSync(path.join(root,'review/verification.json'),JSON.stringify(report,null,2)+'\n');
 console.log(JSON.stringify(report,null,2));
})().catch(e=>{console.error(e);process.exitCode=1});
