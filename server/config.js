const supabase = require('./supabase');

const DEFAULTS = {
  studioName: 'Kaia Photo Studio',
  address: 'Jl. Ariloka No. 17, Krobokan, Semarang Barat, Semarang',
  openTime: '08:00',
  closeTime: '18:00',
  whatsapp: '6281390045600',
  instagram: 'kaia.photostudio',
  bankName: 'BCA',
  bankAccount: '0092280193',
  bankHolder: 'Rajendra Satria Rizki Wardhana',
  slotIntervalMinutes: 10
};

async function readSettings() {
  const { data, error } = await supabase.from('settings').select('key, value');
  if (error || !data) return { ...DEFAULTS };

  const s = { ...DEFAULTS };
  data.forEach((row) => {
    s[row.key] = row.key === 'slotIntervalMinutes' ? Number(row.value) : row.value;
  });
  return s;
}

async function writeSettings(partial) {
  const rows = Object.entries(partial).map(([key, value]) => ({ key, value: String(value) }));
  if (rows.length) {
    const { error } = await supabase.from('settings').upsert(rows, { onConflict: 'key' });
    if (error) throw error;
  }
  return readSettings();
}

module.exports = { readSettings, writeSettings };
