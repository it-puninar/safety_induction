-- ============================================================
-- Safety Induction — Supabase Schema
-- Jalankan di: Supabase Dashboard → SQL Editor
-- ============================================================

CREATE TABLE IF NOT EXISTS safety_induction_records (
    id                      BIGSERIAL       PRIMARY KEY,
    nama_lengkap            VARCHAR(255)    NOT NULL,
    no_ktp                  VARCHAR(16)     NOT NULL,
    nama_perusahaan         VARCHAR(255)    NOT NULL,
    tujuan_datang           VARCHAR(500)    NOT NULL,
    nama_bagian_dikunjungi  VARCHAR(500)    NOT NULL,
    maksud_tujuan           TEXT            NOT NULL,
    q1  CHAR(1) NOT NULL CHECK (q1  IN ('Y','T')),
    q2  CHAR(1) NOT NULL CHECK (q2  IN ('Y','T')),
    q3  CHAR(1) NOT NULL CHECK (q3  IN ('Y','T')),
    q4  CHAR(1) NOT NULL CHECK (q4  IN ('Y','T')),
    q5  CHAR(1) NOT NULL CHECK (q5  IN ('Y','T')),
    q6  CHAR(1) NOT NULL CHECK (q6  IN ('Y','T')),
    q7  CHAR(1) NOT NULL CHECK (q7  IN ('Y','T')),
    q8  CHAR(1) NOT NULL CHECK (q8  IN ('Y','T')),
    q9  CHAR(1) NOT NULL CHECK (q9  IN ('Y','T')),
    q10 CHAR(1) NOT NULL CHECK (q10 IN ('Y','T')),
    total_ya    INTEGER         NOT NULL CHECK (total_ya BETWEEN 0 AND 10),
    persentase  NUMERIC(5,2)    NOT NULL CHECK (persentase BETWEEN 0 AND 100),
    status      VARCHAR(20)     NOT NULL CHECK (status IN ('LOLOS','TIDAK LOLOS')),
    created_at  TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

-- Index untuk query management
CREATE INDEX IF NOT EXISTS idx_si_no_ktp     ON safety_induction_records (no_ktp);
CREATE INDEX IF NOT EXISTS idx_si_status     ON safety_induction_records (status);
CREATE INDEX IF NOT EXISTS idx_si_created_at ON safety_induction_records (created_at DESC);

-- Enable Row Level Security
ALTER TABLE safety_induction_records ENABLE ROW LEVEL SECURITY;

-- Izinkan INSERT dari browser (anon) — SELECT/UPDATE/DELETE diblokir
CREATE POLICY "allow_anon_insert"
    ON safety_induction_records
    FOR INSERT TO anon
    WITH CHECK (true);
