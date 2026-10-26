import {createLocalJWKSet,exportJWK,generateKeyPair,SignJWT} from 'npm:jose@6.2.13';
import {expected,verifySender} from '../trust.ts';
const {privateKey,publicKey}=await generateKeyPair('RS256');
const key=await exportJWK(publicKey);key.kid='test';key.alg='RS256';
const keys=createLocalJWKSet({keys:[key]});
const issuer='https://oidc.vercel.com/'+expected.owner;
const base={owner:expected.owner,project:expected.project,project_id:expected.projectId,environment:'production'};
async function sign(change:Record<string,unknown>={}){return new SignJWT({...base,...change}).setProtectedHeader({alg:'RS256',kid:'test'}).setIssuer(issuer).setAudience('https://vercel.com/'+expected.owner).setSubject(`owner:${expected.owner}:project:${expected.project}:environment:production`).setIssuedAt().setNotBefore('0s').setExpirationTime('2h').sign(privateKey);}
Deno.test('valid signed production sender accepted',async()=>{if(!await verifySender(await sign(),keys))throw Error('rejected');});
for(const [name,change] of Object.entries({project:{project_id:'prj_other'},preview:{environment:'preview'},owner:{owner:'other'},slug:{project:'different'}}))Deno.test('reject different '+name,async()=>{let denied=false;try{await verifySender(await sign(change),keys);}catch{denied=true;}if(!denied)throw Error('accepted');});
Deno.test('reject forged/unsigned token',async()=>{let denied=false;try{await verifySender('eyJhbGciOiJub25lIn0.e30.',keys);}catch{denied=true;}if(!denied)throw Error('accepted');});
Deno.test('reject expired assertion',async()=>{const token=await new SignJWT(base).setProtectedHeader({alg:'RS256',kid:'test'}).setIssuer(issuer).setAudience('https://vercel.com/'+expected.owner).setSubject(`owner:${expected.owner}:project:${expected.project}:environment:production`).setIssuedAt(1).setNotBefore(1).setExpirationTime(2).sign(privateKey);let denied=false;try{await verifySender(token,keys);}catch{denied=true;}if(!denied)throw Error('accepted');});
