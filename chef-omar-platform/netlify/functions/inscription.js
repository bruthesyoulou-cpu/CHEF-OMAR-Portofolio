// Reçoit le reçu de paiement (multipart), le range dans le cloud privé "recus" de Supabase, l'enregistre
// dans la table "inscriptions" et, si configuré, le transmet au bot Telegram du chef.
// Variables Netlify : SUPABASE_URL, SUPABASE_SERVICE_KEY (obligatoires) · TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID (facultatives)
const J = (c, o) => ({ statusCode: c, headers: { 'content-type': 'application/json' }, body: JSON.stringify(o) });

function parse(buf, boundary) {
  const sep = Buffer.from('--' + boundary), out = {};
  let i = buf.indexOf(sep);
  while (i >= 0) {
    const j = buf.indexOf(sep, i + sep.length);
    if (j < 0) break;
    const p = buf.slice(i + sep.length + 2, j - 2), h = p.indexOf('\r\n\r\n');
    if (h > 0) {
      const head = p.slice(0, h).toString(), data = p.slice(h + 4), n = /name="([^"]+)"/.exec(head);
      if (n) out[n[1]] = /filename=/.test(head) ? { file: data } : data.toString();
    }
    i = j;
  }
  return out;
}
const clean = (v, n) => String(v || '').replace(/[\u0000-\u001f]/g, ' ').trim().slice(0, n);

exports.handler = async (event) => {
  if (event.httpMethod !== 'POST') return J(405, { ok: false });
  const m = /boundary=(.+)$/.exec(event.headers['content-type'] || event.headers['Content-Type'] || '');
  if (!m) return J(400, { ok: false });
  const body = Buffer.from(event.body || '', event.isBase64Encoded ? 'base64' : 'utf8');
  if (body.length > 5.5 * 1024 * 1024) return J(413, { ok: false });
  const f = parse(body, m[1].replace(/^"|"$/g, ''));
  const rec = {
    contact: clean(f.contact, 120), formation: clean(f.formation, 160), fid: clean(f.fid, 60),
    methode: clean(f.methode, 20), ref: clean(f.ref, 40), montant: clean(f.montant, 40), device: clean(f.device, 80) || null,
  };
  rec.montant_num = Number(rec.montant.replace(/[^\d]/g, '')) || 0;
  if (!rec.contact || !f.recu || !f.recu.file || f.recu.file.length < 200) return J(400, { ok: false });

  const { TELEGRAM_BOT_TOKEN: T, TELEGRAM_CHAT_ID: C, SUPABASE_URL: SU, SUPABASE_SERVICE_KEY: SK } = process.env;
  let sent = false, saved = false;
  if (SU && SK) {
    const auth = { apikey: SK, Authorization: 'Bearer ' + SK };
    try {
      const path = `${Date.now()}-${rec.ref.replace(/[^\w-]/g, '') || 'recu'}.jpg`;
      const up = await fetch(`${SU}/storage/v1/object/recus/${path}`, { method: 'POST', headers: { ...auth, 'Content-Type': 'image/jpeg' }, body: f.recu.file });
      if (up.ok) rec.recu_path = path;
      const r = await fetch(`${SU}/rest/v1/inscriptions`, { method: 'POST', headers: { ...auth, 'Content-Type': 'application/json', Prefer: 'return=minimal' }, body: JSON.stringify(rec) });
      saved = r.ok;
    } catch (e) { saved = false; }
  }
  if (T && C) {
    try {
      const fd = new FormData();
      fd.append('chat_id', C);
      fd.append('caption', `Nouveau paiement\nRéf : ${rec.ref}\n${rec.formation} (${rec.fid || '-'})\nMontant : ${rec.montant || '-'}\nMoyen : ${rec.methode}\nContact : ${rec.contact}\nÀ valider dans la console.`.slice(0, 1000));
      fd.append('photo', new Blob([f.recu.file], { type: 'image/jpeg' }), 'recu.jpg');
      const r = await fetch(`https://api.telegram.org/bot${T}/sendPhoto`, { method: 'POST', body: fd });
      sent = r.ok;
    } catch (e) { sent = false; }
  }
  return J(sent || saved ? 200 : 502, { ok: sent || saved });
};
