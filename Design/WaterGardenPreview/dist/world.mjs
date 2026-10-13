export const WORLD = { width: 1536, height: 1024 };
export const clamp = (v, lo, hi) => Math.min(hi, Math.max(lo, v));
export const ease = t => 1 - Math.pow(1 - clamp(t, 0, 1), 3);

// Coordinates belong to midground.png, never to the viewport or a separate flower sprite.
export const slots = [
  [248,535],[307,538],[344,515],[386,529],[445,550],[483,555],
  [521,618],[508,643],[551,646],[581,673],[604,713],[640,761],
  [656,683],[729,679],[762,710],[806,624],[833,667],[868,662],
  [894,695],[941,624],[958,666],[990,681],[1025,682],[1079,719],
].map(([x,y], i) => ({ id: `water-${String(i+1).padStart(2,'0')}`, x, y }));

// Persist this manifest when adding real memory IDs. Never re-sort old assignments.
// App/server adapter supplies records; no cookie, production URL or user data lives here.
export function allocateMemories(records, previous = {}) {
  const assignments = {}; const used = new Set(); const overflow = [];
  const ids = new Set(records.map(r => String(r.id)));
  for (const [id, slotID] of Object.entries(previous)) {
    if (ids.has(id) && slots.some(s => s.id === slotID) && !used.has(slotID)) {
      assignments[id] = slotID; used.add(slotID);
    }
  }
  for (const r of [...records].sort((a,b) => String(a.id).localeCompare(String(b.id)))) {
    const id = String(r.id); if (assignments[id] || overflow.includes(id)) continue;
    const slot = slots.find(s => !used.has(s.id));
    if (slot) { assignments[id] = slot.id; used.add(slot.id); } else overflow.push(id);
  }
  return { assignments, overflow, nextLocation: overflow.length ? 'water-deeper' : null };
}

export function transform(view, camera, parallax = 1) {
  const scale = Math.max(view.w / WORLD.width, view.h / WORLD.height) * 1.32 * camera.zoom;
  const cx = WORLD.width / 2 + (camera.x - WORLD.width / 2) * parallax;
  const cy = WORLD.height / 2 + (camera.y - WORLD.height / 2) * parallax;
  const x = clamp(view.w / 2 - cx * scale, view.w - WORLD.width * scale, 0);
  const y = clamp(view.h / 2 - cy * scale, view.h - WORLD.height * scale, 0);
  return { x, y, scale };
}
export const project = (p,t) => ({x:p.x*t.scale+t.x, y:p.y*t.scale+t.y});
export const unproject = (p,t) => ({x:(p.x-t.x)/t.scale, y:(p.y-t.y)/t.scale});
export function nearestSlot(point, visible, t, radius=24) {
  return visible.map(s => ({s,d:Math.hypot(project(s,t).x-point.x,project(s,t).y-point.y)}))
    .filter(x=>x.d<=radius).sort((a,b)=>a.d-b.d)[0]?.s ?? null;
}
