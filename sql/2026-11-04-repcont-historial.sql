-- ============================================================================
-- Liquidación Repcont — carga del historial 2024-2026
--
-- CORRER en el SQL Editor del proyecto del CRM (wcpkpwxhqdcdljfwzcmy),
-- DESPUÉS de 2026-11-03-liquidacion-repcont.sql.
--
-- QUÉ HACE
-- --------
-- Carga en `ind_liquidacion_repcont` las 33 liquidaciones que ya se le pagaron
-- al técnico entre enero de 2024 y septiembre de 2026, sacadas del Excel que
-- se venía llevando a mano. Sin esto la hoja HISTORIAL del primer archivo que
-- genere el botón sale con una sola fila.
--
-- QUÉ REGISTRA, Y QUÉ NO
-- ----------------------
-- Registra lo que se PAGÓ, no lo que correspondía: los días son los que cada
-- hoja declaraba en su total, con su tipo de cambio y su importe en pesos.
-- Eso incluye los meses con diferencias (equipos ya vendidos, la serie
-- duplicada, el total mal sumado de julio 2025). El historial es el registro
-- de lo que pasó; corregirlo acá taparía justamente lo que hay que reclamar.
--
-- `tc_fecha` queda en NULL a propósito: la planilla nunca anotó a qué día
-- correspondía la cotización. Era un número pelado en una celda, sin etiqueta
-- ni fuente. De acá en adelante el botón sí lo guarda.
--
-- `detalle` también queda en NULL: el desglose por serie de esos meses está en
-- el Excel histórico, no en un formato que sirva para reimprimir.
--
-- ES ADITIVO Y NO PISA NADA: `on conflict (mes_anio) do nothing`. Si ya
-- generaste una liquidación desde el botón para alguno de estos meses, la
-- tuya queda. Correr el archivo dos veces no duplica ni cambia nada.
-- ============================================================================

insert into public.ind_liquidacion_repcont
  (mes_anio, dias, contenedores, listados, usd_dia, total_usd,
   tc, tc_fecha, tc_fuente, total_pesos, nota, generado_por)
values
  ('2024-01', 2073, 68, 69, 3.5, 7255.5, 848, null, 'planilla histórica', 6152664, null, 'carga histórica'),
  ('2024-02', 1885, 65, 69, 3.5, 6597.5, 863.5, null, 'planilla histórica', 5696941.25, null, 'carga histórica'),
  ('2024-03', 2015, 65, 69, 3.5, 7052.5, 876, null, 'planilla histórica', 6177990, null, 'carga histórica'),
  ('2024-04', 1846, 65, 69, 3.5, 6461, 897, null, 'planilla histórica', 5795517, null, 'carga histórica'),
  ('2024-05', 1674, 54, 69, 3.5, 5859, 916.5, null, 'planilla histórica', 5369773.5, null, 'carga histórica'),
  ('2024-06', 1640, 55, 69, 3.5, 5740, 933.5, null, 'planilla histórica', 5358290, null, 'carga histórica'),
  ('2024-07', 1698, 55, 69, 3.5, 5943, 951.5, null, 'planilla histórica', 5654764.5, null, 'carga histórica'),
  ('2024-08', 1762, 59, 69, 3.5, 6167, 973, null, 'planilla histórica', 6000491, null, 'carga histórica'),
  ('2024-09', 1770, 59, 69, 3.5, 6195, 995.5, null, 'planilla histórica', 6167122.5, null, 'carga histórica'),
  ('2024-10', 1829, 59, 69, 3.5, 6401.5, 1013, null, 'planilla histórica', 6484719.5, null, 'carga histórica'),
  ('2024-11', 1776, 60, 69, 3.5, 6216, 1023, null, 'planilla histórica', 6358968, null, 'carga histórica'),
  ('2024-12', 1790, 59, 69, 3.5, 6265, 1052.5, null, 'planilla histórica', 6593912.5, null, 'carga histórica'),
  ('2025-01', 1808, 59, 69, 4, 7232, 1076, null, 'planilla histórica', 7781632, null, 'carga histórica'),
  ('2025-02', 1652, 59, 69, 4, 6608, 1084.5, null, 'planilla histórica', 7166376, null, 'carga histórica'),
  ('2025-03', 1829, 59, 69, 4, 7316, 1095.5, null, 'planilla histórica', 8014678, null, 'carga histórica'),
  ('2025-04', 1754, 59, 69, 4, 7016, 1200, null, 'planilla histórica', 8419200, null, 'carga histórica'),
  ('2025-05', 1805, 59, 69, 4, 7220, 1200, null, 'planilla histórica', 8664000, null, 'carga histórica'),
  ('2025-06', 1740, 60, 71, 4, 6960, 1245, null, 'planilla histórica', 8665200, null, 'carga histórica'),
  ('2025-07', 1774, 62, 74, 4, 7096, 1375, null, 'planilla histórica', 9757000, 'La hoja declara 1774 dias pero sus filas suman 1867: la formula del total arranca en F11 en vez de F4 y se saltea el bloque de 20 pies. Se registra lo que se pago (1774). Diferencia a favor de Repcont: 93 dias, 372 USD.', 'carga histórica'),
  ('2025-08', 1922, 62, 74, 4, 7688, 1385, null, 'planilla histórica', 10647880, null, 'carga histórica'),
  ('2025-09', 1815, 62, 74, 4, 7260, 1450, null, 'planilla histórica', 10527000, null, 'carga histórica'),
  ('2025-10', 1875, 61, 74, 4, 7500, 1445, null, 'planilla histórica', 10837500, null, 'carga histórica'),
  ('2025-11', 1790, 63, 74, 4, 7160, 1485, null, 'planilla histórica', 10632600, null, 'carga histórica'),
  ('2025-12', 1947, 67, 74, 4, 7788, 1485, null, 'planilla histórica', 11565180, null, 'carga histórica'),
  ('2026-01', 2049, 67, 75, 4, 8196, 1470, null, 'planilla histórica', 12048120, null, 'carga histórica'),
  ('2026-02', 1820, 65, 75, 4, 7280, 1435, null, 'planilla histórica', 10446800, null, 'carga histórica'),
  ('2026-03', 1935, 66, 75, 4, 7740, 1415, null, 'planilla histórica', 10952100, null, 'carga histórica'),
  ('2026-04', 1859, 62, 75, 4, 7436, 1420, null, 'planilla histórica', 10559120, null, 'carga histórica'),
  ('2026-05', 1736, 56, 75, 4, 6944, 1455, null, 'planilla histórica', 10103520, null, 'carga histórica'),
  ('2026-06', 1680, 56, 75, 4, 6720, 1500, null, 'planilla histórica', 10080000, null, 'carga histórica'),
  ('2026-07', 1718, 56, 75, 4, 6872, 1520, null, 'planilla histórica', 10445440, null, 'carga histórica'),
  ('2026-08', 1743, 57, 75, 4, 6972, 1530, null, 'planilla histórica', 10667160, null, 'carga histórica'),
  ('2026-09', 1710, 57, 75, 4, 6840, 1550, null, 'planilla histórica', 10602000, null, 'carga histórica')
on conflict (mes_anio) do nothing;


-- ----------------------------------------------------------------------------
-- VERIFICACIÓN
-- ----------------------------------------------------------------------------
-- Tiene que dar 33 filas, de 2024-01 a 2026-09, sin huecos:
-- select count(*) as meses, min(mes_anio) as desde, max(mes_anio) as hasta,
--        sum(total_usd) as usd_pagados, sum(total_pesos) as pesos_pagados
--   from public.ind_liquidacion_repcont;
--   -> 33 | 2024-01 | 2026-09 | 227997 | 280393659.75
--
-- Y esta no debe devolver ninguna fila (meses faltantes en la serie):
-- with esperados as (
--   select to_char(d, 'YYYY-MM') as mes_anio
--     from generate_series('2024-01-01'::date, '2026-09-01'::date, '1 month') d)
-- select e.mes_anio from esperados e
--   left join public.ind_liquidacion_repcont l using (mes_anio)
--  where l.mes_anio is null;


-- ----------------------------------------------------------------------------
-- ROLLBACK
-- ----------------------------------------------------------------------------
-- Borra solo lo que cargó este archivo, no lo que generó el botón:
-- delete from public.ind_liquidacion_repcont where generado_por = 'carga histórica';
