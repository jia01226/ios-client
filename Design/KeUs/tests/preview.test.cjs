const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const root=path.resolve(__dirname,'..');
const calendar=require('../calendar-model.js');
const fish=require('../fish-motion.js');
const json=name=>JSON.parse(fs.readFileSync(path.join(root,'spec',name),'utf8'));

test('月经开始日计入，结束日排除，不预测未来',()=>{
  const today='2026-10-14';
  const start=calendar.changePeriod([],'2026-10-12','start',today);
  assert.equal(calendar.isPeriod(start.periods,'2026-10-12',today),true);
  assert.equal(calendar.isPeriod(start.periods,'2026-10-15',today),false);
  assert.ok(calendar.changePeriod(start.periods,'2026-10-13','start',today).error);
  assert.ok(calendar.changePeriod(start.periods,'2026-10-11','end',today).error);
  const end=calendar.changePeriod(start.periods,today,'end',today);
  assert.equal(calendar.isPeriod(end.periods,'2026-10-13',today),true);
  assert.equal(calendar.isPeriod(end.periods,today,today),false);
  assert.equal(start.periods[0].end,null);
});
test('纪念日与日期边界',()=>{
  assert.equal(calendar.count({date:'2026-06-25',annual:false},'2026-10-14').days,111);
  assert.equal(calendar.count({date:'2000-02-29',annual:true},'2027-02-27').days,1);
  assert.equal(calendar.valid('2026-02-30'),false);
  assert.equal(calendar.iso('2026-9-14'),'2026-10-14');
});
test('示例数据、预算和浅色令牌',()=>{
  const data=json('sample-data.json'),state=json('notebook-sample.json'),tokens=json('tokens.json');json('preview-controls.json');
  assert.equal(data.entries.length,4);
  const spent=state.transactions.filter(x=>x.date.startsWith(state.month)).reduce((sum,x)=>sum+x.amount,0);
  assert.equal((state.budget.amount-spent)/state.budget.amount,.62);
  assert.equal(state.saving.amount/state.saving.target,.24);
  assert.equal(Object.keys(tokens.palettes).length,4);assert.equal(tokens.colors.night,undefined);
  assert.equal(tokens.fonts.script.family,'Pinyon Script');
  assert.ok(tokens.colors.day.progressTrack&&tokens.colors.day.savingAccent);
});
test('两条鱼180秒的姿态和连续脊线数值有效',()=>{
  for(let index=0;index<2;index++)for(let t=0;t<=180;t+=.5){
    const pose=fish.pose(t,index,390,304,100,80);
    for(const n of [pose.x,pose.y,pose.angle,...pose.points.flatMap(p=>[p.x,p.y])])assert.ok(Number.isFinite(n));
    assert.equal(pose.points.length,81);
  }
});
test('HTML/CSS引用的本地文件存在',()=>{
  for(const filename of ['index.html','compare.html','style.css','palettes.css','calendar-ui.css','notebooks.css','compare.css']){
    const source=fs.readFileSync(path.join(root,filename),'utf8');
    const refs=[...source.matchAll(/(?:src|href)=["']([^"']+)["']|url\(["']?([^)'"\s]+)["']?\)/g)];
    for(const m of refs){const target=m[1]||m[2];if(/^(?:https?:|data:|#)/.test(target))continue;assert.ok(fs.existsSync(path.join(root,target.split(/[?#]/)[0])),`${filename}: ${target}`)}
  }
});
