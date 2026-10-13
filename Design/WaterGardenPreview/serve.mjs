import http from 'node:http';
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import path from 'node:path';
const root=path.dirname(fileURLToPath(import.meta.url));
const port=8941, host='127.0.0.1';
const mime={'.html':'text/html; charset=utf-8','.mjs':'text/javascript; charset=utf-8','.css':'text/css; charset=utf-8','.png':'image/png','.webp':'image/webp','.jpg':'image/jpeg','.ttf':'font/ttf','.webm':'video/webm','.mp4':'video/mp4','.json':'application/json'};
const server=http.createServer(async(req,res)=>{try{
 if(req.headers.host!==`${host}:${port}`&&req.headers.host!==`localhost:${port}`){res.writeHead(403).end();return}
 const url=new URL(req.url,`http://${host}:${port}`);
 if(req.method==='POST'&&url.pathname==='/capture-still'){
  const kind=url.searchParams.get('kind');
  if(req.headers.origin!==`http://${req.headers.host}`||req.headers['content-type']!=='image/png'||!['overview','detail'].includes(kind)){res.writeHead(403).end();return}
  let size=0;const parts=[];for await(const chunk of req){size+=chunk.length;if(size>16*1024*1024){res.writeHead(413).end();return}parts.push(chunk)}
  const data=Buffer.concat(parts);const raw=req.headers['x-capture-metadata']||'';
  if(raw.length>4096||data.length<24||data.subarray(0,8).toString('hex')!=='89504e470d0a1a0a'){res.writeHead(422).end();return}
  const metadata=JSON.parse(decodeURIComponent(raw));
  if(metadata.canvas?.width!==data.readUInt32BE(16)||metadata.canvas?.height!==data.readUInt32BE(20)||metadata.renderDpr!==3||metadata.physicalPixelsPerSourcePixel>1.00001){res.writeHead(422).end();return}
  const dir=path.join(root,'review','hd');await mkdir(dir,{recursive:true});
  await writeFile(path.join(dir,`${kind}-3x.png`),data);
  await writeFile(path.join(dir,`${kind}-3x.json`),JSON.stringify(metadata,null,2)+'\n');
  res.writeHead(201).end('Saved original resolution');return;
 }
 if(req.method==='POST'&&url.pathname==='/capture'){
  const allowedOrigin=`http://${req.headers.host}`;
  if(req.headers.origin!==allowedOrigin||!/^video\/(webm|mp4)(;|$)/.test(req.headers['content-type']||'')){res.writeHead(403).end();return}
  let size=0;const parts=[];for await(const chunk of req){size+=chunk.length;if(size>32*1024*1024){res.writeHead(413).end();return}parts.push(chunk)}
  const duration=Number(req.headers['x-capture-duration']),frames=Number(req.headers['x-capture-frames']);
  if(!(duration>=20000&&duration<25000&&frames>100)){res.writeHead(422).end('Incomplete capture');return}
  const ext=req.headers['content-type'].startsWith('video/mp4')?'mp4':'webm';await mkdir(path.join(root,'review'),{recursive:true});
  await writeFile(path.join(root,'review',`walkthrough-20s.${ext}`),Buffer.concat(parts));
  await writeFile(path.join(root,'review','capture.json'),JSON.stringify({durationMs:duration,renderedFrames:frames,bytes:size,mime:req.headers['content-type'],type:'Live Canvas capture with scripted camera route; not device screen recording',anonymous:true},null,2)+'\n');
  res.writeHead(201).end('Saved');return;
 }
 if(req.method!=='GET'&&req.method!=='HEAD'){res.writeHead(405).end();return}
 const base=url.pathname.startsWith('/review/')?root:path.join(root,'dist');const pathname=decodeURIComponent(url.pathname==='/'?'/index.html':url.pathname);const file=path.resolve(base,'.'+pathname);
 if(!file.startsWith(base+path.sep)){res.writeHead(403).end();return}
 const data=await readFile(file);res.writeHead(200,{'Content-Type':mime[path.extname(file)]||'application/octet-stream','Content-Length':data.length,'Cache-Control':'no-store','X-Content-Type-Options':'nosniff'});res.end(req.method==='HEAD'?undefined:data);
}catch{res.writeHead(404).end('Not found')}});
server.listen(port,host,()=>console.log(`Water garden preview: http://${host}:${port}/`));
