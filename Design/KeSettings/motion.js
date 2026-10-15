(function(root){
  'use strict';
  const clamp=n=>Math.min(1,Math.max(0,n));
  function step(position,velocity,target,dt,config){
    const h=Math.min(dt,config.maxFrameStepSeconds)/4;
    for(let i=0;i<4;i++){velocity+=(-config.stiffness*(position-target)-config.damping*velocity)/config.mass*h;position+=velocity*h}
    return {position,velocity};
  }
  function release(position,velocity,config){return position+velocity*config.projectionSeconds>=config.releaseThreshold?1:0}
  const api={clamp,step,release};if(typeof module!=='undefined')module.exports=api;else root.DrawerMotion=api;
})(typeof window!=='undefined'?window:globalThis);
