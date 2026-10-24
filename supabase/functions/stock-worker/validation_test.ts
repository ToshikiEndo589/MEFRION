import { safeTask, type Task } from "./validation.ts";
const id="e80d14bf-6270-43a7-bce4-72090ea4a88e";
const base:Task={id,lease:id,reference_path:"pexels-123.jpg",original_path:`${id}/${id}.jpg`,public_path:`${id}.jpg`};
Deno.test("reserved catalogue paths accepted",()=>{if(!safeTask(base)) throw Error("valid rejected");});
Deno.test("reference source cannot be URL, private path, or traversal",()=>{
 for(const reference_path of ["https://example.com/p.jpg","../secret.jpg","pet/private.jpg","pexels-1.mp4","pexels-1.jpg\u0000"])
  if(safeTask({...base,reference_path}))throw Error("unsafe accepted");
});
Deno.test("destination cannot escape the reserved JPEG paths",()=>{
 for(const key of ["original_path","public_path"] as const)
  for(const value of ["../secret.jpg","/absolute.jpg",`${id}.mp4`,`${id}/../${id}.jpg`])
   if(safeTask({...base,[key]:value}))throw Error("unsafe accepted");
});
Deno.test("malformed task identity and lease rejected",()=>{
 for(const key of ["id","lease"] as const)
  for(const value of ["",id+"\n","../../", "not-a-uuid"])
   if(safeTask({...base,[key]:value}))throw Error("unsafe accepted");
});
