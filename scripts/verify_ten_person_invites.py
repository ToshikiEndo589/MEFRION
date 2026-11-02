"""Two actual concurrent joins for the last seat, development fixtures only.

No customer IDs, stored invitation secrets, emails sent, or load generation.
The scoped database API executes each join in an independent transaction.
"""
import json
import threading
import urllib.error
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from uuid import uuid4
from configure_stock_rotation import query, lit


def claims(user):
    return ("select set_config('request.jwt.claim.sub',"+lit(user)+",true);"
            "select set_config('request.jwt.claims',"+lit(json.dumps({'sub': user, 'role': 'authenticated'}))+",true);")


def main():
    people=[str(uuid4()) for _ in range(12)]
    owner=people[0]
    pet=str(uuid4())
    checks=[]
    try:
        sql="begin;insert into auth.users(id,aud,role,email) values "+','.join(
            '('+lit(u)+",'authenticated','authenticated',"+lit(u+'@example.invalid')+')' for u in people)+';'
        sql+="insert into mefrion_private.pets(id,owner_id,name,species) values("+lit(pet)+','+lit(owner)+",'10-seat concurrency fixture','dog');"
        sql+=claims(owner)+"set local role authenticated;select public.mefrion_invite("+lit(pet)+") as invitation;commit;"
        inv=query('development',sql)[0]['invitation']
        accept="select public.mefrion_accept_invite("+lit(inv['token'])+",true);"
        for u in people[1:10]:
            query('development','begin;'+claims(u)+'set local role authenticated;'+accept+'commit;')
        barrier=threading.Barrier(2)

        def join(u):
            barrier.wait()
            try:
                query('development','begin;'+claims(u)+'set local role authenticated;'+accept+'commit;')
                return 'joined'
            except urllib.error.HTTPError as error:
                # Check the precise denial but never emit response bodies/tokens.
                body=error.read().decode()
                if 'invitation_full' in body:
                    return 'full'
                raise RuntimeError('Unexpected concurrent join response') from None

        with ThreadPoolExecutor(max_workers=2) as pool:
            results=list(pool.map(join,people[10:12]))
        assert sorted(results)==['full','joined'], results
        checks.append('two concurrent joins for last seat: exactly one succeeds')
        counts=query('development',"select used_count,state,(select count(*) from mefrion_private.invite_claims where invite_id=i.id) as claims,(select count(*) from mefrion_private.members where pet_id=i.pet_id and active) as members from mefrion_private.invites i where id="+lit(inv['id']))[0]
        assert counts=={'used_count':10,'state':'accepted','claims':10,'members':10},counts
        checks.append('exactly ten claims, ten members, closed link')
        # Repeated requests from an existing member are safe even at capacity.
        query('development','begin;'+claims(people[1])+'set local role authenticated;'+accept+accept+'commit;')
        after=query('development',"select used_count from mefrion_private.invites where id="+lit(inv['id']))[0]
        assert after['used_count']==10
        checks.append('retries at capacity do not consume additional places')
    finally:
        query('development',"begin;delete from mefrion_private.audit where pet_id="+lit(pet)+";delete from mefrion_private.pets where id="+lit(pet)+";delete from auth.users where id in ("+','.join(map(lit,people))+');commit;')
        remaining=query('development',"select count(*) as remaining from auth.users where id in ("+','.join(map(lit,people))+')')[0]['remaining']
        assert remaining==0
    result={'environment':'development','passed':True,'checks':checks,'fixtures_remaining':remaining}
    Path('docs/evidence/FAMILY-INVITE-TEN-CONCURRENCY-20261025.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps(result))


if __name__=='__main__':
    main()
