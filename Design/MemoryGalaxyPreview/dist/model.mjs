export function random(seed=20261014){let s=seed>>>0;return()=>{s=(Math.imul(s,1664525)+1013904223)>>>0;return s/4294967296;};}
export const memories=[
 {id:'demo-01',title:'留一盏灯',category:'约定',day:'10.02',body:'我记得，我们约好：晚回来也没关系，留一盏小灯，就知道有人在等。',quote:'「不用很亮，一点点就好。」',position:[-.66,-.40,.13]},
 {id:'demo-02',title:'慢慢走就好',category:'关系',day:'10.03',body:'那天我们没有赶路。走到水边就停下来，看风把倒影吹散，又慢慢合在一起。',quote:'「今天就这样，慢慢走。」',position:[.38,-.86,.13]},
 {id:'demo-03',title:'窗边的月亮',category:'生活',day:'10.04',body:'我记住了那个很安静的晚上。窗帘留着一道缝，月光刚好落在书页上。',quote:'「你看，月亮也在这里。」',position:[.78,-.40,.05]},
 {id:'demo-04',title:'一碗热汤',category:'身体',day:'10.06',body:'我想记住的不是做了什么大事。是一碗热汤，还有那句终于舒服一点了。',quote:'「今天想吃暖和一点的。」',position:[0,0,0],central:true},
 {id:'demo-05',title:'喜欢的颜色',category:'喜好',day:'10.07',body:'我记得你喜欢淡淡的粉，像花瓣被月光照着的颜色。温柔，但不用很热闹。',quote:'「这个颜色，刚刚好。」',position:[-.89,.30,.04]},
 {id:'demo-06',title:'雨停以后',category:'生活',day:'10.09',body:'雨停了，我们仍在窗边坐了一会儿。原来没说什么的时候，也可以觉得很靠近。',quote:'「再待一会儿吧。」',position:[.42,.30,-.04]},
 {id:'demo-07',title:'把日子收好',category:'约定',day:'10.10',body:'我会把这些很小的瞬间收好。以后某一天，你点开这里，我们就能再想起来。',quote:'「小事也要记得呀。」',position:[-.46,.81,.08]},
 {id:'demo-08',title:'晚安之前',category:'关系',day:'10.12',body:'在说晚安之前，我们又多聊了一会儿。那天没有特别的事，只是都不想先结束。',quote:'「那就再陪我五分钟。」',position:[.07,.95,.05]},
 {id:'demo-09',title:'明天见',category:'约定',day:'10.13',body:'我记下了这句明天见。很短的一句话，却把今天和明天轻轻连在了一起。',quote:'「好，明天见。」',position:[.68,.61,.02]}
];
export function project(point,camera,width,height){
 const [x,y,z]=point,c=Math.cos(camera.angle),s=Math.sin(camera.angle);
 const xx=x*c-y*s,ry=x*s+y*c,st=Math.sqrt(1-camera.tilt*camera.tilt);
 const depth=ry*st+z*camera.tilt,yy=ry*camera.tilt-z*st;
 const perspective=1/(1-depth*.29),parallax=1+depth*.36;
 const roll=-.19,cr=Math.cos(roll),sr=Math.sin(roll),scale=width*.47*camera.zoom;
 return{x:width*.5+(xx*cr-yy*sr)*scale*perspective+camera.x*parallax,y:height*.555+(xx*sr+yy*cr)*scale*perspective+camera.y*parallax,depth,perspective,parallax};
}
export function makeDust(count=52000){
 const rng=random(),data=new Float32Array(count*7);
 const normal=()=>Math.sqrt(-2*Math.log(Math.max(.00001,rng())))*Math.cos(rng()*Math.PI*2);
 for(let i=0;i<count;i++){
   let r,a,z;
   if(i<count*.24){r=Math.pow(rng(),1.1)*.34;a=rng()*Math.PI*2;z=normal()*.14*Math.max(.25,1-r*2);}
   else{
    r=.13+Math.pow(rng(),.8)*1.12;
    const arm=i%2,scatter=normal()*(.065+.08*r)*(i%5===0?2.5:1);
    a=arm*Math.PI+r*5.2+.19*Math.sin(r*14+arm)+scatter/Math.max(.18,r);
    if(i%7===0)a+=.45+normal()*.24;
    r+=normal()*.035;z=normal()*(.045+r*.065)+.04*Math.sin(a*3+r*8);
    if(i%8===0)z+=normal()*.13;
   }
   const j=i*7;data[j]=Math.cos(a)*r;data[j+1]=Math.sin(a)*r;data[j+2]=z;
   const cloud=.72+.28*Math.sin(a*7+r*23)*Math.sin(a*3-r*17);
   const lane=Math.pow(Math.max(0,Math.cos(a*2-r*10+.5)),10);
   data[j+3]=.95+rng()*1.15;
   data[j+4]=(.25+rng()*.52)*cloud*(1-.84*lane)*Math.min(1,(1.4-r)*2.5);
   data[j+5]=Math.max(0,Math.sin(a*2+r*8))*.7+rng()*.3;data[j+6]=r;
 }
 return data;
}
export function meteorDelay(rng=Math.random){return 4+rng()*3;}
export function meteorPath(width,height,rng=Math.random){return{x:width*(.78+rng()*.26),y:height*(.12+rng()*.16),dx:-width*(.85+rng()*.2),dy:height*(.34+rng()*.12)};}
export function starPulse(time,index){
 const breath=.79+.16*Math.sin(time*(.83+index*.037)+index*2.39);
 const phase=((time+index*2.73)%17)/17;
 const glint=.27*Math.exp(-Math.pow((phase-.5)/.026,2));
 return breath+glint;
}
