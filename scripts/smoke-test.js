const fs=require('fs');const path=require('path');
const root=path.join(__dirname,'..');
const must=['netlify/functions/api.js','server/app.js','server/routes/public.js','server/routes/admin.js','server/google.js','supabase/schema.sql','supabase/migrations/002_hardening_calendar_drive_selection.sql','supabase/migrations/003_final_concurrency_oauth_hardening.sql','public/index.html','public/admin/index.html','public/select.html','netlify.toml'];
for(const f of must)if(!fs.existsSync(path.join(root,f)))throw new Error('Missing '+f);
const all=[];function walk(d){for(const n of fs.readdirSync(d,{withFileTypes:true})){if(n.name==='node_modules'||n.name==='.git')continue;const p=path.join(d,n.name);n.isDirectory()?walk(p):all.push(p)}}walk(root);
for(const f of all){if(f===__filename)continue;if(/\.(js|html|sql|toml|env\.example)$/.test(f)){const s=fs.readFileSync(f,'utf8');if(['19:00','20:00','kaia-'+'dev-secret-change-me'].some(x=>s.includes(x)))throw new Error('Obsolete value in '+path.relative(root,f));}}
const api=fs.readFileSync(path.join(root,'netlify/functions/api.js'),'utf8');
if(!api.includes("req.url.startsWith('/api')") || !api.includes("req.url = `/api"))throw new Error('Netlify API prefix normalization missing');
const schema=fs.readFileSync(path.join(root,'supabase/schema.sql'),'utf8');for(const x of ['booking_idempotency','booking_daily_sequences','calendar_sync','photo_selection_sessions','photo_metadata','templates','claim_calendar_sync','processing_until','google_oauth_states'])if(!schema.includes(x))throw new Error('Schema missing '+x);
console.log('SMOKE PASS: structure, obsolete-value scan, and required schema markers verified.');
