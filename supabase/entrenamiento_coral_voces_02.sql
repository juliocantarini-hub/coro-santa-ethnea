-- ═══════════════════════════════════════════════════════════════════
-- CORUM — coral-voces-02: módulo Entrenamiento completo
-- (ejercicios de técnica vocal + "Práctica por voz" con MusicXML)
-- Ejecutar en: supabase.com → proyecto coral-voces-02 → SQL Editor (todo junto)
-- Este proyecto es multi-tenant: sirve a Santa Ethnea, Sonamos, Sanroman y
-- Encuentro a la vez, todos distinguidos por coro_id. Se corre UNA sola vez
-- para los 4. Se puede ejecutar más de una vez sin problema (usa
-- IF NOT EXISTS / OR REPLACE).
--
-- IMPORTANTE — hallazgo al correr la v1 de este script: la tabla
-- ejercicios_entrenamiento YA EXISTÍA en este proyecto, pero sin columna
-- coro_id — hoy es un catálogo único, compartido por los 4 coros (así
-- "ya funciona" actualmente). actividad_entrenamiento sí tenía coro_id.
-- Decisión (confirmada con Julio): el catálogo sigue compartido. coro_id
-- en ejercicios_entrenamiento queda NULLABLE: NULL = ejercicio global,
-- visible/editable por cualquier director de los 4 coros (así quedan los
-- que ya existían); un coro_id puntual = ejercicio privado de ese coro.
--
-- Qué crea/ajusta:
--   · ejercicios_entrenamiento: agrega coro_id (nullable) a la tabla ya
--     existente, con políticas que tratan NULL como "global".
--   · actividad_entrenamiento: ya existía con coro_id correcto, solo se
--     documentan políticas e índices (no debería cambiar nada si ya está bien).
--   · partituras_entrenamiento: ESTA SÍ es nueva — obras cargadas en
--     MusicXML para "Práctica por voz" (genera el audio de cada voz en el
--     navegador), por coro (no compartida — cada coro canta su propio
--     repertorio). Guarda el MusicXML en texto plano, no usa Storage.
--
-- Usa las mismas funciones mis_coros_activos() / soy_director_de(coro_id)
-- que ya están creadas (cerrar_perfiles_coral_voces_02.sql /
-- parche_perfiles_pendientes_coral_voces_02.sql), y agrega una nueva,
-- soy_director_en_algun_coro(), para poder gestionar el catálogo global.
--
-- Igual que en proyecto2_sorpresas_y_estadistica.sql: agregamos los GRANT de
-- tabla explícitos, porque en este proyecto no vienen por defecto y sin
-- ellos las consultas fallan aunque las políticas estén bien.
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

-- ─── 0. Funciones de apoyo ────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.mis_coros_activos()
RETURNS SETOF uuid
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT coro_id FROM public.perfiles
  WHERE id = auth.uid()
    AND (rol IN ('director', 'admin') OR estado IN ('activo', 'pausa'));
$$;

CREATE OR REPLACE FUNCTION public.soy_director_de(p_coro uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.perfiles
    WHERE id = auth.uid() AND coro_id = p_coro AND rol IN ('director', 'admin')
  );
$$;

-- Nueva: para administrar el catálogo GLOBAL (coro_id NULL) de ejercicios,
-- cualquier director/admin de cualquiera de los 4 coros puede gestionarlo.
CREATE OR REPLACE FUNCTION public.soy_director_en_algun_coro()
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.perfiles
    WHERE id = auth.uid() AND rol IN ('director', 'admin')
  );
$$;

REVOKE ALL ON FUNCTION public.mis_coros_activos() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.soy_director_de(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.soy_director_en_algun_coro() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.mis_coros_activos() TO authenticated;
GRANT EXECUTE ON FUNCTION public.soy_director_de(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.soy_director_en_algun_coro() TO authenticated;

-- ═══ PARTE 1: EJERCICIOS DE TÉCNICA VOCAL (ya existía, le falta coro_id) ═══

-- Fallback por si este script se corre en un proyecto nuevo donde la tabla
-- todavía no existe (acá, en coral-voces-02, ya existe con más columnas
-- propias — descripcion_corta, nivel, momento_sugerido, modo, created_at —
-- así que esto es un no-op).
CREATE TABLE IF NOT EXISTS public.ejercicios_entrenamiento (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  categoria             text NOT NULL,
  nombre                text NOT NULL,
  instruccion_texto     text,
  patron_tone           jsonb NOT NULL,
  duracion_estimada_seg numeric,
  orden                 integer NOT NULL DEFAULT 0,
  activo                boolean NOT NULL DEFAULT true,
  creado_en             timestamptz NOT NULL DEFAULT now()
);

-- coro_id NULLABLE a propósito: NULL = ejercicio global/compartido por los
-- 4 coros (así quedan los que ya existían). Con un coro_id puesto, el
-- ejercicio pasa a ser privado de ese coro.
ALTER TABLE public.ejercicios_entrenamiento
  ADD COLUMN IF NOT EXISTS coro_id uuid REFERENCES public.coros(id) ON DELETE CASCADE;

CREATE INDEX IF NOT EXISTS ejercicios_entrenamiento_coro_idx
  ON public.ejercicios_entrenamiento (coro_id);

ALTER TABLE public.ejercicios_entrenamiento ENABLE ROW LEVEL SECURITY;

GRANT SELECT, INSERT, UPDATE, DELETE ON public.ejercicios_entrenamiento TO authenticated;
REVOKE ALL ON public.ejercicios_entrenamiento FROM anon;

DROP POLICY IF EXISTS "Miembros activos leen ejercicios activos de su coro" ON public.ejercicios_entrenamiento;
DROP POLICY IF EXISTS "Miembros activos leen ejercicios activos (globales o de su coro)" ON public.ejercicios_entrenamiento;
CREATE POLICY "Miembros activos leen ejercicios activos (globales o de su coro)"
  ON public.ejercicios_entrenamiento FOR SELECT TO authenticated
  USING (
    activo = true
    AND (coro_id IS NULL OR coro_id IN (SELECT public.mis_coros_activos()))
  );

DROP POLICY IF EXISTS "Directores leen todos los ejercicios de su coro" ON public.ejercicios_entrenamiento;
DROP POLICY IF EXISTS "Directores leen ejercicios globales o de su coro" ON public.ejercicios_entrenamiento;
CREATE POLICY "Directores leen ejercicios globales o de su coro"
  ON public.ejercicios_entrenamiento FOR SELECT TO authenticated
  USING (coro_id IS NULL OR public.soy_director_de(coro_id));

DROP POLICY IF EXISTS "Directores crean ejercicios" ON public.ejercicios_entrenamiento;
DROP POLICY IF EXISTS "Directores crean ejercicios globales o de su coro" ON public.ejercicios_entrenamiento;
CREATE POLICY "Directores crean ejercicios globales o de su coro"
  ON public.ejercicios_entrenamiento FOR INSERT TO authenticated
  WITH CHECK (
    (coro_id IS NULL AND public.soy_director_en_algun_coro())
    OR public.soy_director_de(coro_id)
  );

DROP POLICY IF EXISTS "Directores editan ejercicios de su coro" ON public.ejercicios_entrenamiento;
DROP POLICY IF EXISTS "Directores editan ejercicios globales o de su coro" ON public.ejercicios_entrenamiento;
CREATE POLICY "Directores editan ejercicios globales o de su coro"
  ON public.ejercicios_entrenamiento FOR UPDATE TO authenticated
  USING (
    (coro_id IS NULL AND public.soy_director_en_algun_coro())
    OR public.soy_director_de(coro_id)
  )
  WITH CHECK (
    (coro_id IS NULL AND public.soy_director_en_algun_coro())
    OR public.soy_director_de(coro_id)
  );

DROP POLICY IF EXISTS "Directores borran ejercicios de su coro" ON public.ejercicios_entrenamiento;
DROP POLICY IF EXISTS "Directores borran ejercicios globales o de su coro" ON public.ejercicios_entrenamiento;
CREATE POLICY "Directores borran ejercicios globales o de su coro"
  ON public.ejercicios_entrenamiento FOR DELETE TO authenticated
  USING (
    (coro_id IS NULL AND public.soy_director_en_algun_coro())
    OR public.soy_director_de(coro_id)
  );

-- ─── 2. Actividad (ya existía con coro_id correcto; solo políticas/índices) ──
CREATE TABLE IF NOT EXISTS public.actividad_entrenamiento (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  coro_id           uuid NOT NULL REFERENCES public.coros(id) ON DELETE CASCADE,
  cantante_id       uuid NOT NULL,
  ejercicio_id      uuid NOT NULL REFERENCES public.ejercicios_entrenamiento(id) ON DELETE CASCADE,
  duracion_real_seg numeric,
  metadata          jsonb,
  completado_en     timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS actividad_entrenamiento_cantante_idx
  ON public.actividad_entrenamiento (cantante_id, completado_en DESC);
CREATE INDEX IF NOT EXISTS actividad_entrenamiento_coro_idx
  ON public.actividad_entrenamiento (coro_id);

ALTER TABLE public.actividad_entrenamiento ENABLE ROW LEVEL SECURITY;

GRANT SELECT, INSERT, DELETE ON public.actividad_entrenamiento TO authenticated;
REVOKE ALL ON public.actividad_entrenamiento FROM anon;

DROP POLICY IF EXISTS "Cada cantante registra su propia actividad" ON public.actividad_entrenamiento;
CREATE POLICY "Cada cantante registra su propia actividad"
  ON public.actividad_entrenamiento FOR INSERT TO authenticated
  WITH CHECK (cantante_id = auth.uid());

DROP POLICY IF EXISTS "Cada cantante lee su propia actividad" ON public.actividad_entrenamiento;
CREATE POLICY "Cada cantante lee su propia actividad"
  ON public.actividad_entrenamiento FOR SELECT TO authenticated
  USING (cantante_id = auth.uid());

DROP POLICY IF EXISTS "Directores leen la actividad de su coro" ON public.actividad_entrenamiento;
CREATE POLICY "Directores leen la actividad de su coro"
  ON public.actividad_entrenamiento FOR SELECT TO authenticated
  USING (public.soy_director_de(coro_id));

-- Necesaria para poder borrar un ejercicio que ya tiene actividad registrada
-- (eliminarEjercicioEntrenamiento borra primero la actividad asociada, y esa
-- actividad puede ser de cualquier cantante del coro, no solo la del director).
DROP POLICY IF EXISTS "Directores borran actividad de su coro" ON public.actividad_entrenamiento;
CREATE POLICY "Directores borran actividad de su coro"
  ON public.actividad_entrenamiento FOR DELETE TO authenticated
  USING (public.soy_director_de(coro_id));

-- ═══ PARTE 2: PRÁCTICA POR VOZ (partituras en MusicXML) — esto es lo nuevo ═══
-- No compartida entre coros: cada coro canta su propio repertorio.

CREATE TABLE IF NOT EXISTS public.partituras_entrenamiento (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  coro_id       uuid NOT NULL REFERENCES public.coros(id) ON DELETE CASCADE,
  titulo        text NOT NULL,
  compositor    text,
  musicxml      text NOT NULL,
  duracion_seg  numeric,
  publicada     boolean NOT NULL DEFAULT false,
  creado_en     timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS partituras_entrenamiento_coro_idx
  ON public.partituras_entrenamiento (coro_id);

ALTER TABLE public.partituras_entrenamiento ENABLE ROW LEVEL SECURITY;

GRANT SELECT, INSERT, UPDATE, DELETE ON public.partituras_entrenamiento TO authenticated;
REVOKE ALL ON public.partituras_entrenamiento FROM anon;

DROP POLICY IF EXISTS "Miembros activos leen partituras publicadas de su coro" ON public.partituras_entrenamiento;
CREATE POLICY "Miembros activos leen partituras publicadas de su coro"
  ON public.partituras_entrenamiento FOR SELECT TO authenticated
  USING (publicada = true AND coro_id IN (SELECT public.mis_coros_activos()));

DROP POLICY IF EXISTS "Directores leen todas las partituras de su coro" ON public.partituras_entrenamiento;
CREATE POLICY "Directores leen todas las partituras de su coro"
  ON public.partituras_entrenamiento FOR SELECT TO authenticated
  USING (public.soy_director_de(coro_id));

DROP POLICY IF EXISTS "Directores crean partituras" ON public.partituras_entrenamiento;
CREATE POLICY "Directores crean partituras"
  ON public.partituras_entrenamiento FOR INSERT TO authenticated
  WITH CHECK (public.soy_director_de(coro_id));

DROP POLICY IF EXISTS "Directores editan partituras de su coro" ON public.partituras_entrenamiento;
CREATE POLICY "Directores editan partituras de su coro"
  ON public.partituras_entrenamiento FOR UPDATE TO authenticated
  USING (public.soy_director_de(coro_id))
  WITH CHECK (public.soy_director_de(coro_id));

DROP POLICY IF EXISTS "Directores borran partituras de su coro" ON public.partituras_entrenamiento;
CREATE POLICY "Directores borran partituras de su coro"
  ON public.partituras_entrenamiento FOR DELETE TO authenticated
  USING (public.soy_director_de(coro_id));

COMMIT;
