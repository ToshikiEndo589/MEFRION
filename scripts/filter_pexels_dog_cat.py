"""Build a conservative dog/cat-only library; preserve the original separately."""
import argparse
import csv
import json
from pathlib import Path
import re
import shutil

DOG = re.compile(r'\b(?:dogs?|pupp(?:y|ies)|canine|retrievers?|labradors?|shiba|corgis?|poodles?|husk(?:y|ies)|dachshunds?|beagles?|chihuahuas?|collies?|pomeranians?|bulldogs?|shepherds?|rottweilers?|terriers?|dalmatians?|schnauzers?|samoyeds?|pugs?|malteses?|dobermans?|whippets?|greyhounds?)\b', re.I)
CAT = re.compile(r'\b(?:cats?|kittens?|feline|tabb(?:y|ies)|siamese|ragdolls?|maine coon|british shorthair|persian cat|bengal cat|sphynx)\b', re.I)
OTHER = re.compile(r'\b(?:birds?|parrots?|rabbits?|bunnies|hamsters?|guinea pigs?|pigs?|horses?|cows?|cattle|sheep|goats?|tigers?|lions?|leopards?|cheetahs?|lynx|fox(?:es)?|wolves|wolf|coyotes?|pandas?|bears?|ferrets?|turtles?|tortoises?|snakes?|lizards?|chickens?|ducks?|geese|eagles?|owls?|monkeys?|deer|squirrels?|mice|mouse|rats?)\b', re.I)

def eligible(row):
    if row.get('species_hint') not in ('dog','cat'):
        return False, 'non_dog_cat_search_category'
    description = row.get('alt', '')
    if OTHER.search(description):
        return False, 'other_animal_text_hint'
    positive = DOG if row['species_hint'] == 'dog' else CAT
    if not positive.search(description):
        return False, 'species_not_confirmed_by_description'
    return True, 'dog_cat_query_and_description'

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--input',type=Path,default=Path('.local/pexels-pets'))
    parser.add_argument('--backup',type=Path,default=Path('.local/pexels-before-dog-cat-filter'))
    args = parser.parse_args()
    root, backup = args.input.resolve(), args.backup.resolve()
    if backup.exists():
        raise SystemExit('Backup already exists; refusing to overwrite')
    rows = [json.loads(line) for line in (root/'manifest.jsonl').read_text().splitlines()]
    selected, excluded = [], []
    for row in rows:
        accepted, reason = eligible(row)
        if accepted:
            row['intake_filter'] = reason
            # This is a description filter, not image recognition or ground truth.
            row['species_verified'] = False
            selected.append(row)
        else:
            excluded.append({'asset_id':row['asset_id'],'reason':reason,'previous_species_hint':row['species_hint']})
    if not selected:
        raise SystemExit('No candidates; input unchanged')
    root.rename(backup)
    for folder in ('images','thumbnails','records'):
        (root/folder).mkdir(parents=True,exist_ok=True)
    shutil.copy2(backup/'permission.json',root/'permission.json')
    for row in selected:
        for key in ('image_path','thumbnail_path'):
            relative = Path(row[key])
            if relative.is_absolute() or '..' in relative.parts:
                raise ValueError('Unsafe local asset path')
            shutil.copy2(backup/relative,root/relative)
        (root/'records'/f'{row["pexels_id"]}.json').write_text(json.dumps(row,ensure_ascii=False,indent=2))
    (root/'manifest.jsonl').write_text(''.join(json.dumps(row,ensure_ascii=False)+'\n' for row in selected))
    with (root/'manifest.csv').open('w',newline='') as handle:
        fields = ['asset_id','species_hint','image_path','thumbnail_path','width','height','photographer','source_page','credit','review_status','sha256']
        writer=csv.DictWriter(handle,fieldnames=fields,extrasaction='ignore');writer.writeheader();writer.writerows(selected)
    for name in ('seed-01-06-photo-drafts.json',):
        if (backup/name).exists():
            drafts=json.loads((backup/name).read_text())
            keep={r['asset_id'] for r in selected}
            assert all(d['asset']['asset_id'] in keep for d in drafts)
            shutil.copy2(backup/name,root/name)
    counts={species:sum(row['species_hint']==species for row in selected) for species in ('dog','cat')}
    report={'original_manifest_count':len(rows),'dog_cat_candidates':len(selected),'excluded_count':len(excluded),
            'species_query_hints':counts,'classification_method':'query category plus conservative description filter',
            'all_visually_verified':False,'api_requests':0,'original_backup':str(backup)}
    (root/'filter-report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2))
    (backup/'excluded-by-dog-cat-filter.json').write_text(json.dumps(excluded,ensure_ascii=False,indent=2))
    summary={'collected_unique_images':len(selected),'species_query_hints':counts,'failures':[],
             'all_pending_visual_review':True,'published':False,'filter_report':'filter-report.json','api_requests_this_change':0}
    (root/'summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2))
    old_zip=root.parent/'MEFRION-Pexels-6311.zip'
    if old_zip.exists():
        old_zip.rename(backup/'original-6311.zip')
    print(json.dumps(report,ensure_ascii=False))

if __name__=='__main__':
    main()
