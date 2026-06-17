    -- ============================================================
    -- Safety Induction DB — Puninar Logistics
    -- PostgreSQL Schema
    -- ============================================================

    -- Drop if re-running
    DROP TABLE IF EXISTS safety_induction_records CASCADE;
    DROP VIEW  IF EXISTS v_safety_induction_summary CASCADE;
    DROP VIEW  IF EXISTS v_safety_induction_stats   CASCADE;

    -- ── Main table ───────────────────────────────────────────────
    CREATE TABLE safety_induction_records (
        id                      SERIAL PRIMARY KEY,

        -- Data diri
        nama_lengkap            VARCHAR(255)    NOT NULL,
        no_ktp                  VARCHAR(16)     NOT NULL,
        nama_perusahaan         VARCHAR(255)    NOT NULL,
        tujuan_datang           VARCHAR(500)    NOT NULL,
        nama_bagian_dikunjungi  VARCHAR(500)    NOT NULL,
        maksud_tujuan           TEXT            NOT NULL,

        -- Jawaban checklist (Y = Ya, T = Tidak)
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

        -- Hasil kalkulasi
        total_ya    INTEGER         NOT NULL CHECK (total_ya BETWEEN 0 AND 10),
        persentase  NUMERIC(5,2)    NOT NULL CHECK (persentase BETWEEN 0 AND 100),
        status      VARCHAR(20)     NOT NULL CHECK (status IN ('LOLOS','TIDAK LOLOS')),

        -- Metadata
        created_at  TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
        ip_address  VARCHAR(45),
        user_agent  TEXT
    );

    -- ── Indexes ──────────────────────────────────────────────────
    CREATE INDEX idx_si_no_ktp      ON safety_induction_records (no_ktp);
    CREATE INDEX idx_si_status      ON safety_induction_records (status);
    CREATE INDEX idx_si_created_at  ON safety_induction_records (created_at DESC);
    CREATE INDEX idx_si_perusahaan  ON safety_induction_records (nama_perusahaan);

    -- ── View: daftar lengkap (WIB) ───────────────────────────────
    CREATE VIEW v_safety_induction_summary AS
    SELECT
        id,
        nama_lengkap,
        no_ktp,
        nama_perusahaan,
        tujuan_datang,
        nama_bagian_dikunjungi,
        maksud_tujuan,
        q1, q2, q3, q4, q5, q6, q7, q8, q9, q10,
        total_ya,
        persentase,
        status,
        (created_at AT TIME ZONE 'Asia/Jakarta') AS created_at_wib,
        ip_address
    FROM safety_induction_records
    ORDER BY created_at DESC;

    -- ── View: statistik ringkasan ────────────────────────────────
    CREATE VIEW v_safety_induction_stats AS
    SELECT
        COUNT(*)                                                    AS total_pengunjung,
        COUNT(*) FILTER (WHERE status = 'LOLOS')                    AS total_lolos,
        COUNT(*) FILTER (WHERE status = 'TIDAK LOLOS')              AS total_tidak_lolos,
        ROUND(
            COUNT(*) FILTER (WHERE status = 'LOLOS') * 100.0
            / NULLIF(COUNT(*), 0), 2
        )                                                           AS pct_lolos,
        ROUND(AVG(persentase), 2)                                   AS rata_rata_skor,
        ROUND(AVG(total_ya), 2)                                     AS rata_rata_ya,
        (SELECT created_at AT TIME ZONE 'Asia/Jakarta'
        FROM safety_induction_records ORDER BY created_at DESC LIMIT 1) AS terakhir_submit
    FROM safety_induction_records;
