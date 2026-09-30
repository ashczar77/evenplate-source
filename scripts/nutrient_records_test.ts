import { matchRecord, profileFromRecord } from '../supabase/functions/_shared/nutrients.ts';
function check(value: unknown, label: string) { if(!value) throw new Error(label); console.log('PASS '+label); }
const row={fdcId:123,dataType:'SR Legacy',description:'Edamame, frozen, prepared',foodNutrients:[{nutrientId:1008,unitName:'KCAL',value:121},{nutrientId:1003,unitName:'G',value:12},{nutrientId:1079,unitName:'G',value:5},{nutrientId:1004,unitName:'G',value:5}]};
check(profileFromRecord('Edamame',row)?.fiberG === 5,'USDA identifiers and units map correctly');
check(profileFromRecord('Edamame',{...row,foodNutrients:row.foodNutrients.slice(0,2)}) === null,'missing fiber is not invented as zero');
check(profileFromRecord('Edamame',{...row,foodNutrients:row.foodNutrients.map(n=>({...n,unitName:'MG'}))})===null,'wrong units are refused');
check(matchRecord('Edamame',[{...row,description:'Corn dog'},row])?.fdcId===123,'unrelated first search hit is skipped');
check(matchRecord('Edamame',[{...row,dataType:'Branded'}])===null,'generic queries do not assume branded recipes');
check(matchRecord('Fried edamame',[row])===null,'preparation mismatches remain unrated');
console.log('6 nutrient record checks passed');
