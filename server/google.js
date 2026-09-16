const crypto = require('crypto');
let google;
function googleLib(){ if(!google) google = require('googleapis').google; return google; }
const supabase = require('./supabase');

function required(name) {
  const value = process.env[name];
  if (!value) throw new Error(`MISSING_${name}`);
  return value;
}

function oauthClient() {
  return new (googleLib().auth.OAuth2)(
    required('GOOGLE_CLIENT_ID'),
    required('GOOGLE_CLIENT_SECRET'),
    required('GOOGLE_REDIRECT_URI')
  );
}

function encrypt(text) {
  const keyRaw = process.env.GOOGLE_TOKEN_ENCRYPTION_KEY;
  if (!keyRaw) throw new Error('MISSING_GOOGLE_TOKEN_ENCRYPTION_KEY');
  const key = crypto.createHash('sha256').update(keyRaw).digest();
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', key, iv);
  const encrypted = Buffer.concat([cipher.update(text, 'utf8'), cipher.final()]);
  return [iv.toString('base64url'), cipher.getAuthTag().toString('base64url'), encrypted.toString('base64url')].join('.');
}

function decrypt(value) {
  const keyRaw = process.env.GOOGLE_TOKEN_ENCRYPTION_KEY;
  if (!keyRaw) throw new Error('MISSING_GOOGLE_TOKEN_ENCRYPTION_KEY');
  const [ivS, tagS, dataS] = value.split('.');
  const key = crypto.createHash('sha256').update(keyRaw).digest();
  const decipher = crypto.createDecipheriv('aes-256-gcm', key, Buffer.from(ivS, 'base64url'));
  decipher.setAuthTag(Buffer.from(tagS, 'base64url'));
  return Buffer.concat([decipher.update(Buffer.from(dataS, 'base64url')), decipher.final()]).toString('utf8');
}

async function getSetting(key) {
  const { data } = await supabase.from('settings').select('value').eq('key', key).maybeSingle();
  return data?.value || null;
}

async function setSetting(key, value) {
  const { error } = await supabase.from('settings').upsert({ key, value }, { onConflict: 'key' });
  if (error) throw error;
}

async function getAuthUrl() {
  const client = oauthClient();
  const rawState = crypto.randomBytes(32).toString('base64url');
  const stateHash = crypto.createHash('sha256').update(rawState).digest('hex');
  await supabase.from('google_oauth_states').delete().lt('expires_at', new Date().toISOString());
  const { error } = await supabase.from('google_oauth_states').insert({ state_hash: stateHash, expires_at: new Date(Date.now() + 10 * 60 * 1000).toISOString() });
  if (error) throw error;
  return client.generateAuthUrl({ access_type: 'offline', prompt: 'consent', state: rawState, scope: [
    'https://www.googleapis.com/auth/calendar',
    'https://www.googleapis.com/auth/drive.readonly'
  ] });
}

async function saveOAuthCode(code, state) {
  if (!state) throw new Error('OAUTH_STATE_MISSING');
  const stateHash = crypto.createHash('sha256').update(String(state)).digest('hex');
  const { data: stateRow } = await supabase.from('google_oauth_states').select('state_hash,expires_at').eq('state_hash', stateHash).maybeSingle();
  if (!stateRow || new Date(stateRow.expires_at) < new Date()) throw new Error('OAUTH_STATE_INVALID');
  await supabase.from('google_oauth_states').delete().eq('state_hash', stateHash);
  const client = oauthClient();
  const { tokens } = await client.getToken(code);
  if (!tokens.refresh_token) throw new Error('NO_REFRESH_TOKEN');
  await setSetting('google_refresh_token_encrypted', encrypt(tokens.refresh_token));
  if (tokens.scope) await setSetting('google_scope', tokens.scope);
  return tokens;
}

async function getRefreshToken() {
  if (process.env.GOOGLE_REFRESH_TOKEN) return process.env.GOOGLE_REFRESH_TOKEN;
  const encrypted = await getSetting('google_refresh_token_encrypted');
  return encrypted ? decrypt(encrypted) : null;
}

async function authorizedClient() {
  const refreshToken = await getRefreshToken();
  if (!refreshToken) throw new Error('GOOGLE_NOT_CONNECTED');
  const client = oauthClient();
  client.setCredentials({ refresh_token: refreshToken });
  return client;
}

async function syncBookingToCalendar(booking) {
  const refreshToken = await getRefreshToken();
  if (!refreshToken) return { status: 'pending', reason: 'GOOGLE_NOT_CONNECTED' };
  const calendarId = process.env.GOOGLE_CALENDAR_ID || await getSetting('google_calendar_id');
  if (!calendarId) return { status: 'pending', reason: 'GOOGLE_CALENDAR_ID_MISSING' };
  if (!booking.start_time || !booking.end_time) return { status: 'pending', reason: 'DURATION_UNSPECIFIED' };

  // Claim the sync atomically. Only the claimant may call Google createEvent.
  const { data: claim, error: claimError } = await supabase.rpc('claim_calendar_sync', { p_booking_id: booking.id });
  if (claimError) throw claimError;
  if (!claim) return { status: 'already_claimed' };
  if (claim.status === 'synced' && claim.google_event_id) return claim;

  try {
    const auth = await authorizedClient();
    const calendar = googleLib().calendar({ version: 'v3', auth });
    const deterministicEventId = crypto.createHash('sha256').update(`kaia:${booking.id}`).digest('hex');
    let event;
    try {
      event = await calendar.events.insert({
        calendarId,
      requestBody: {
        id: deterministicEventId,
        summary: `[KAIA] ${booking.package_name_snapshot} — ${booking.customer_name}`,
        description: [
          `Booking Code: ${booking.booking_code}`,
          `Customer: ${booking.customer_name}`,
          `WhatsApp: ${booking.whatsapp}`,
          `Package: ${booking.package_name_snapshot}`,
          `People: ${booking.people_count}`,
          `Payment: ${booking.payment_status}`
        ].join('\n'),
        start: { dateTime: `${booking.booking_date}T${booking.start_time}:00+07:00`, timeZone: 'Asia/Jakarta' },
        end: { dateTime: `${booking.booking_date}T${booking.end_time}:00+07:00`, timeZone: 'Asia/Jakarta' },
        extendedProperties: { private: { kaia_booking_id: String(booking.id), booking_code: booking.booking_code } }
      }
      });
    } catch (insertError) {
      if (insertError?.code === 409 || insertError?.response?.status === 409) {
        event = await calendar.events.get({ calendarId, eventId: deterministicEventId });
      } else { throw insertError; }
    }
    const { error } = await supabase.from('calendar_sync').update({
      status: 'synced', google_event_id: event.data.id, last_error: null, synced_at: new Date().toISOString(), updated_at: new Date().toISOString()
    }).eq('booking_id', booking.id);
    if (error) throw error;
    await supabase.from('bookings').update({calendar_sync_status:'synced',updated_at:new Date().toISOString()}).eq('id',booking.id);
    return { status: 'synced', googleEventId: event.data.id };
  } catch (error) {
    await supabase.from('calendar_sync').update({ status: 'failed', last_error: String(error.message || error).slice(0, 1000), updated_at: new Date().toISOString() }).eq('booking_id', booking.id);
    await supabase.from('bookings').update({calendar_sync_status:'failed',updated_at:new Date().toISOString()}).eq('id',booking.id);
    return { status: 'failed', reason: String(error.message || error).slice(0, 500) };
  }
}

async function listDriveImages(folderId) {
  const auth = await authorizedClient();
  const drive = googleLib().drive({ version: 'v3', auth });
  const { data } = await drive.files.list({
    q: `'${folderId}' in parents and trashed = false and mimeType contains 'image/'`,
    fields: 'files(id,name,mimeType,size,webViewLink,thumbnailLink)',
    pageSize: 1000,
    orderBy: 'name'
  });
  return (data.files || []).filter(f => ['image/jpeg','image/png','image/webp'].includes(f.mimeType));
}

async function getDriveImageStream(fileId) {
  const auth = await authorizedClient();
  const drive = googleLib().drive({ version: 'v3', auth });
  return drive.files.get({ fileId, alt: 'media' }, { responseType: 'stream' });
}

module.exports = { getAuthUrl, saveOAuthCode, authorizedClient, syncBookingToCalendar, listDriveImages, getDriveImageStream };
