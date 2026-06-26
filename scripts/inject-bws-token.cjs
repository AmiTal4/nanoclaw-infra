// Injects the BWS access token (from $BWS_TOKEN) into NanoClaw's SQLite DB.
//
// Why the DB and not container.json: NanoClaw v2 stores container config in
// data/v2.db (container_configs.mcp_servers, a JSON blob) and REGENERATES
// groups/<group>/container.json from that DB at every spawn
// (materializeContainerJson). Editing container.json directly is silently
// overwritten on the next spawn — the DB is the source of truth.
//
// Updates every container_configs row whose mcp_servers JSON has a server with
// env.BWS_ACCESS_TOKEN. The DB is in WAL mode, so this is safe to run while
// NanoClaw is live; the next browser spawn reads the new value (no restart).
//
// Deployed to /home/ubuntu/scripts/ by the /setup-bitwarden skill and invoked
// by fetch-bws-token.sh. NANOCLAW_DIR can override the install path.
const NANOCLAW_DIR = process.env.NANOCLAW_DIR || '/home/ubuntu/nanoclaw-v2';
const Database = require(NANOCLAW_DIR + '/node_modules/better-sqlite3');

const token = process.env.BWS_TOKEN;
if (!token) { console.error('ERROR: BWS_TOKEN env not set'); process.exit(1); }

const db = new Database(NANOCLAW_DIR + '/data/v2.db');
const rows = db.prepare('SELECT agent_group_id, mcp_servers FROM container_configs').all();
const upd = db.prepare('UPDATE container_configs SET mcp_servers = ?, updated_at = ? WHERE agent_group_id = ?');

let updated = 0;
for (const r of rows) {
  let j;
  try { j = JSON.parse(r.mcp_servers); } catch { continue; }
  let changed = false;
  for (const k of Object.keys(j || {})) {
    const env = j[k] && j[k].env;
    if (env && Object.prototype.hasOwnProperty.call(env, 'BWS_ACCESS_TOKEN')) {
      if (env.BWS_ACCESS_TOKEN !== token) { env.BWS_ACCESS_TOKEN = token; changed = true; }
    }
  }
  if (changed) {
    upd.run(JSON.stringify(j), new Date().toISOString(), r.agent_group_id);
    updated++;
    console.log('updated group', r.agent_group_id);
  }
}
console.log('Done. Rows updated:', updated, '| token prefix:', token.slice(0, 12) + '...');
db.close();
