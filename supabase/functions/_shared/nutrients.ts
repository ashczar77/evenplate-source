import catalog from './nutrient_catalog.json' with { type: 'json' };

export type NutrientProfile = {
  name: string; fdcId: number; description: string;
  kcal: number; proteinG: number; fiberG: number; fatG: number;
  portionG: number; liquid: boolean;
};
const records = catalog as Record<string, NutrientProfile>;
const cache = new Map<string, { profile: NutrientProfile | null; expires: number }>();
const aliases: Record<string, string> = {
  egg: 'eggs', 'hard boiled egg': 'eggs', edamame: 'edamame',
  'edamame beans': 'edamame', 'side of edamame beans': 'edamame',
  sausage: 'sausage', sausages: 'sausage', 'grilled sausage': 'sausage',
  'grilled sausages': 'sausage', 'cooked sausage': 'sausage', 'cooked sausages': 'sausage',
  'french fries': 'french fries',
  'olive oil': 'olive oil', avocado: 'avocado', oats: 'oats', oatmeal: 'cooked oats',
};
const tokens = (text: string) => text.toLowerCase().replace(/[^a-z0-9 ]/g, ' ').split(/\s+/)
  .map((t) => t.length > 3 && t.endsWith('s') ? t.slice(0, -1) : t)
  .filter((t) => t && !['with', 'without', 'and', 'of', 'a', 'the', 'side', 'salt'].includes(t));

export function profileFromRecord(name: string, row: any): NutrientProfile | null {
  const nutrients = Array.isArray(row?.foodNutrients) ? row.foodNutrients : [];
  function value(id: number, unit: string): number | null {
    const n = nutrients.find((n: any) => (n.nutrientId ?? n.nutrient?.id) === id && (n.unitName ?? n.nutrient?.unitName)?.toLowerCase() === unit);
    const v = n?.value ?? n?.amount;
    return typeof v === 'number' && Number.isFinite(v) && v >= 0 ? v : null;
  }
  const kcal = value(1008, 'kcal') ?? value(2047, 'kcal') ?? value(2048, 'kcal');
  const proteinG = value(1003, 'g'), fiberG = value(1079, 'g'), fatG = value(1004, 'g');
  if (kcal === null || proteinG === null || fiberG === null || fatG === null || kcal > 1000 || [proteinG, fiberG, fatG].some(v => v > 100)) return null;
  if (!Number.isInteger(row.fdcId) || row.fdcId <= 0 || typeof row.description !== 'string') return null;
  return {name, fdcId:row.fdcId, description:row.description, kcal, proteinG, fiberG, fatG, portionG:100,
    liquid: /\b(juice|milk|beverage|drink|coffee|tea|cola|soda|beer|wine|water)\b/i.test(row.description + ' ' + name)};
}

export function matchRecord(name: string, foods: any[]): NutrientProfile | null {
  const wanted = tokens(name);
  if (!wanted.length) return null;
  const ranked = [...foods].sort((a, b) => {
    const priority = (row: any) => {
      const text = String(row?.description ?? '');
      const generic = /\bNFS\b|not specified/i.test(text);
      return (row?.dataType === 'Survey (FNDDS)' ? 0 : 100) - (generic ? 50 : 0) + tokens(text).length;
    };
    return priority(a) - priority(b);
  });
  for (const row of ranked) {
    if (!['SR Legacy', 'Survey (FNDDS)'].includes(row?.dataType)) continue;
    const description = String(row.description ?? '');
    if (/APPLEBEE|DENNY|MCDONALD|WENDY|BURGER KING|CARRABBA|T\.G\.I|restaurant|fast food/i.test(description)) continue;
    const actual = new Set(tokens(description));
    const extraIngredients = ['cheese', 'chicken', 'beef', 'pork', 'shrimp', 'tuna', 'crab', 'egg', 'chili'];
    if (description.toLowerCase().includes(' with ') && extraIngredients.some(t => actual.has(t) && !wanted.includes(t))) continue;
    // Every identifying token must match. Never substitute a merely popular result.
    if (!wanted.every(t => actual.has(t))) continue;
    const p = profileFromRecord(name, row);
    if (p) return p;
  }
  return null;
}

export async function nutrientProfiles(names: string[], apiKey: string, timeoutMs = 8000): Promise<NutrientProfile[]> {
  if (!apiKey) throw new Error('USDA_UNAVAILABLE');
  const signal = AbortSignal.timeout(Math.max(1, Math.min(8000, timeoutMs)));
  const out: NutrientProfile[] = [];
  let next = 0;
  async function worker() {
    while (next < names.length) {
      const name = names[next++];
      const key = name.trim().toLowerCase();
      const local = records[aliases[key] ?? key];
      if (local) { out.push({...local,name}); continue; }
      const hit = cache.get(key);
      if (hit && hit.expires > Date.now()) { if(hit.profile) out.push({...hit.profile,name}); continue; }
      const response = await fetch('https://api.nal.usda.gov/fdc/v1/foods/search?api_key=' + encodeURIComponent(apiKey), {
        method:'POST', signal, headers:{'Content-Type':'application/json'},
        body:JSON.stringify({query:name, dataType:['SR Legacy','Survey (FNDDS)'],pageSize:15}),
      });
      if (!response.ok) throw new Error('USDA_UNAVAILABLE');
      const data = await response.json();
      if (!Array.isArray(data.foods)) throw new Error('USDA_UNAVAILABLE');
      const profile = matchRecord(name, data.foods);
      if(cache.size >= 500) cache.delete(cache.keys().next().value!);
      cache.set(key,{profile,expires:Date.now()+86400000});
      if(profile) out.push(profile);
    }
  }
  try { await Promise.all(Array.from({length:Math.min(4,names.length)},worker)); }
  catch { throw new Error('USDA_UNAVAILABLE'); }
  return names.flatMap(name => out.filter(p => p.name === name));
}
