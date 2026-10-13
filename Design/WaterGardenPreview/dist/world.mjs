export const WORLD = { width: 1536, height: 1024 };
export const SOURCE = { width: 6144, height: 4096 };
export const clamp = (v, lo, hi) => Math.min(hi, Math.max(lo, v));
export const ease = t => 1 - Math.pow(1 - clamp(t, 0, 1), 3);

// Calibrated on the restored 6144×4096 midground. Camera units stay independent of texture resolution.
export const imageSlots = [
  [1004,2140],[1224,2144],[1376,2060],[1544,2116],[1780,2200],[1932,2220],
  [2084,2472],[2032,2572],[2204,2584],[2324,2692],[2416,2852],[2560,3044],
  [2624,2732],[2916,2716],[3048,2840],[3224,2496],[3332,2668],[3472,2648],
  [3576,2780],[3764,2496],[3832,2664],[3960,2724],[4100,2728],[4316,2876],
];
export const slots = imageSlots.map(([x,y], i) => ({
  id: `water-${String(i+1).padStart(2,'0')}`,
  x: x / SOURCE.width * WORLD.width, y: y / SOURCE.height * WORLD.height,
}));

export const renderPixelRatio = value => clamp(Number(value) || 1, 1, 3);
export function zoomLimit(view) {
  if (view.preview) return 1;
  const base = Math.max(view.w / WORLD.width, view.h / WORLD.height) * 1.32;
  return Math.min(1.65, (view.textureDensity || 4) / (base * (view.dpr || 1)));
}
export function samplingReport(view, camera) {
  const t = transform(view, camera);
  return { physicalPixelsPerSourcePixel:t.scale * (view.dpr || 1) / (view.textureDensity || 4),
    maxZoom:zoomLimit(view), scale:t.scale };
}

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
  const requested = Math.max(view.w / WORLD.width, view.h / WORLD.height) * 1.32 * camera.zoom;
  // A preview is explicitly temporary. Once HD is ready no texture pixel is enlarged.
  const scale = view.preview ? requested : Math.min(requested, (view.textureDensity || 4) / (view.dpr || 1));
  const cx = WORLD.width / 2 + (camera.x - WORLD.width / 2) * parallax;
  const cy = WORLD.height / 2 + (camera.y - WORLD.height / 2) * parallax;
  const x = WORLD.width*scale < view.w ? (view.w-WORLD.width*scale)/2 : clamp(view.w / 2 - cx * scale, view.w - WORLD.width * scale, 0);
  const y = WORLD.height*scale < view.h ? (view.h-WORLD.height*scale)/2 : clamp(view.h / 2 - cy * scale, view.h - WORLD.height * scale, 0);
  return { x, y, scale };
}
export const project = (p,t) => ({x:p.x*t.scale+t.x, y:p.y*t.scale+t.y});
export const unproject = (p,t) => ({x:(p.x-t.x)/t.scale, y:(p.y-t.y)/t.scale});
export function nearestSlot(point, visible, t, radius=24) {
  return visible.map(s => ({s,d:Math.hypot(project(s,t).x-point.x,project(s,t).y-point.y)}))
    .filter(x=>x.d<=radius).sort((a,b)=>a.d-b.d)[0]?.s ?? null;
}
