import assert from 'node:assert/strict';
import {memories,makeDust,project,meteorDelay,meteorPath,starPulse} from './dist/model.mjs';
for(let i=0;i<100;i++){const p=meteorPath(430,932,()=>i/100);assert.ok(p.dx<0&&p.dy>0&&p.x>430*.75&&p.y<932*.3);}
const pulses=Array.from({length:1000},(_,i)=>starPulse(i*.05,2));assert.ok(Math.min(...pulses)>.6&&Math.max(...pulses)<1.23);assert.ok(Math.max(...pulses)-Math.min(...pulses)>.3);assert.notEqual(starPulse(2,1),starPulse(2,2));
assert.equal(new Set(memories.map(m=>m.id)).size,9);
assert.equal(memories.filter(m=>m.central).length,1);
assert.deepEqual(memories.find(m=>m.central).position,[0,0,0]);
assert.equal(meteorDelay(()=>0),4);assert.equal(meteorDelay(()=>1),7);
const a=makeDust(),b=makeDust();assert.deepEqual(a,b);assert.equal(a.length,52000*7);assert.ok(a.every(Number.isFinite));
const camera={angle:0,tilt:.58,zoom:1,x:0,y:0};
const far=project([.3,-.7,0],camera,430,932),near=project([.3,.7,0],camera,430,932);assert.ok(near.perspective>far.perspective&&near.parallax>far.parallax);
assert.ok(Math.max(...Array.from(a).filter((_,i)=>i%7===2))>.3);
const center=project([0,0,0],camera,430,932);assert.equal(center.x,215);assert.equal(center.y,932*.555);
const positions=memories.map(m=>project(m.position,camera,430,932));
assert.ok(positions.every(p=>p.x>22&&p.x<408&&p.y>190&&p.y<780));
for(let i=0;i<positions.length;i++)for(let j=i+1;j<positions.length;j++)assert.ok(Math.hypot(positions[i].x-positions[j].x,positions[i].y-positions[j].y)>44);
for(const m of memories){const p=project(m.position,{...camera,zoom:1.7},430,932);assert.ok(Number.isFinite(p.x)&&Number.isFinite(p.y));}
console.log('PASS: unique demo IDs, deterministic 52,000-particle geometry, projection, visible initial memory targets, 44px target separation.');
