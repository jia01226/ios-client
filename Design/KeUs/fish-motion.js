/* Head-led swimming: a continuous spine carries a travelling wave towards the
   tail. Stroke strength also changes forward speed; each fish has its own clock. */
(function(root){
  'use strict';
  const wrap=a=>Math.atan2(Math.sin(a),Math.cos(a));
  function rhythm(t,index){
    const r=t*(index?.61:.73)+index*2.3;
    return {effort:.13+.87*Math.pow((1+Math.cos(r))/2,3),beat:t*(index?2.48:2.72)+.28*Math.sin(r)+index*1.9};
  }
  function position(t,index){
    const frequency=index?.61:.73,r=t*frequency+index*2.3;
    // The derivative varies smoothly: a stroke advances, then a longer glide.
    const a=t*(index?.082:.088)+.035*Math.sin(r)+.008*Math.sin(2*r)+.4+index*2.8;
    const rx=.215+.025*Math.sin(t*.11+index),ry=.265+.025*Math.cos(t*.095+index*1.7);
    return {x:.51+rx*Math.cos(a)+.022*Math.sin(2*a+.2),y:.49+ry*Math.sin(a)+.024*Math.cos(2*a)};
  }
  function pose(t,index,width,height,length,slices=80){
    const p=position(t,index),q=position(t+.12,index),ahead=position(t+1.2,index);
    const heading=Math.atan2((q.y-p.y)*height,(q.x-p.x)*width);
    const next=Math.atan2((ahead.y-q.y)*height,(ahead.x-q.x)*width);
    const turn=wrap(next-heading),{effort,beat}=rhythm(t,index);
    // Nose anticipates the turn. The back trails behind, rather than rotating as a plate.
    const nose=turn*.65+(.065+.145*effort)*Math.sin(beat+.4);
    const points=[{x:0,y:0}];
    for(let j=1;j<=slices;j++){
      const f=(j-.5)/slices;
      const tail=Math.max(0,(f-.18)/.82);
      const amplitude=(.03+.98*Math.pow(tail,1.7))*(.24+.76*effort);
      // A small head/shoulder arc leads the travelling tail wave, even during a glide.
      const headArc=.27*(.45+.55*effort)*Math.exp(-Math.pow((f-.12)/.20,2))*Math.sin(beat+.85);
      const bend=headArc+amplitude*Math.sin(beat-tail*4.6)-turn*tail*2.1;
      const previous=points[j-1],step=length/slices;
      points.push({x:previous.x+Math.sin(bend)*step,y:previous.y+Math.cos(bend)*step});
    }
    const anchor=points[Math.round(slices*.32)];
    return {x:p.x*width,y:p.y*height,angle:heading+Math.PI/2+nose,points:points.map(v=>({x:v.x-anchor.x,y:v.y-anchor.y})),effort,beat};
  }
  const api={position,rhythm,pose};
  if(typeof module!=='undefined'&&module.exports)module.exports=api;
  else root.PondFishMotion=api;
})(typeof window!=='undefined'?window:globalThis);
