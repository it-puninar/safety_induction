<?php
header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { exit(0); }

require_once __DIR__ . '/config.php';

// ── Only accept POST ──────────────────────────────────────────
if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['success' => false, 'message' => 'Method not allowed']);
    exit;
}

// ── Parse JSON body ───────────────────────────────────────────
$raw  = file_get_contents('php://input');
$body = json_decode($raw, true);
if (!$body || !is_array($body)) {
    http_response_code(400);
    echo json_encode(['success' => false, 'message' => 'Invalid JSON body']);
    exit;
}

// ── Validate data diri ────────────────────────────────────────
$textFields = [
    'nama_lengkap'           => 'Nama lengkap',
    'no_ktp'                 => 'No KTP',
    'nama_perusahaan'        => 'Nama perusahaan',
    'tujuan_datang'          => 'Tujuan datang',
    'nama_bagian_dikunjungi' => 'Nama dan bagian yang dikunjungi',
    'maksud_tujuan'          => 'Maksud dan tujuan',
];

$errors = [];
$data   = [];

foreach ($textFields as $key => $label) {
    $val = isset($body[$key]) ? trim($body[$key]) : '';
    if ($val === '') {
        $errors[] = "$label wajib diisi";
    } else {
        $data[$key] = $val;
    }
}

// ── Validate checklist ────────────────────────────────────────
$answers = [];
for ($i = 1; $i <= 10; $i++) {
    $key = "q$i";
    $val = isset($body[$key]) ? strtolower(trim($body[$key])) : '';
    if (!in_array($val, ['ya', 'tidak'], true)) {
        $errors[] = "Pertanyaan $i belum dijawab";
    } else {
        $answers[$key] = ($val === 'ya') ? 'Y' : 'T';
    }
}

if ($errors) {
    http_response_code(422);
    echo json_encode(['success' => false, 'errors' => $errors]);
    exit;
}

// ── Hitung skor ───────────────────────────────────────────────
$totalYa = 0;
foreach ($answers as $v) {
    if ($v === 'Y') $totalYa++;
}
$pct    = round(($totalYa / 10) * 100, 2);
$status = ($totalYa / 10) > 0.9 ? 'LOLOS' : 'TIDAK LOLOS';

// ── Simpan ke database ────────────────────────────────────────
$sql = "
    INSERT INTO safety_induction_records
        (nama_lengkap, no_ktp, nama_perusahaan, tujuan_datang,
         nama_bagian_dikunjungi, maksud_tujuan,
         q1, q2, q3, q4, q5, q6, q7, q8, q9, q10,
         total_ya, persentase, status, ip_address, user_agent)
    VALUES
        (:nama_lengkap, :no_ktp, :nama_perusahaan, :tujuan_datang,
         :nama_bagian_dikunjungi, :maksud_tujuan,
         :q1, :q2, :q3, :q4, :q5, :q6, :q7, :q8, :q9, :q10,
         :total_ya, :persentase, :status, :ip_address, :user_agent)
    RETURNING id, created_at
";

// Build params — compatible PHP 7.0+
$params = [
    ':nama_lengkap'           => $data['nama_lengkap'],
    ':no_ktp'                 => $data['no_ktp'],
    ':nama_perusahaan'        => $data['nama_perusahaan'],
    ':tujuan_datang'          => $data['tujuan_datang'],
    ':nama_bagian_dikunjungi' => $data['nama_bagian_dikunjungi'],
    ':maksud_tujuan'          => $data['maksud_tujuan'],
    ':total_ya'               => $totalYa,
    ':persentase'             => $pct,
    ':status'                 => $status,
    ':ip_address'             => isset($_SERVER['REMOTE_ADDR']) ? $_SERVER['REMOTE_ADDR'] : null,
    ':user_agent'             => isset($_SERVER['HTTP_USER_AGENT']) ? $_SERVER['HTTP_USER_AGENT'] : null,
];
foreach ($answers as $key => $val) {
    $params[':' . $key] = $val;
}

try {
    $pdo  = getDB();
    $stmt = $pdo->prepare($sql);
    $stmt->execute($params);
    $row  = $stmt->fetch();

    echo json_encode([
        'success'    => true,
        'id'         => (int) $row['id'],
        'status'     => $status,
        'total_ya'   => $totalYa,
        'persentase' => $pct,
        'created_at' => $row['created_at'],
    ]);

} catch (Exception $e) {
    http_response_code(500);
    error_log('[SafetyInduction] Error: ' . $e->getMessage());
    echo json_encode([
        'success' => false,
        'message' => 'Gagal menyimpan data: ' . $e->getMessage(),
    ]);
    exit;
}
