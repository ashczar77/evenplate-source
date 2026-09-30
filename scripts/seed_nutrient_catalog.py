"""Fetch reviewed USDA records. Keep the server key out of generated assets."""
import json
from pathlib import Path
from urllib.request import Request, urlopen

IDS = {'Eggs':173424,'Greek yogurt':2705424,'Chicken':171477,'Salmon':175168,'Tofu':172475,'Beans':173735,'Side salad':2709822,'Broccoli':169967,'Oats':173904,'Lentils':172421,'Berries':171711,'Avocado':171705,'Olive oil':171413,'Walnuts':170187,'Almonds':170567,'Tahini':170189,'Cucumber':168409,'Cherry tomatoes':170457,'Greens':168462,'Apple':168202,'Slaw':169975,'Orange juice':2709186,'Sloppy joes':2706378,'Strawberries':167762,'Banana':173944,'Orange':169097,'Rice':168878,'Pasta':169737,'Bread':172688,'Milk':171267,'Edamame':168411,'Sausage':2706190,'French fries':2709456}

def main():
    config = {}
    for line in Path('supabase/.env.functions').read_text().splitlines():
        if '=' in line and not line.lstrip().startswith('#'):
            name, value = line.split('=', 1)
            config[name.strip()] = value.strip().strip('\"\'')
    key = config['USDA_API_KEY']
    req = Request('https://api.nal.usda.gov/fdc/v1/foods?api_key=' + key, data=json.dumps({'fdcIds':list(IDS.values())}).encode(), headers={'Content-Type':'application/json'})
    with urlopen(req, timeout=30) as response:
        records = {row['fdcId']:row for row in json.load(response)}
    profiles = {}
    for name, fdc_id in IDS.items():
        row = records[fdc_id]
        nutrients = {n['nutrient']['id']:n for n in row['foodNutrients']}
        def value(ids, unit):
            for nutrient_id in ids:
                n = nutrients.get(nutrient_id)
                if n and n['nutrient']['unitName'].lower() == unit:
                    result = n.get('amount')
                    if isinstance(result, (int, float)) and result >= 0:
                        return result
            raise ValueError(f'Missing nutrient in {name}')
        profiles[name.lower()] = {'name':name,'fdcId':fdc_id,'description':row['description'],'kcal':value([1008,2047,2048],'kcal'),'proteinG':value([1003],'g'),'fiberG':value([1079],'g'),'fatG':value([1004],'g'),'portionG':100,'liquid':name in ['Orange juice','Milk']}
        print(f'{name}: FDC {fdc_id}, {row["description"]}')
    encoded = json.dumps(profiles, indent=2, ensure_ascii=True)+'\n'
    Path('assets/pantry/nutrient_profiles.json').write_text(encoded)
    Path('supabase/functions/_shared/nutrient_catalog.json').write_text(encoded)

if __name__ == '__main__':
    main()
