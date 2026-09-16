// =====================================================================
// 4housing — Edge Function: clasificar-mail (v8)
// Cambios respecto a la v7:
//  - LEADS ENTRANTES A PROSPECCIÓN. Los mails que genera la web
//    (formulario de contacto y botón de WhatsApp, remitente noreply@,
//    asunto "Contacto web ..." / "Contacto WhatsApp ...") tienen formato
//    FIJO. Además de la oportunidad de siempre, ahora se parsean de forma
//    DETERMINÍSTICA (sin llamar a Claude: cero tokens extra) y se registra
//    el contacto como PROSPECTO en `empresas_prospecto` + `prospectos`,
//    con la vía de contacto (whatsapp | formulario_web) y el motivo, y
//    vinculado a la oportunidad que se creó. La clasificación por Claude y
//    la creación de la oportunidad NO cambian en nada.
//  - El insert del prospecto va DENTRO del bloque !esSpam, después de crear
//    la oportunidad, y queda protegido por el mismo dedup por message_id.
//
// Cambios de la v7 respecto a la v6:
//  - FILTRO ANTI-BUCLE. Se detectó un bucle de retroalimentación: el
//    propio aviso "[Alerta comercial]" que genera el sistema volvía a
//    caer en info@4housing.com.ar, el pipeline lo tomaba como un mail
//    nuevo, lo clasificaba como Licitación pública, creaba otra opp y
//    mandaba otro aviso -> loop cada ~75s que no paraba solo.
//    Ahora, ANTES de clasificar, la función descarta cualquier mail que
//    sea una alerta interna del propio sistema (por asunto y/o remitente),
//    dejando rastro en mails_entrantes con estado "descartado_autoalerta"
//    pero SIN crear oportunidad, actividad ni disparar nada.
//    Los marcadores están en constantes arriba para ajustarlos fácil.
//  - Se conserva todo lo de la v6 (dedup por message_id + índice UNIQUE).
//
// Secrets: ANTHROPIC_API_KEY, SERVICE_ROLE_KEY
// Archivo: supabase/functions/clasificar-mail/index.ts
// =====================================================================

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const ANTHROPIC_API_KEY = Deno.env.get("ANTHROPIC_API_KEY");
const SERVICE_ROLE_KEY  = Deno.env.get("SERVICE_ROLE_KEY");
const SB_URL = Deno.env.get("SUPABASE_URL");

// Tope de caracteres del cuerpo que se le manda a Claude para clasificar.
// ~15.000 caracteres son ~4.000 tokens: de sobra para tipo/prioridad/unidad
// de negocio/resumen, incluso si el mail trae un pliego larguísimo pegado.
const CUERPO_MAX_CHARS = 15000;

// ── Anti-bucle: marcadores que identifican los avisos que genera el
// PROPIO sistema (no mails de clientes). Si un mail entrante coincide con
// alguno de estos, se descarta antes de clasificar para que el sistema
// nunca se auto-alimente. Ajustá acá si cambiás el texto de los avisos.
//   - ASUNTO: cualquier texto (case-insensitive) que aparezca en el asunto
//     de las alertas internas. "[Alerta comercial]" es la firma actual.
//   - REMITENTES: direcciones desde las que salen los avisos del sistema.
//     Si alguna vez el aviso llega "de parte de" una de estas, se descarta.
const AUTOALERTA_ASUNTO_MARCADORES = ["[alerta comercial]"];
const AUTOALERTA_REMITENTES = ["info@4housing.com.ar"];

const SYSTEM_PROMPT = `Sos un clasificador de correos para el equipo comercial de 4housing, una empresa de construcción modular en Argentina. Recibís el contenido de un mail (remitente, asunto y cuerpo) que llegó a la casilla compartida info@4housing.com.ar, donde caen licitaciones, pedidos de cotización, notificaciones y spam.

Tu tarea es clasificar el mail y extraer información, devolviendo SOLO un objeto JSON válido, sin texto adicional, sin markdown, sin explicaciones.

El JSON debe tener exactamente esta estructura:
{
  "tipo": "<una de: Licitación pública | Licitación privada | Notificación de proceso | Pedido de cotización | Spam>",
  "prioridad": "<una de: urgente | alta | media | baja>",
  "unidad_negocio": "<una de: rental | ventas | ambas>",
  "organismo": "<nombre del organismo, repartición o empresa que envía o convoca; null si no se identifica>",
  "cliente": "<nombre de la persona o empresa de contacto; puede coincidir con organismo; null si no se identifica>",
  "fecha_limite": "<fecha de cierre/vencimiento en formato YYYY-MM-DD si el mail la menciona; null si no hay>",
  "resumen": "<una o dos líneas en español neutro explicando qué pide o informa el mail>"
}

Reglas de prioridad (asignala según el tipo):
- Licitación pública -> "urgente"
- Licitación privada -> "urgente"
- Pedido de cotización -> "alta"
- Notificación de proceso -> "media"
- Spam -> "baja"

Criterios de cada tipo:
- "Licitación pública": convocatoria de un organismo estatal (municipio, provincia, ministerio, empresa pública) a presentar ofertas.
- "Licitación privada": convocatoria de una empresa privada a cotizar un proyecto, concurso de precios privado.
- "Pedido de cotización": alguien pide precio por módulos, alquiler, servicios, sin proceso licitatorio formal.
- "Notificación de proceso": avisos sobre un proceso ya en curso (aclaraciones, prórrogas, adjudicaciones, circulares), no una convocatoria nueva.
- "Spam": publicidad, newsletters masivos, phishing, promociones, nada relevante al negocio.

Reglas de unidad de negocio (campo "unidad_negocio"):
4housing tiene dos unidades: RENTAL (alquiler de módulos) y VENTAS (venta de módulos). Clasificá según las señales del mail:
- "rental": el mail habla de ALQUILER, renta, locación, "por cuánto tiempo lo necesitan", "período de alquiler", "alquilar", obradores temporales, leasing operativo.
- "ventas": el mail habla de COMPRA, "adquirir", "precio de venta", "comprar el módulo", "cotización de venta", adquisición definitiva.
- "ambas": el mail pide EXPLÍCITAMENTE las dos opciones (cotizar tanto alquiler como compra), o menciona que quiere comparar alquilar vs comprar.
- Si NO hay señales claras de alquiler ni de venta (el mail no especifica), usá "rental" por defecto. Rental es la unidad principal del negocio. NO adivines ventas sin señales explícitas de compra.

IMPORTANTE — Mails internos y reenvíos:
- El remitente puede ser una dirección interna (@4housing.com.ar). NO trates un mail como Spam solo por venir de una dirección interna. Un compañero del equipo puede reenviar a info@ una licitación o un pedido importante.
- Si el mail es un REENVÍO (FWD, RV, "reenviado por", o incluye un mensaje original citado abajo), clasificá según el CONTENIDO del mensaje reenviado (la licitación, el pedido o la notificación que está adentro), NO según quién lo reenvía.
- En esos casos, extraé el organismo/empresa y el contacto del mensaje original reenviado, no del compañero que reenvía.
- Solo usá "Spam" para correo verdaderamente irrelevante (publicidad, newsletters, phishing), venga de afuera o de adentro.

Si dudás entre dos categorías, elegí la de mayor prioridad. Respondé SOLO el JSON.`;

// ── Parseo DETERMINÍSTICO de los mails que genera la web (sin Claude) ──
// El formulario de contacto y el botón de WhatsApp mandan mails con formato
// fijo desde noreply@. Detectamos la vía por el asunto/cuerpo y extraemos los
// datos con regex. Devuelve null si el mail NO es uno de estos (entonces no
// se crea prospecto y todo sigue igual que siempre).
function parseContactoWeb(asunto: string, cuerpo: string): {
  via: "whatsapp" | "formulario_web";
  nombre: string | null;
  email: string | null;
  telefono: string | null;
  motivo: string | null;
  mensaje: string | null;
} | null {
  const asuntoL = (asunto || "").toLowerCase();
  const cuerpoL = (cuerpo || "").toLowerCase();
  let via: "whatsapp" | "formulario_web" | null = null;
  if (asuntoL.includes("contacto whatsapp") || cuerpoL.includes("contacto whatsapp")) via = "whatsapp";
  else if (asuntoL.includes("contacto web") || cuerpoL.includes("contacto web")) via = "formulario_web";
  if (!via) return null;

  // El cuerpo puede venir en HTML: sacamos etiquetas, decodificamos las
  // entidades más comunes (incluidos los acentos, p. ej. Tel&eacute;fono) y
  // normalizamos espacios para poder anclar cada campo a la etiqueta siguiente.
  const decode = (s: string): string =>
    s
      .replace(/&nbsp;/gi, " ")
      .replace(/&aacute;/g, "á").replace(/&Aacute;/g, "Á")
      .replace(/&eacute;/g, "é").replace(/&Eacute;/g, "É")
      .replace(/&iacute;/g, "í").replace(/&Iacute;/g, "Í")
      .replace(/&oacute;/g, "ó").replace(/&Oacute;/g, "Ó")
      .replace(/&uacute;/g, "ú").replace(/&Uacute;/g, "Ú")
      .replace(/&ntilde;/g, "ñ").replace(/&Ntilde;/g, "Ñ")
      .replace(/&#(\d+);/g, (_m, n) => String.fromCharCode(Number(n)))
      .replace(/&amp;/gi, "&");
  const texto = decode((cuerpo || "").replace(/<[^>]+>/g, " "))
    .replace(/\s+/g, " ")
    .trim();

  const grab = (re: RegExp): string | null => {
    const m = texto.match(re);
    return m && m[1] ? m[1].trim() : null;
  };

  // Fallback por asunto: "Contacto web - <motivo> - <nombre>"
  const partesAsunto = (asunto || "").split(" - ").map((s) => s.trim());
  const motivoAsunto = partesAsunto.length >= 3 ? partesAsunto[1] : null;
  const nombreAsunto = partesAsunto.length >= 3 ? partesAsunto.slice(2).join(" - ") : null;

  const nombre = grab(/Nombre:\s*(.+?)\s*(?:Email:|Tel[eé]fono:|Motivo|Mensaje:|Enviado desde|$)/i) || nombreAsunto;
  const email = grab(/Email:\s*([^\s]+@[^\s]+)/i);
  const telefono = grab(/Tel[eé]fono:\s*([+\d][\d\s()\-]{4,})/i);
  const motivo = grab(/Motivo de la consulta:\s*(.+?)\s*(?:Mensaje:|Enviado desde|$)/i) || motivoAsunto;
  const mensaje = grab(/Mensaje:\s*(.+?)\s*(?:Enviado desde|$)/i);

  return { via, nombre, email, telefono, motivo, mensaje };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers": "authorization, content-type",
        "Access-Control-Allow-Methods": "POST, OPTIONS",
      },
    });
  }

  try {
    if (!ANTHROPIC_API_KEY) return json({ error: "Falta ANTHROPIC_API_KEY" }, 500);
    if (!SERVICE_ROLE_KEY)  return json({ error: "Falta SERVICE_ROLE_KEY" }, 500);

    const body = await req.json();
    const { remitente, asunto, cuerpo, message_id, recibido_at } = body;

    if (!asunto && !cuerpo) {
      return json({ error: "Faltan datos del mail (asunto y/o cuerpo)" }, 400);
    }

    // ── FILTRO ANTI-BUCLE: descartar los avisos que genera el propio
    // sistema. Sin esto, el aviso "[Alerta comercial]" vuelve a caer en la
    // casilla, se clasifica como licitación y dispara otro aviso -> loop.
    const asuntoLower = (asunto || "").toLowerCase();
    const remitenteLower = (remitente || "").toLowerCase();
    const esAutoAlerta =
      AUTOALERTA_ASUNTO_MARCADORES.some((m) => asuntoLower.includes(m)) ||
      AUTOALERTA_REMITENTES.some((r) => remitenteLower.includes(r));

    if (esAutoAlerta) {
      // Dejamos rastro (para poder auditarlo) pero NO clasificamos, NO
      // creamos oportunidad ni actividad, y NO disparamos ningún aviso.
      const sbSkip = createClient(SB_URL!, SERVICE_ROLE_KEY!);
      await sbSkip.from("mails_entrantes").upsert({
        message_id: message_id || null,
        remitente: remitente || null,
        asunto: asunto || null,
        cuerpo: cuerpo || null,
        recibido_at: recibido_at || new Date().toISOString(),
        clasificacion: null,
        cliente_id: null,
        oportunidad_id: null,
        estado_procesamiento: "descartado_autoalerta",
        alertado: false,
      }, { onConflict: "message_id", ignoreDuplicates: true });
      return json({
        ok: true,
        descartado: true,
        motivo: "auto-alerta del sistema (anti-bucle); no se procesa.",
      });
    }

    // ── DEDUP (A): si este message_id ya fue procesado, no repetir nada. ──
    // Power Automate puede re-disparar el mismo mail (timeout + retry, o
    // más de un flujo escuchando la casilla). Sin esto, cada re-disparo
    // crea otra oportunidad + otra actividad + otro aviso.
    const sbDedup = createClient(SB_URL!, SERVICE_ROLE_KEY!);
    if (message_id) {
      const { data: yaExiste } = await sbDedup
        .from("mails_entrantes")
        .select("id, oportunidad_id, cliente_id, clasificacion")
        .eq("message_id", message_id)
        .limit(1);
      if (yaExiste && yaExiste.length > 0) {
        const prev = yaExiste[0];
        return json({
          ok: true,
          duplicado: true,
          mensaje: "Mail ya procesado; se ignora el re-disparo.",
          clasificacion: prev.clasificacion,
          cliente_id: prev.cliente_id,
          oportunidad_id: prev.oportunidad_id,
        });
      }
    }

    // Truncamos SOLO lo que se le manda a Claude. El "cuerpo" original
    // completo se sigue guardando sin tocar en mails_entrantes más abajo.
    const cuerpoTruncado = cuerpo && cuerpo.length > CUERPO_MAX_CHARS
      ? cuerpo.slice(0, CUERPO_MAX_CHARS) + "\n\n[...cuerpo truncado por longitud, se guardó completo en la base...]"
      : cuerpo;

    const mailTexto =
      `Remitente: ${remitente || "(desconocido)"}\n` +
      `Asunto: ${asunto || "(sin asunto)"}\n\n` +
      `Cuerpo:\n${cuerpoTruncado || "(sin cuerpo)"}`;

    const resp = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "x-api-key": ANTHROPIC_API_KEY,
        "anthropic-version": "2023-06-01",
        "content-type": "application/json",
      },
      body: JSON.stringify({
        model: "claude-sonnet-4-6",
        max_tokens: 1024,
        system: SYSTEM_PROMPT,
        messages: [{ role: "user", content: mailTexto }],
      }),
    });

    if (!resp.ok) {
      const errTxt = await resp.text().catch(() => "");
      return json({ error: "Error de la API de Anthropic", detalle: errTxt }, 502);
    }

    const data = await resp.json();
    const texto = (data.content || [])
      .map((b: any) => (b.type === "text" ? b.text : ""))
      .join("").trim();

    let c: any;
    try {
      c = JSON.parse(texto.replace(/```json|```/g, "").trim());
    } catch (e) {
      return json({ error: "Claude no devolvió JSON válido", crudo: texto }, 502);
    }

    const sb = createClient(SB_URL!, SERVICE_ROLE_KEY!);

    const esSpam = (c.tipo || "").toLowerCase() === "spam";
    let cliente_id: string | null = null;
    let oportunidad_id: string | null = null;

    if (!esSpam) {
      const nombreCliente = c.organismo || c.cliente;
      if (nombreCliente) {
        const { data: encontrados } = await sb
          .from("clientes")
          .select("id")
          .ilike("nombre", nombreCliente)
          .limit(1);

        if (encontrados && encontrados.length > 0) {
          cliente_id = encontrados[0].id;
        } else {
          const { data: nuevo } = await sb
            .from("clientes")
            .insert({ nombre: nombreCliente, atencion: c.cliente || null })
            .select("id")
            .single();
          cliente_id = nuevo?.id ?? null;
        }
      }

      // Unidad de negocio: rental | ventas | ambas. Default seguro = rental.
      const unidad = ["rental", "ventas", "ambas"].includes((c.unidad_negocio || "").toLowerCase())
        ? c.unidad_negocio.toLowerCase()
        : "rental";

      const { data: opp } = await sb
        .from("oportunidades")
        .insert({
          cliente_id,
          unidad_negocio: unidad,
          tipo: c.tipo,
          titulo: asunto || c.resumen?.slice(0, 80),
          estado: "nuevo",
          prioridad: c.prioridad || "media",
          fecha_limite: c.fecha_limite || null,
          notas: c.resumen || null,
        })
        .select("id")
        .single();
      oportunidad_id = opp?.id ?? null;

      if (oportunidad_id) {
        await sb.from("actividades").insert({
          oportunidad_id,
          cliente_id,
          unidad_negocio: unidad,
          tipo: "mail",
          descripcion: `Mail entrante: ${asunto || "(sin asunto)"} — ${c.resumen || ""}`,
          comercial: null,
        });
      }

      // ── LEAD ENTRANTE → PROSPECCIÓN ──────────────────────────────────
      // Si el mail es del formulario web o del botón de WhatsApp (formato
      // fijo), además de la oportunidad registramos el contacto como
      // prospecto, con la vía y el motivo, y lo vinculamos a la opp. El
      // parseo es determinístico (regex): no se llama a Claude, cero costo.
      const contacto = parseContactoWeb(asunto || "", cuerpo || "");
      if (contacto) {
        const nombreLead = (contacto.nombre || nombreCliente || "Contacto sin nombre").trim();

        // Empresa: reusar si ya existe una con ese nombre; si no, crearla.
        let empresa_id: string | null = null;
        const { data: empEnc } = await sb
          .from("empresas_prospecto")
          .select("id")
          .ilike("nombre", nombreLead)
          .limit(1);
        if (empEnc && empEnc.length > 0) {
          empresa_id = empEnc[0].id;
        } else {
          const { data: empNueva } = await sb
            .from("empresas_prospecto")
            .insert({
              nombre: nombreLead,
              notas: `Alta automática desde contacto ${contacto.via === "whatsapp" ? "WhatsApp" : "web"}.`,
            })
            .select("id")
            .single();
          empresa_id = empNueva?.id ?? null;
        }

        await sb.from("prospectos").insert({
          empresa_id,
          nombre: nombreLead,
          email: contacto.email || null,
          telefono: contacto.telefono || null,
          via_contacto: contacto.via,
          motivo: contacto.motivo || null,
          estado: "sin_contactar",
          oportunidad_id,
          notas: contacto.mensaje ? `Mensaje: ${contacto.mensaje}` : null,
        });
      }
    }

    // ── DEDUP (B): upsert con onConflict como red de seguridad ante
    // disparos casi-simultáneos que pasaron el check (A) antes de que
    // ninguno insertara. Requiere el índice UNIQUE parcial sobre
    // mails_entrantes.message_id (ver dedup_mails_entrantes.sql).
    const { error: mailErr } = await sb
      .from("mails_entrantes")
      .upsert({
        message_id: message_id || null,
        remitente: remitente || null,
        asunto: asunto || null,
        cuerpo: cuerpo || null, // se guarda el cuerpo ORIGINAL completo, sin truncar
        recibido_at: recibido_at || new Date().toISOString(),
        clasificacion: c,
        cliente_id,
        oportunidad_id,
        estado_procesamiento: "clasificado",
        alertado: false,
      }, { onConflict: "message_id", ignoreDuplicates: true });

    if (mailErr) {
      return json({ error: "Error guardando el mail", detalle: mailErr.message, clasificacion: c }, 500);
    }

    return json({ ok: true, clasificacion: c, cliente_id, oportunidad_id });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});

function json(obj: unknown, status = 200) {
  return new Response(JSON.stringify(obj, null, 2), {
    status,
    headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" },
  });
}