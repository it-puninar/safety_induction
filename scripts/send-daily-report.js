const { createClient } = require('@supabase/supabase-js');
const XLSX       = require('xlsx');
const nodemailer = require('nodemailer');
const WS         = require('ws');

// ── Config ────────────────────────────────────────────────────
const SUPABASE_URL           = process.env.SUPABASE_URL;
const SUPABASE_SERVICE_KEY   = process.env.SUPABASE_SERVICE_ROLE_KEY;
const SMTP_PASS              = process.env.SMTP_PASS;

const SMTP_HOST = 'mail.puninar.com';
const SMTP_PORT = 465;
const SMTP_USER = 'wms-automail@puninar.com';

const EMAIL_TO  = ['mariana@puninar.com', 'tsany.alauddin@puninar.com'];
// ──────────────────────────────────────────────────────────────

async function main() {
  // 1. Rentang waktu hari ini (WIB) → dikonversi ke UTC murni
  const { todayWIB, startUTC, endUTC } = getTodayRange();
  const dateLabel = formatDateLabel(todayWIB);  // "19/06/2026"

  console.log(`[${new Date().toISOString()}] Mengirim laporan untuk tanggal ${dateLabel}`);

  // 2. Query Supabase
  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY, {
    realtime: { transport: WS },
  });

  const { data, error } = await supabase
    .from('safety_induction_records')
    .select('nama_lengkap, no_ktp, nama_perusahaan, nama_bagian_dikunjungi, created_at')
    .gte('created_at', startUTC)
    .lte('created_at', endUTC)
    .order('created_at', { ascending: true });

  if (error) throw new Error('Supabase query error: ' + error.message);

  if (!data || data.length === 0) {
    console.log('Tidak ada data hari ini. Email tidak dikirim.');
    return;
  }

  console.log(`Ditemukan ${data.length} record.`);

  // 3. Buat xlsx
  const rows = data.map((row, idx) => ({
    'NO':               idx + 1,
    'nama_visitor':     row.nama_lengkap,
    'nomor_id':         row.no_ktp,
    'perusahaan':       row.nama_perusahaan,
    'project':          row.nama_bagian_dikunjungi,
    'kategori_visitor': '',
    'tema_training':    'INDUKSI',
    'lokasi':           'NAGRAK',
    'tanggal_training': formatDate(row.created_at),
    'pemateri':         '',
  }));

  const wb = XLSX.utils.book_new();
  const ws = XLSX.utils.json_to_sheet(rows, {
    header: [
      'NO', 'nama_visitor', 'nomor_id', 'perusahaan', 'project',
      'kategori_visitor', 'tema_training', 'lokasi', 'tanggal_training', 'pemateri'
    ]
  });

  // Auto-width kolom
  const colWidths = [
    { wch: 5 }, { wch: 30 }, { wch: 20 }, { wch: 30 }, { wch: 30 },
    { wch: 18 }, { wch: 15 }, { wch: 12 }, { wch: 18 }, { wch: 20 }
  ];
  ws['!cols'] = colWidths;

  XLSX.utils.book_append_sheet(wb, ws, 'Safety Induction');
  const xlsxBuffer = XLSX.write(wb, { type: 'buffer', bookType: 'xlsx' });

  const fileName = `Safety_Induction_${todayWIB.replace(/-/g, '')}.xlsx`;

  // 4. Kirim email via SMTP
  const transporter = nodemailer.createTransport({
    host:   SMTP_HOST,
    port:   SMTP_PORT,
    secure: true,
    auth:   { user: SMTP_USER, pass: SMTP_PASS },
    tls:    { rejectUnauthorized: false },
  });

  await transporter.verify();
  console.log('Koneksi SMTP berhasil.');

  await transporter.sendMail({
    from:    `"Safety Induction System" <${SMTP_USER}>`,
    to:      EMAIL_TO.join(', '),
    subject: `[Safety Induction] Laporan Harian — ${dateLabel}`,
    html: `
      <p>Yth. Tim HSE Puninar Logistics,</p>
      <br>
      <p>Terlampir data Safety Induction tanggal <strong>${dateLabel}</strong>.</p>
      <p>Total pengunjung: <strong>${data.length} orang</strong></p>
      <br>
      <p>Regards,<br>
      <strong>Safety Induction System</strong><br>
      Puninar Logistics</p>
    `,
    attachments: [{
      filename:    fileName,
      content:     xlsxBuffer,
      contentType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    }],
  });

  console.log(`Email berhasil dikirim ke: ${EMAIL_TO.join(', ')}`);
  console.log(`Attachment: ${fileName} (${data.length} baris)`);
}

// ── Helpers ───────────────────────────────────────────────────

function getTodayRange() {
  const now = new Date();
  const wib = new Date(now.toLocaleString('en-US', { timeZone: 'Asia/Jakarta' }));
  const yyyy = wib.getFullYear();
  const mm   = String(wib.getMonth() + 1).padStart(2, '0');
  const dd   = String(wib.getDate()).padStart(2, '0');
  const todayWIB = `${yyyy}-${mm}-${dd}`;

  // Konversi ke UTC murni (hindari karakter '+' di URL query Supabase)
  const startUTC = new Date(`${todayWIB}T00:00:00+07:00`).toISOString();
  const endUTC   = new Date(`${todayWIB}T23:59:59.999+07:00`).toISOString();

  return { todayWIB, startUTC, endUTC };
}

function formatDate(isoString) {
  const d   = new Date(isoString);
  const wib = new Date(d.toLocaleString('en-US', { timeZone: 'Asia/Jakarta' }));
  const dd   = String(wib.getDate()).padStart(2, '0');
  const mm   = String(wib.getMonth() + 1).padStart(2, '0');
  const yyyy = wib.getFullYear();
  return `${dd}/${mm}/${yyyy}`;
}

function formatDateLabel(ymd) {
  const [yyyy, mm, dd] = ymd.split('-');
  return `${dd}/${mm}/${yyyy}`;
}

// ── Run ───────────────────────────────────────────────────────
main().catch(err => {
  console.error('FATAL:', err.message || err);
  process.exit(1);
});
