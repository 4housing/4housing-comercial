-- 2026-09-04-agenda-tareas.sql
-- Tareas propias de la Agenda: lo que el equipo comercial carga a mano.
--
-- La Agenda (fase 1) solo LEÍA vencimientos que ya existían en otras tablas
-- (próximos pasos de oportunidades, fechas límite, validez de ofertas). Esta
-- tabla agrega lo que faltaba: poder agendar una tarea propia, con su fecha,
-- su hora y la persona a la que le toca.
--
-- Correr en el SQL Editor de Supabase (proyecto wcpkpwxhqdcdljfwzcmy).
-- Es idempotente: se puede correr más de una vez sin romper nada.
--
-- ORDEN DE DEPLOY: primero este SQL, después el index.html.
-- Igual la app está preparada para el orden inverso: si la tabla todavía no
-- existe, la Agenda sigue funcionando y solo no muestra tareas propias (la
-- carga usa .catch(()=>[]), como el resto de las colecciones opcionales).

create table if not exists public.agenda_tareas (
  id          uuid        primary key default gen_random_uuid(),
  titulo      text        not null,
  detalle     text,
  fecha       date        not null,                     -- día en que hay que hacerla
  hora        text,                                     -- 'HH:MM', opcional
  asignado_a  text,                                     -- nombre del comercial (misma lista que usa el CRM)
  estado      text        not null default 'pendiente', -- 'pendiente' | 'hecha'
  prioridad   text        not null default 'media',     -- 'alta' | 'media' | 'baja'
  creado_por  text,                                     -- email de quien la creó
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

comment on table public.agenda_tareas is
  'Tareas que el equipo comercial agenda a mano desde la vista Agenda. '
  'Los vencimientos derivados (próximo paso de una oportunidad, validez de una '
  'oferta) NO viven acá: se calculan al vuelo desde sus propias tablas.';

comment on column public.agenda_tareas.asignado_a is
  'Nombre del comercial, tal como figura en la lista COMERCIALES del index.html. '
  'Se guarda el nombre y no el email porque es lo que ya usan oportunidades y '
  'cotizaciones para asignar responsable; así el filtro "Mis pendientes" compara '
  'contra un solo criterio en todo el CRM.';

-- La agenda siempre se consulta por día y por persona.
create index if not exists agenda_tareas_fecha_idx      on public.agenda_tareas (fecha);
create index if not exists agenda_tareas_asignado_idx   on public.agenda_tareas (asignado_a);

alter table public.agenda_tareas enable row level security;

-- Mismo criterio que el resto del CRM endurecido: solo el sector fhcomercial,
-- y solo para authenticated (nunca anon).
drop policy if exists agenda_tareas_fhcomercial on public.agenda_tareas;
create policy agenda_tareas_fhcomercial on public.agenda_tareas
  for all to authenticated
  using (public.tiene_sector('fhcomercial'))
  with check (public.tiene_sector('fhcomercial'));

-- Nota sobre visibilidad: hoy cualquier usuario de fhcomercial ve y edita las
-- tareas de todos, igual que pasa con oportunidades y cotizaciones. El filtro
-- "Mis pendientes" de la Agenda es una comodidad de la interfaz, NO una barrera
-- de seguridad. Restringir la edición a la persona asignada sería un cambio de
-- criterio para todo el CRM, no solo para esta tabla.
