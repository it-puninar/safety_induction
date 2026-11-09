-- ============================================================
-- Login untuk halaman records.html (tabel user sendiri)
-- Jalankan di: Supabase Dashboard → SQL Editor
--
-- Cara kerja:
--   * records_users    : akun HSE/Admin (password disimpan sebagai hash bcrypt)
--   * records_sessions : token login (disimpan sebagai hash SHA-256, berlaku 12 jam)
--   * Kedua tabel TIDAK bisa diakses langsung dari browser (RLS aktif tanpa policy).
--   * Browser hanya boleh memanggil 3 fungsi: records_login, records_get_data, records_logout.
--   * Data safety_induction_records tetap tidak bisa dibaca anon; hanya lewat
--     records_get_data() dengan token yang valid.
--   * 5x salah password → akun terkunci 15 menit.
-- ============================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;

-- ── Tabel user ───────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.records_users (
    id              BIGSERIAL    PRIMARY KEY,
    username        VARCHAR(50)  NOT NULL UNIQUE CHECK (username = lower(username)),
    password_hash   TEXT         NOT NULL,
    nama_lengkap    VARCHAR(255) NOT NULL,
    is_active       BOOLEAN      NOT NULL DEFAULT TRUE,
    failed_attempts INTEGER      NOT NULL DEFAULT 0,
    locked_until    TIMESTAMPTZ,
    last_login      TIMESTAMPTZ,
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

-- ── Tabel session ────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.records_sessions (
    token_hash  TEXT         PRIMARY KEY,
    user_id     BIGINT       NOT NULL REFERENCES public.records_users(id) ON DELETE CASCADE,
    expires_at  TIMESTAMPTZ  NOT NULL,
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_rs_expires ON public.records_sessions (expires_at);

-- Kunci rapat: RLS aktif tanpa policy + cabut semua hak akses langsung
ALTER TABLE public.records_users    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.records_sessions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.records_users, public.records_sessions FROM anon, authenticated;

-- ── Fungsi: login ────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.records_login(p_username TEXT, p_password TEXT)
RETURNS JSON
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    u        public.records_users%ROWTYPE;
    v_token  TEXT;
    v_exp    TIMESTAMPTZ := NOW() + INTERVAL '12 hours';
    v_fails  INTEGER;
BEGIN
    DELETE FROM public.records_sessions WHERE expires_at < NOW();

    SELECT * INTO u FROM public.records_users
     WHERE username = lower(trim(p_username)) AND is_active
       FOR UPDATE;

    IF NOT FOUND THEN
        PERFORM pg_sleep(0.4);
        RETURN json_build_object('ok', false, 'error', 'invalid');
    END IF;

    IF u.locked_until IS NOT NULL AND u.locked_until > NOW() THEN
        RETURN json_build_object('ok', false, 'error', 'locked');
    END IF;
    IF u.locked_until IS NOT NULL THEN u.failed_attempts := 0; END IF;  -- kunci sudah habis

    IF u.password_hash <> crypt(p_password, u.password_hash) THEN
        v_fails := u.failed_attempts + 1;
        UPDATE public.records_users
           SET failed_attempts = v_fails,
               locked_until    = CASE WHEN v_fails >= 5 THEN NOW() + INTERVAL '15 minutes' ELSE NULL END
         WHERE id = u.id;
        PERFORM pg_sleep(0.4);
        RETURN json_build_object('ok', false, 'error', CASE WHEN v_fails >= 5 THEN 'locked' ELSE 'invalid' END);
    END IF;

    v_token := encode(gen_random_bytes(32), 'hex');
    INSERT INTO public.records_sessions (token_hash, user_id, expires_at)
    VALUES (encode(digest(v_token, 'sha256'), 'hex'), u.id, v_exp);

    UPDATE public.records_users
       SET failed_attempts = 0, locked_until = NULL, last_login = NOW()
     WHERE id = u.id;

    RETURN json_build_object('ok', true, 'token', v_token,
                             'nama', u.nama_lengkap, 'expires_at', v_exp);
END;
$$;

-- ── Fungsi: ambil semua data (butuh token valid) ─────────────
CREATE OR REPLACE FUNCTION public.records_get_data(p_token TEXT)
RETURNS SETOF public.safety_induction_records
LANGUAGE plpgsql SECURITY DEFINER STABLE
SET search_path = public, extensions
AS $$
BEGIN
    IF p_token IS NULL OR NOT EXISTS (
        SELECT 1
          FROM public.records_sessions s
          JOIN public.records_users u ON u.id = s.user_id
         WHERE s.token_hash = encode(digest(p_token, 'sha256'), 'hex')
           AND s.expires_at > NOW()
           AND u.is_active
    ) THEN
        RAISE EXCEPTION 'SESSION_INVALID';
    END IF;

    RETURN QUERY
    SELECT * FROM public.safety_induction_records
     ORDER BY created_at DESC, id DESC;
END;
$$;

-- ── Fungsi: logout ───────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.records_logout(p_token TEXT)
RETURNS VOID
LANGUAGE sql SECURITY DEFINER
SET search_path = public, extensions
AS $$
    DELETE FROM public.records_sessions
     WHERE token_hash = encode(digest(p_token, 'sha256'), 'hex');
$$;

-- ── Hak eksekusi: hanya 3 fungsi ini untuk browser ───────────
REVOKE ALL ON FUNCTION public.records_login(TEXT, TEXT)  FROM PUBLIC;
REVOKE ALL ON FUNCTION public.records_get_data(TEXT)     FROM PUBLIC;
REVOKE ALL ON FUNCTION public.records_logout(TEXT)       FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.records_login(TEXT, TEXT) TO anon;
GRANT EXECUTE ON FUNCTION public.records_get_data(TEXT)    TO anon;
GRANT EXECUTE ON FUNCTION public.records_logout(TEXT)     TO anon;

-- ============================================================
-- MENAMBAH USER  (jalankan manual di SQL Editor; JANGAN di-commit dengan password asli)
-- ============================================================
-- INSERT INTO public.records_users (username, password_hash, nama_lengkap)
-- VALUES ('hse.admin', extensions.crypt('GantiPasswordIni!', extensions.gen_salt('bf', 10)), 'HSE Admin');

-- Ganti password:
-- UPDATE public.records_users
--    SET password_hash = extensions.crypt('PasswordBaru!', extensions.gen_salt('bf', 10)),
--        failed_attempts = 0, locked_until = NULL
--  WHERE username = 'hse.admin';

-- Nonaktifkan user (sekaligus matikan sesinya):
-- UPDATE public.records_users SET is_active = FALSE WHERE username = 'hse.admin';
-- DELETE FROM public.records_sessions WHERE user_id = (SELECT id FROM public.records_users WHERE username = 'hse.admin');
