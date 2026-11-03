# Integración de Indicadores al CRM — Paso 1: estructura

Acompaña a `2026-11-02-indicadores-tablas.sql`.

Este paso **solo crea estructura**. No migra datos todavía y no toca el
`index.html`. Es deliberadamente aburrido y reversible.

---

## Antes de correr nada: dos hallazgos

### 1. La "foto del mes" está rota en producción

El `create table stock_snapshots` se corrió **en el proyecto Supabase
equivocado** — el de la app de plantas, no el de indicadores
(`zziktktjsnkmtaqwghha`). Se confirmó con tres evidencias:

- `pg_indexes` del proyecto de plantas muestra `stock_snapshots` con
  `stock_snapshots_pkey` e `idx_snap_mes ON (mes_anio)`.
- `information_schema.columns` del proyecto de indicadores devuelve las otras
  10 tablas de la app **más `heartbeat`, pero no `stock_snapshots`**.
- El SQL original, recuperado, tiene como encabezado *"arregla que un mes
  desaparezca al cambiar el calendario"*.

O sea: **el bug que ese SQL venía a arreglar nunca se arregló.** Y falla de una
forma que no se ve:

| dónde | línea | qué pasa |
|---|---|---|
| Dashboard | 1010 | `SNAPSHOTS = (!snap.error && snap.data) ? snap.data : []` — se traga el error y sigue con lista vacía. **No se ve ningún cartel**, simplemente no aparecen los meses cerrados. |
| Cerrar mes | 2570 | `cerrarMes()` sí alerta: `No se pudo guardar la foto del mes: ...` y no cierra. |

**Esta migración lo arregla de paso**, porque crea `ind_stock_snapshots` en el
proyecto correcto con la estructura correcta.

**Qué hacer con la tabla del proyecto de plantas:** si llegó a tener filas, son
datos reales de 4housing viviendo en un proyecto con registro de usuarios
abierto y Stripe. Hay que exportarlos (entran en el paso 2 de migración de
datos) y después borrar la tabla de ahí.

### 2. Las notificaciones son globales — queda pendiente

Hoy `read` es una sola bandera compartida y el botón de limpiar hace
`delete().neq('id',0)`: **borra las notificaciones de todos**. En la app vieja,
con pocos usuarios, era tolerable. En el CRM entran 8+ personas.

Se migra **tal cual está** para no cambiar comportamiento en la mudanza. Si se
quiere por usuario hace falta una tabla puente y va en otra migración. Queda
anotado, no resuelto.

---

## Cómo correrlo

### Paso A — la migración

Pegar `2026-11-02-indicadores-tablas.sql` completo en el SQL Editor de Supabase
del **proyecto del CRM** (`wcpkpwxhqdcdljfwzcmy`) y ejecutar.

Se puede correr más de una vez sin romper nada (está probado).

Van a aparecer varios `NOTICE: policy ... does not exist, skipping`. Es
esperable: son los `drop policy if exists` de la primera pasada.

### Paso B — verificar

Descomentar y correr el bloque 7 del `.sql`. Tiene que dar **11 filas, todas
con `rls_activo = true` y 4 políticas** (salvo `ind_chat_messages`, que tiene 2
a propósito: el chat no se edita ni se borra).

### Paso C — habilitar a quien carga los datos ⚠️

**Sin este paso nadie puede subir el Excel**, salvo quien tenga
`es_direccion = true`.

Es a propósito, y es la única parte donde la migración se aparta de cómo se
comporta hoy la UI del CRM:

- **La UI es permisiva por default**: sin permisos configurados, `comPuedeVer`
  y `comPuedeEditar` dan acceso total (retrocompatible).
- **El RLS es restrictivo por default**: sin permiso explícito no se escribe.

La diferencia es deliberada. El tab "Datos" hace `delete()` de la tabla entera
y reinserta: es la diferencia entre ocultar un botón y proteger los datos. Con
una política `to authenticated using (true)` cualquiera del equipo comercial
borraría todo el histórico de rental con un click.

Descomentar el bloque 5 del `.sql` y correrlo una vez por cada persona que deba
cargar datos, cambiando el mail.

### Paso D — realtime (opcional, decisión de Pablo)

El chat y las notificaciones usan `postgres_changes`. Las tablas nuevas no
entran solas a la publicación. El bloque 6 tiene los dos `alter publication`,
comentados.

Queda comentado porque **modifica un objeto global del proyecto**
(`supabase_realtime`). No rompe nada existente, pero no es para ejecutar de
taquito. Si no se corre, el chat sigue funcionando: deja de actualizarse solo y
hay que recargar.

---

## Qué NO hace esta migración

- **No migra datos.** Las 11 tablas quedan vacías. Eso es el paso 2.
- **No toca el `index.html`.** Eso es el paso 3.
- **No toca el proyecto viejo.** `zziktktjsnkmtaqwghha` sigue intacto y la app
  en Vercel sigue andando igual. El link del menú del CRM no se cambia hasta
  que la vista nativa esté verificada.
- **No crea foreign keys.** A propósito, igual que producción. En particular
  **no** va `ind_stock_movimientos.serie → ind_stock_items.serie`: la
  importación de stock borra `ind_stock_items` entero pero conserva los
  movimientos cargados a mano. Con FK ese borrado falla; con `ON DELETE
  CASCADE` se lleva puesto todo el historial.

---

## Dos bugs del código que conviene arreglar en el paso 3

No son de esta migración, pero si el código se copia tal cual se heredan:

1. **`loadData()` pagina `rental_data` con `.range()` sin `.order()`** (línea
   1000). PostgREST lo traduce a `LIMIT/OFFSET` sin `ORDER BY`, y Postgres no
   garantiza el mismo orden entre páginas: arriba de 1000 filas se pueden
   repetir o perder registros. El patrón establecido del CRM es
   `SB._fetchAll()`, que ya lo resuelve.

2. **`loadChat()` trae los 50 mensajes más viejos** (línea 1301):
   `.order('created_at', {ascending:true}).limit(50)`. Cuando el chat pase de
   50 mensajes, los nuevos dejan de aparecer salvo los que llegan por realtime
   en esa sesión.

---

## Un bloqueante del CRM a tener presente en el paso 3

En la línea 695 de `index.html`, `sbFetch` **tira error en cualquier método que
no sea GET/HEAD** si `comEdicionActual()` da `false` para la vista actual.

Si la vista `indicadores` no queda registrada como editable en
`comPuedeEditar`, **todos los inserts y updates de estas 11 tablas van a
rebotar del lado del cliente**, aunque el RLS esté perfecto. Es el tipo de cosa
que hace perder una tarde culpando a la base.

---

## Validación hecha

La migración se corrió contra un PostgreSQL 16.15 limpio, con una mímica de
`auth.uid()`, `auth.jwt()`, `perfiles`, `perfiles_sector` y `tiene_sector()`:

| chequeo | resultado |
|---|---|
| tablas creadas | 11 / 11 |
| con RLS activo | 11 / 11 |
| políticas | 42 |
| índices | 24 |
| grants a `anon` | **0** |
| grants a `authenticated` | 44 |
| correrla dos veces seguidas | sin errores |

Y el RLS se probó con tres perfiles reales, no solo compilando:

| | Dirección | Comercial sin permiso | Comercial con permiso |
|---|---|---|---|
| `ind_puede_editar()` | `true` | `false` | `true` |
| insert en `ind_rental_data` | ✅ | ❌ bloqueado | ✅ |
| delete | ✅ | ❌ 0 filas | ✅ |
| leer | ✅ | ✅ | ✅ |
| chat con su propio mail | ✅ | ✅ | ✅ |
| chat haciéndose pasar por otro | ❌ | ❌ | ❌ |
