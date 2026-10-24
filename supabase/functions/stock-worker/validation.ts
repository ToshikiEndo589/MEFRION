export type Task = { id: string; lease: string; reference_path: string; original_path: string; public_path: string };
const uuid = "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}";
export function safeTask(t: Task): boolean {
  return new RegExp(`^${uuid}$`).test(t.id) && new RegExp(`^${uuid}$`).test(t.lease) &&
    /^pexels-[0-9]+\.jpg$/.test(t.reference_path) &&
    new RegExp(`^${uuid}/${uuid}\\.jpg$`).test(t.original_path) && new RegExp(`^${uuid}\\.jpg$`).test(t.public_path);
}
