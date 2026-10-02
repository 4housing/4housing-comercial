-- ============================================================================
-- 4housing Comercial · cotizaciones: costeo estructurado + datos de planificación
-- ============================================================================
-- Fase 2 del cableado Comercial → Compras → Planificación (solo VENTAS).
-- Al adjuntar el costeo a la cotización, la app lo parsea (secciones del Tablero
-- + detalle para el desglose) y guarda el presupuesto ESTRUCTURADO en `costeo`
-- (jsonb). Así, al ganar, pasa redondo a Compras (y el MOD a Planificación) sin
-- re-parsear ningún Excel.
--
-- También se capturan en la etapa comercial los datos que Planificación necesita
-- para dar de alta el proyecto: cantidad de módulos, tamaño de módulos, m² totales.
-- Son OPCIONALES hasta marcar la cotización como ganada (ahí se vuelven obligatorios,
-- enforcement en la app — Fase 3).
--
-- Correr en el SQL Editor de wcpk. Idempotente.
-- ============================================================================

alter table public.cotizaciones
  add column if not exists costeo       jsonb,      -- { secciones:[{seccion,orden,presupuesto_ars,presupuesto_usd}], detalle:{...}, tc, meta, tol, archivo_nombre, cargado_en }
  add column if not exists modulos      integer,    -- cantidad de módulos del proyecto
  add column if not exists tam_modulos  text,       -- tamaño/tipología de módulos
  add column if not exists m2_totales   numeric;    -- m² totales del proyecto
