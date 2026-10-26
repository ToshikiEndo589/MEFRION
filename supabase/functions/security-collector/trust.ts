import { createRemoteJWKSet, jwtVerify, type JWTVerifyGetKey } from 'npm:jose@6.2.13';
// One deployed project, production only. No caller-supplied issuer/JWKS URL.
export const expected = { owner:'toshiki-endos-projects',project:'mefrion',projectId:'prj_zzSYKWLDXUMWVv8TpuAVIuemDvqQ' };
const issuer='https://oidc.vercel.com/'+expected.owner;
const keys=createRemoteJWKSet(new URL(issuer+'/.well-known/jwks'),{timeoutDuration:2500,cacheMaxAge:600000,cooldownDuration:30000});
export async function verifySender(token:string, keySet:JWTVerifyGetKey=keys) {
  if(token.length>12000)throw Error('assertion_invalid');
  const {payload}=await jwtVerify(token,keySet,{issuer,audience:'https://vercel.com/'+expected.owner,algorithms:['RS256'],clockTolerance:5,maxTokenAge:'2h',requiredClaims:['iss','aud','sub','exp','iat','nbf','project_id','environment','owner','project']});
  if(payload.project_id!==expected.projectId||payload.environment!=='production'||payload.owner!==expected.owner||payload.project!==expected.project||payload.sub!==`owner:${expected.owner}:project:${expected.project}:environment:production`)throw Error('sender_not_allowed');
  return true;
}
