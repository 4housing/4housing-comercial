-- ============================================================================
-- Liquidación Repcont — historial de liquidaciones del técnico de reefers
--
-- CORRER en el SQL Editor del proyecto del CRM (wcpkpwxhqdcdljfwzcmy),
-- DESPUÉS de 2026-11-02-indicadores-tablas.sql y 2026-11-03-indicadores-editores.sql.
--
-- QUÉ RESUELVE
-- ------------
-- El técnico de los reefers cobra por día y por equipo. Hasta hoy eso se
-- liquidaba en un Excel a mano, con una hoja por mes. El botón "Liquidación
-- Repcont" genera ese Excel desde los datos del CRM; esta tabla guarda el
-- registro de cada liquidación emitida.
--
-- POR QUÉ HACE FALTA GUARDARLO
-- ----------------------------
-- El tipo de cambio es el del día en que se baja el informe (es el criterio
-- del técnico: factura con el TC del día en que recibe la liquidación). Eso
-- hace que el mismo mes dé un total distinto según cuándo se genere. Guardando
-- el TC usado, con su fecha y su fuente, la liquidación que se mandó queda
-- reconstruible aunque el botón se vuelva a apretar meses después.
--
-- El Excel histórico no guardaba nada de esto: el TC era un número pelado
-- tipeado en una celda, sin fecha, sin etiqueta y sin fuente.
--
-- ES ADITIVO: crea una tabla nueva. No toca ninguna tabla, función ni política
-- existente, ni del CRM ni de Indicadores.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 1. LA TABLA
-- ----------------------------------------------------------------------------
create table if not exists public.ind_liquidacion_repcont (
  id            bigint generated always as identity primary key,

  -- el mes liquidado, 'YYYY-MM'. Uno solo por mes: volver a generar corrige
  -- la liquidación de ese mes, no agrega otra.
  mes_anio      text    not null,

  dias          integer not null,          -- días facturables del mes
  contenedores  integer not null,          -- series distintas que facturaron
  listados      integer not null,          -- filas de la hoja (incluye las de stock)

  usd_dia       numeric not null,          -- tarifa del período (3,5 hasta 12-2024; 4 desde 01-2025)
  total_usd     numeric not null,          -- dias * usd_dia

  -- El tipo de cambio, con todo lo que hace falta para poder repetir la cuenta.
  tc            numeric not null,
  tc_fecha      date,                      -- a qué día corresponde la cotización
  tc_fuente     text,                      -- de dónde salió, o 'manual' si se tipeó
  total_pesos   numeric not null,          -- total_usd * tc

  -- La foto de lo que se facturó: una entrada por serie con sus días y tramos.
  -- Va en jsonb para no tener que mantener una tabla hija por algo que solo se
  -- lee para reimprimir o auditar.
  detalle       jsonb,

  -- Las diferencias que el botón detectó contra lo esperado y que la persona
  -- revisó antes de emitir. Queda constancia de que se vieron.
  diferencias   jsonb,

  nota          text,
  generado_por  text,
  generado_en   timestamptz not null default now(),

  constraint ind_liq_repcont_mes_key    unique (mes_anio),
  constraint ind_liq_repcont_mes_chk    check (mes_anio ~ '^[0-9]{4}-[0-9]{2}$'),
  constraint ind_liq_repcont_dias_chk   check (dias >= 0),
  constraint ind_liq_repcont_tc_chk     check (tc > 0),
  constraint ind_liq_repcont_usd_chk    check (usd_dia > 0)
);

comment on table public.ind_liquidacion_repcont is
  'Una fila por liquidación mensual emitida al técnico de reefers. Guarda el '
  'TC usado con su fecha y fuente para que el total sea reconstruible: el '
  'criterio es el TC del día en que se baja el informe, así que sin esto el '
  'mismo mes daría distinto cada vez.';

comment on column public.ind_liquidacion_repcont.tc_fuente is
  'De dónde salió la cotización. ''manual'' si la escribió la persona.';

comment on column public.ind_liquidacion_repcont.diferencias is
  'Las inconsistencias que el botón marcó contra los datos de rental '
  '(series facturadas que figuran en stock, alquiladas sin días, etc.). Se '
  'guardan para que quede constancia de que se revisaron antes de emitir.';

create index if not exists ind_liq_repcont_mes_idx
  on public.ind_liquidacion_repcont (mes_anio desc);


-- ----------------------------------------------------------------------------
-- 2. RLS
-- ----------------------------------------------------------------------------
-- Leer: cualquiera del sector comercial, igual que el resto de las tablas ind_.
-- Escribir: solo quien figure en ind_editores, la misma función que gobierna
-- la carga de datos de Indicadores. Así emitir una liquidación queda limitado
-- a las mismas personas que pueden tocar los datos, sin crear un permiso nuevo.
--
-- Nunca políticas para anon (regla 7 de CLAUDE.md).
alter table public.ind_liquidacion_repcont enable row level security;

drop policy if exists ind_liq_repcont_sel on public.ind_liquidacion_repcont;
create policy ind_liq_repcont_sel
  on public.ind_liquidacion_repcont
  for select to authenticated
  using (public.tiene_sector('fhcomercial'));

-- Las dos condiciones encadenadas son el mismo patrón que usan las 11 tablas
-- de la migración del 2/11: el sector habilita, ind_editores autoriza a escribir.
drop policy if exists ind_liq_repcont_ins on public.ind_liquidacion_repcont;
create policy ind_liq_repcont_ins
  on public.ind_liquidacion_repcont
  for insert to authenticated
  with check (public.tiene_sector('fhcomercial') and public.ind_puede_editar());

drop policy if exists ind_liq_repcont_upd on public.ind_liquidacion_repcont;
create policy ind_liq_repcont_upd
  on public.ind_liquidacion_repcont
  for update to authenticated
  using (public.tiene_sector('fhcomercial') and public.ind_puede_editar())
  with check (public.tiene_sector('fhcomercial') and public.ind_puede_editar());

-- Borrar no se habilita: una liquidación emitida no se borra, se corrige
-- volviéndola a generar (el unique sobre mes_anio hace que sea un upsert).

revoke all on public.ind_liquidacion_repcont from anon;
grant select, insert, update on public.ind_liquidacion_repcont to authenticated;


-- ----------------------------------------------------------------------------
-- 3. VERIFICACIÓN
-- ----------------------------------------------------------------------------
-- 3.a — la tabla existe, con RLS activo y 3 políticas, ninguna para anon
-- select c.relrowsecurity as rls_activo,
--        (select count(*) from pg_policies p
--          where p.schemaname='public' and p.tablename='ind_liquidacion_repcont') as politicas,
--        (select count(*) from pg_policies p
--          where p.schemaname='public' and p.tablename='ind_liquidacion_repcont'
--            and 'anon' = any(p.roles)) as politicas_anon   -- tiene que dar 0
--   from pg_class c join pg_namespace n on n.oid=c.relnamespace
--  where n.nspname='public' and c.relname='ind_liquidacion_repcont';
--
-- 3.b — anon no debe tener ningún grant
-- select grantee, privilege_type
--   from information_schema.role_table_grants
--  where table_schema='public' and table_name='ind_liquidacion_repcont'
--  order by grantee, privilege_type;


-- ----------------------------------------------------------------------------
-- 4. ROLLBACK
-- ----------------------------------------------------------------------------
-- drop table if exists public.ind_liquidacion_repcont;
