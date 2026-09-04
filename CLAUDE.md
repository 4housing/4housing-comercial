# 4housing-comercial — Contexto del proyecto

Este archivo es la memoria persistente del proyecto para Claude Code. Cualquier
instancia (la de Pablo o la de Ignacio) debe leer esto antes de tocar código.

## Qué es esto

CRM comercial interno de **4housing (4COMMERCE SRL)**, empresa de construcción
modular en Buenos Aires, Argentina. Cubre prospección, oportunidades, cotizaciones,
cobranzas, facturación (integración con ERP) y pipeline, para dos unidades de
negocio: **Rental** (alquiler de módulos) y **Ventas** (venta única).

Reemplaza procesos manuales y se conecta con el ERP **Tango Delta 5 (Axoft)**.

## Personas y roles

- **Pablo** — co-dueño de 4housing, builder y mantenedor principal de la app.
  Decide sobre cambios estructurales. Prefiere entender el "por qué" antes de
  que se implemente algo grande. Comunica en español rioplatense (voseo), directo
  y sin relleno.
- **Ignacio Sánchez Moser** — también va a operar Claude Code sobre este mismo repo.
- **Equipo comercial:** Ignacio Sánchez Moser, Victoria López Aybar, Pablo Spinetto,
  Leandro Seoane, Héctor Bermúdez.
- **Equipo de cobranzas (Gerencia de Administración y Finanzas):** Santiago Cittar,
  Alexis Carranza, Micaela Seoane.

## Stack

- **Frontend:** un solo archivo `index.html` (vanilla JS/HTML/CSS, sin frameworks).
- **Hosting:** GitHub Pages, org `4housing`, repo `4housing-comercial`.
  URL pública: https://4housing.github.io/4housing-comercial/
  (El repo se mudó de la org `labo-comercial`; el dominio viejo puede servir una
  versión desactualizada. Si un cambio "no aparece", chequear la URL además de
  la caché del navegador.)
- **Backend:** Supabase (REST API + Edge Functions + RLS).
  Project ID: `wcpkpwxhqdcdljfwzcmy`
- **Auth — OJO, hay DOS caminos distintos y conviene no confundirlos:**
  1. **Login de la app: Supabase Auth con proveedor Azure**
     (`sbClient.auth.signInWithOAuth({provider:'azure'})`, scopes
     `openid profile email`). De acá sale `AUTH_USER`, y **cada llamada REST a
     Supabase viaja con el JWT del usuario**, así que las políticas RLS
     distinguen usuarios (ver `public.tiene_sector('fhcomercial')`, que existe
     en la base pero NO está en el repo).
  2. **MSAL v3.7.0 embebido (`msal-browser.min.js`): solo para Microsoft
     Graph**, con una app registrada aparte (`f47da2c5-7922-4e2f-8648-51b8486552fb`).
     Lo usan SharePoint (`Files.ReadWrite.All`, `Sites.ReadWrite.All`) y el
     calendario de la Agenda (`Calendars.Read`). El token se pide con
     `_spToken(interactivo, scopes)`; **solo se cachea en `_spTok` cuando son los
     scopes de SharePoint** — meter ahí un token de otro scope rompe SharePoint.
  Client ID del login: `66a475e3-745f-4931-8085-ee71a0b6d6fe`
  Tenant ID: `c408b6d8-ae0b-4d30-9056-da52e18116c4`
- **ERP:** Tango Delta 5 (Axoft), servidor local accesible desde internet.
  API usa headers `ApiAuthorization` (token) y `Company: 3`.
- **Notificaciones:** Power Automate (webhook Teams firmado) + Supabase Edge
  Function (Microsoft Graph `Mail.Send`).
- **Mail pipeline:** Power Automate + Supabase Edge Function + Claude API para
  clasificar mails entrantes a `info@4housing.com.ar`.
- **Diseño:** paleta oliva/crema (`#9db98b`, `#5f7a4e`, `#37432c`, `#f4f2ea`),
  tipografías Archivo/Quicksand, sello ISO/TÜV NORD.

## Reglas de trabajo — NO NEGOCIABLES

1. **SQL nunca se ejecuta automáticamente.** Toda migración se entrega como
   archivo `.sql` separado para que Pablo lo corra manualmente en el SQL Editor
   de Supabase. Claude Code no tiene ni debe usar credenciales de escritura
   directa a la base de producción salvo que Pablo lo autorice explícitamente
   para una tarea puntual.
2. **Orden de deploy:** primero el SQL (si agrega columnas/tablas), después el
   deploy del HTML. Nunca al revés.
3. **El token de la API de Tango NUNCA va en `index.html`** (es público en
   GitHub Pages). Todo llamado a Tango pasa por Supabase Edge Functions.
4. **Cambios incrementales y aditivos:** no reescribir funciones existentes
   salvo necesidad real. Cada feature se entrega como pieza separada y testeable.
5. **Todo cambio en JS se valida con `node --check`** antes de darlo por
   terminado.
6. **Decisiones estructurales se cierran antes de escribir código.** Si hay
   una decisión de diseño/arquitectura pendiente, se discute y se cierra
   primero con Pablo (y con Ignacio si corresponde).
7. **RLS por defecto en `authenticated`, nunca en `anon`.** Crear políticas
   permisivas para `anon` "temporalmente" es el error recurrente que ya causó
   trabajo de hardening. Toda tabla nueva arranca con políticas solo para
   `authenticated`.
8. **Nada de credenciales sensibles hardcodeadas más allá de lo ya aceptado**
   (la anon key de Supabase es pública por diseño; el token de Tango NO).
9. **No romper nada de lo que ya funciona. Es la regla que manda sobre todas
   las demás.** Llegar al estado actual costó mucho trabajo; una feature nueva
   nunca justifica degradar una que ya anda. En la práctica:
   - **Preferir agregar antes que modificar.** Una vista nueva, una función
     nueva, una tabla nueva son de bajo riesgo. Tocar una función que ya usa
     otra parte de la app es de alto riesgo, aunque el cambio parezca trivial.
   - **Si hay que tocar código compartido, buscar primero TODOS los usos**
     (`grep`) y entender qué depende de él. Ejemplo real: `_spToken()` cacheaba
     el token en la global `_spTok`; agregarle el calendario sin cuidado habría
     hecho fallar con 403 las carpetas de SharePoint de Ventas, que ya andaban.
   - **Probar lo que se tocó, no solo lo que se agregó.** `node --check` valida
     sintaxis, no comportamiento. Si el cambio afecta algo existente, hay que
     verificar que eso existente siga funcionando.
   - **Un PR por feature, chico y reversible.** Si algo sale mal en producción,
     tiene que poder revertirse solo, sin arrastrar lo demás.
   - **Ante la duda, preguntar antes de tocar.** Es preferible una consulta de
     más que una regresión.

## Flujo de trabajo en git (dos personas, mismo repo)

- Evitar que ambos commiteen directo a `main` en simultáneo sobre `index.html`
  (archivo único y grande → conflictos difíciles de mergear).
- Usar ramas por feature + Pull Request, o coordinarse antes de tocar el archivo
  si se prefiere simplicidad.
- Antes de empezar una sesión de Claude Code, hacer `git pull` para no pisar
  cambios del otro.
- Commits chicos y descriptivos, en español, describiendo qué feature/fix es.

## Patrones técnicos establecidos

- **Formato de referencia unificado:** `OE-{R|V}-{número}-{versión}` con
  contadores independientes por unidad de negocio vía RPC `next_seq_un(p_unidad)`.
- **Paginación:** usar siempre `SB._fetchAll()` para cualquier query que pueda
  superar 1000 filas (cap por defecto de PostgREST).
- **Tabla `contador`:** tiene constraint `contador_unica_fila` (una sola fila).
  Los contadores son columnas de esa fila única, actualizados con
  `FOR UPDATE` row locking dentro de las RPCs.
- **CSS de tablas:** usar `vertical-align:top` + `word-break:break-word` +
  `td.nowrap` selectivo para celdas de contenido corto. NO usar
  `white-space:nowrap` global (rompe tablas anchas) ni `table-layout:fixed`
  con ellipsis (corta contenido).
- **Power Automate:** los triggers HTTP del tenant requieren OAuth; se usa la
  URL firmada del Teams Workflow (`COBRANZA_WEBHOOK_URL`), que acepta POST
  anónimo sin problemas de CORS.

## Estado actual (features completadas)

- **Agenda** (menú Comercial): vista de lista y calendario mensual que unifica
  vencimientos. Junta cuatro fuentes: tareas propias (tabla `agenda_tareas`,
  se cargan a mano desde el botón o clickeando un día), próximo paso y fecha
  límite de oportunidades, validez de ofertas enviadas, y las reuniones de
  Outlook/Teams vía Graph (opt-in, con botón "Unirse"). Filtro "Mis pendientes"
  y cartel de recordatorio al abrir (1 vez por día, solo lo vencido/de hoy).
  - El usuario se identifica comparando el nombre de Azure AD contra
    `COMERCIALES` **ignorando tildes** (Azure devuelve "Ignacio Sanchez Moser",
    la lista tiene "Ignacio Sánchez Moser"), con respaldo por el usuario del
    mail. Si no matchea, no adivina: muestra todo el equipo y avisa.
  - "Mis pendientes" es comodidad visual, **no** barrera de seguridad.
- **Duplicar cotización**: copia una OE en una oferta nueva (número propio,
  versión 01). Distinto de "Nueva versión". No hereda fecha de envío, carpeta
  de SharePoint ni la oportunidad de origen (copiar `fromOppId` le robaría la
  OP a la original al guardar).
- **Impresión**: en `@media print` hay una regla que oculta **todo** hijo directo
  de `<body>` salvo `.app`, `#catPrintLayer` y `#edcPrintLayer` (era la única
  forma de tapar el botón flotante de `/portal/nav.js`, que vive en un shadow
  DOM). Trampa a tener presente: **si algún día se agrega un elemento nuevo a
  nivel de `<body>` que SÍ deba imprimirse, hay que sumarlo a esa lista** o no
  va a salir en el PDF, sin ningún error visible.
- Pipeline Kanban, log de actividades con próximo paso, audit trail parcial
  (tabla `audit_log`, `fn_audit()`). Triggers confirmados funcionando (con
  registros reales) en `oportunidades` y `cotizaciones`. Los triggers en
  `pedidos` y `facturas` NO están confirmados: `audit_log` no tiene ningún
  registro de esas dos tablas — pendiente verificar si los triggers existen
  y están disparando (investigación directa 2/7/2026).
- Módulo de cotizaciones de Ventas (sin plazo/período, columna `unidad_negocio`
  en `cotizaciones`).
- Módulo de Cobranzas: condiciones de pago, adicionales, sistema de ageing,
  semáforo, notificaciones Teams + mail.
- Circuito de facturación: tablas `pedidos` y `facturas`, arquitectura de
  integración con Tango vía Edge Functions diseñada. Las tablas maestras
  (`tango_articulos`, `tango_clientes`, `tango_vendedores`, `tango_depositos`,
  `tango_config`) NUNCA se crearon en producción (confirmado por investigación
  directa el 2/7/2026: no existen en el esquema, sin rastro en `audit_log`,
  sin referencias en `index.html` ni en migraciones del repo). La importación
  real de estas tablas sigue pendiente.
- Hardening de seguridad: políticas `anon` permisivas eliminadas de `catalogo`,
  `clientes`, `contador`, `cotizaciones`; `execute` de `next_seq()` revocado a `anon`.
- Consistencia visual entre dashboards Rental y Ventas.

## Pendientes conocidos

- `COD_GVA23` de Victoria López Aybar en Tango: falta dar de alta como vendedora.
- Config `lista_precios_dolar_billete`: falta completar el número de lista de Tango.
- **Pedido draft UI** dentro de cada cobranza — próximo paso grande, requiere
  tocar el `index.html` actual completo.
- Push de pedidos a Tango vía API (`POST Api/Create/{process}`) una vez exista
  la UI. Mientras tanto, importación por Excel de facturas sigue siendo el
  workaround (la API de lectura de Tango está "próximamente").
- Talonarios: 56 (PEDIDOS ALQUILERES) para Rental, 57 (PEDIDOS VENTAS) para Ventas.
- Circuito de aprobación de adicionales post-venta (re-cotización) — no
  implementado todavía.
- Compartimentalización row-level entre usuarios internos (hoy todos los
  usuarios autenticados ven todos los datos) — consideración de seguridad futura.
- Existe una tabla `contadores` (plural) además de `contador` (singular), con
  estructura distinta (`nombre` + `seq`, 2 filas, sin foreign keys). No está
  confirmado si las RPCs `next_seq()` / `next_seq_un()` la usan — hay que
  revisar el código de esas funciones antes de tocar o eliminar cualquiera de
  las dos tablas.

## Cómo entregar trabajo

- **Archivos HTML/JS:** entregar el archivo completo actualizado o instrucciones
  claras de qué reemplazar, ya validado con `node --check`.
- **Migraciones SQL:** archivo `.sql` separado (o `INSTRUCCIONES-SQL.md` si hace
  falta explicar pasos), nunca ejecutado directo contra producción sin que
  Pablo lo revise y corra él mismo.
- **Si algo no sale como se esperaba:** diagnosticar con evidencia (grep/diff
  contra el archivo original), no adivinar.
- Asumir que el archivo entregado se despliega tal cual, sin ediciones manuales
  intermedias — es una base confiable para diagnosticar síntomas.
