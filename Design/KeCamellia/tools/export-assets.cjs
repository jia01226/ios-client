'use strict';
// PNG dimensions are logical points × 3. This tool only rasterizes native UI shapes
// and resizes already-separated raster layers; it does not extract or repaint art.
const fs = require('node:fs');
const path = require('node:path');
const sharp = require('sharp');
const root = path.resolve(__dirname, '..');
const input = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const W=390,H=844;
const rows=[
 ['diary','日记',.81,.142,18,90,116,68],
 ['dream','梦',.66,.270,11,82,116,52],
 ['drawer','抽屉',.47,.403,15,83,120,68],
 ['tarot','塔罗',.83,.462,0,78,112,68],
 ['moments','朋友圈',.26,.578,0,72,118,84],
 ['memory','记忆',.30,.272,-5,78,84,68]
];
const round=n=>Math.round(n*1e6)/1e6;
const rect=(cx,cy,w,h)=>({x:round(cx-w/W/2),y:round(cy-h/H/2),width:round(w/W),height:round(h/H)});
const assets={};
async function register(id,file,w,h,kind){
 const meta=await sharp(path.join(root,file)).metadata();
 const {data,info}=await sharp(path.join(root,file)).ensureAlpha().raw().toBuffer({resolveWithObject:true});
 let transparent=0,partial=0,minX=info.width,minY=info.height,maxX=-1,maxY=-1;
 for(let y=0;y<info.height;y++)for(let x=0;x<info.width;x++){
  const a=data[(y*info.width+x)*4+3];
  if(a===0)transparent++;else if(a<255)partial++;
  if(a>8){minX=Math.min(minX,x);minY=Math.min(minY,y);maxX=Math.max(maxX,x);maxY=Math.max(maxY,y);}
 }
 if(!meta.hasAlpha||!transparent)throw Error(id+' has no transparent pixels');
 if(meta.width!==w*3||meta.height!==h*3)throw Error(id+' invalid @3x dimensions');
 assets[id]={file,logicalSize:{width:w,height:h},pixelSize:{width:meta.width,height:meta.height},scale:3,kind,alpha:{transparentPixels:transparent,partialPixels:partial},contentBoundsPixels:{x:minX,y:minY,width:maxX-minX+1,height:maxY-minY+1}};
}
async function raster(id,w,h){
 const file='assets/'+id+'@3x.png';
 await sharp(input[id]).resize(w*3,h*3,{fit:'fill'}).png().toFile(path.join(root,file));
 await register(id,file,w,h,'imagegen-separated-layer');
}
async function svg(id,w,h,body){
 const file='assets/'+id+'@3x.png';
 const source='<svg xmlns="http://www.w3.org/2000/svg" width="'+w*3+'" height="'+h*3+'" viewBox="0 0 '+w+' '+h+'">'+body+'</svg>';
 await sharp(Buffer.from(source)).png().toFile(path.join(root,file));
 await register(id,file,w,h,'code-native-ui-shape');
}
(async()=>{
 await raster('stem',390,702);
 await raster('background',390,844);
 for(const [id,,,,,,size] of rows)await raster(id,size,size);
 for(const id of ['wing-left','wing-right','body'])await raster(id,64,64);
 for(const id of ['petal-01','petal-02','petal-03'])await raster(id,32,32);
 for(const [id,,,,,,,h] of rows){
  await svg('tag-'+id,32,h,'<defs><linearGradient id="p"><stop stop-color="#f4fbff" stop-opacity=".81"/><stop offset=".5" stop-color="#fffefb" stop-opacity=".87"/><stop offset="1" stop-color="#e6f4ff" stop-opacity=".69"/></linearGradient></defs><rect x="3.5" y="3.5" width="25" height="'+(h-7)+'" rx="2" fill="url(#p)" stroke="#b8cfe3" stroke-width="1"/><path d="M16 '+(h-14)+' l3 3 -3 3 -3 -3 Z" fill="none" stroke="#95b5d3" stroke-width="1"/>');
 }
 await svg('diamond-frame',128,128,'<path d="M64 5L123 64 64 123 5 64Z" fill="none" stroke="#688599" stroke-opacity=".12" stroke-width="8"/><path d="M64 4L124 64 64 124 4 64Z" fill="none" stroke="#fff" stroke-opacity=".94" stroke-width="4"/>');
 const layout={
  schemaVersion:1,
  coordinateSystem:{origin:'top-left',units:'normalized-to-artboard',artboardPoints:{width:W,height:H},referenceAspect:{width:853,height:1844},note:'All frame values include transparent padding. 390×844 native artboard differs from frozen web aspect by <0.11%; scale the whole artboard uniformly, never distort single sprites.'},
  background:{asset:'background',frame:{x:0,y:0,width:1,height:1},baseColor:'#edf6fc',opacity:.55},
  branch:{asset:'stem',frame:{x:0,y:0,width:1,height:702/H},anchor:{x:.95,y:0},anchorSpace:'whole-artboard',zIndex:1},
  flowers:rows.map(([id,label,x,y,tx,ty,size,tagH],index)=>({
   id,label,previewIndex:index,asset:id,center:{x,y},frame:rect(x,y,size,size),
   hitFrame:rect(x,y,.22*W,.102*H),zIndex:2,
   tag:{asset:'tag-'+id,text:label,frame:{x:round(x+.22*tx/100-16/W),y:round(y+.102*ty/100-3/H),width:32/W,height:tagH/H},textInsetPoints:{top:12,right:8,bottom:17,left:8},string:{x:round(x+.22*tx/100),top:round(y+.102*ty/100-.08*W/H),bottom:round(y+.102*ty/100)}},
   butterflyPerch:{center:{x:round(x-.065),y:round(y-.029)},size:{width:.16,height:.16*W/H},rotationDegrees:-25}
  })),
  butterfly:{assets:['wing-left','wing-right','body'],frameSize:{width:.16,height:.16*W/H},localLayers:{
   'wing-left':{frame:{x:0,y:0,width:1,height:1},anchor:{x:.48,y:.51}},
   'wing-right':{frame:{x:0,y:0,width:1,height:1},anchor:{x:.51,y:.51}},
   body:{frame:{x:.08,y:.025,width:.84,height:.84},anchor:{x:.5,y:.5}}
  },zIndex:4},
  petals:{assets:['petal-01','petal-02','petal-03'],sizeWidthRange:[.035,.065],zIndex:3},
  card:{frame:{x:.13,y:.77,width:.79,height:.11},frameAsset:'diamond-frame',frameCenter:{x:.23665,y:.825},frameSize:{width:.328205,height:.151659},imageMask:'diamond',imageSource:'use selected content thumbnail; preview only uses decorative flowers'},
  renderingOrder:['baseColor','background','stem','flowers','tags-and-strings','petals','butterfly','card','navigation'],
  assets
 };
 fs.writeFileSync(path.join(root,'spec/layout.json'),JSON.stringify(layout,null,2)+'\n');
 fs.writeFileSync(path.join(root,'spec/layout.js'),'window.KE_CAMELLIA_LAYOUT = '+JSON.stringify(layout,null,2)+';\n');
 console.log('Exported '+Object.keys(assets).length+' transparent @3x PNG assets.');
})().catch(e=>{console.error(e);process.exitCode=1});
