-- =====================================================================
-- 4housing — Leads entrantes en Prospección
-- Agrega los campos necesarios para que la Edge Function `clasificar-mail`
-- pueda registrar como PROSPECTO los contactos que entran por el formulario
-- web y por WhatsApp (además de crear la oportunidad, como hasta ahora).
--
-- CÓMO CORRERLO: pegar este archivo en Supabase → SQL Editor → Run.
-- Es 100% aditivo: solo agrega columnas nuevas a `prospectos`, con
-- `IF NOT EXISTS`, así que es seguro correrlo aunque ya exista algo.
-- No toca RLS ni las columnas viejas. Los ~1900 prospectos actuales
-- quedan con `via_contacto` y `motivo` en NULL (= siguen siendo outbound).
-- =====================================================================

-- Vía por la que entró el contacto: 'whatsapp' | 'formulario_web'.
-- NULL = prospecto outbound (cargado a mano o importado), como hasta ahora.
alter table public.prospectos
  add column if not exists via_contacto text;

-- Motivo de la consulta declarado en el formulario (ej. "Otros", "Alquiler").
alter table public.prospectos
  add column if not exists motivo text;

-- Fecha de alta. La mayoría de las tablas ya la tienen; la aseguramos para
-- poder filtrar y hacer estadística por fecha en los leads entrantes.
alter table public.prospectos
  add column if not exists created_at timestamptz not null default now();

comment on column public.prospectos.via_contacto is
  'Canal de entrada del lead: whatsapp | formulario_web. NULL = prospecto outbound.';
comment on column public.prospectos.motivo is
  'Motivo de la consulta declarado en el formulario web / WhatsApp.';
