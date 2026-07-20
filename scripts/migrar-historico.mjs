// Fase 1 — migra los Excel históricos (los que hoy viven sueltos en una
// carpeta local) a la base de datos Supabase creada en la Fase 0.
//
// Uso:
//   node scripts/migrar-historico.mjs "/ruta/a/la/carpeta/con/excels"
//
// Requiere en scripts/.env (ver .env.example):
//   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
//
// Reutiliza exactamente la misma lógica de lectura que parseSheet() en
// app/panel_semaforo.html, para que cada muestra migrada sea idéntica
// a como hoy la interpreta el tablero.

import fs from "node:fs";
import path from "node:path";
import * as XLSX from "xlsx";
import { createClient } from "@supabase/supabase-js";
import "dotenv/config";

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
  console.error(
    "Faltan SUPABASE_URL y/o SUPABASE_SERVICE_ROLE_KEY. Copiá scripts/.env.example a scripts/.env y completá los valores del proyecto (Supabase → Project Settings → API)."
  );
  process.exit(1);
}

const carpeta = process.argv[2];
if (!carpeta) {
  console.error('Falta la carpeta. Uso: node scripts/migrar-historico.mjs "/ruta/a/la/carpeta"');
  process.exit(1);
}

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false },
});

const norm = (s) => (s === null || s === undefined ? "" : String(s).trim().replace(/\s+/g, " "));
const DIACRITICS = new RegExp("[\\u0300-\\u036f]", "g");
const strip = (s) => norm(s).toLowerCase().normalize("NFD").replace(DIACRITICS, "");

function parseDate(v) {
  if (v === "" || v == null) return null;
  if (v instanceof Date) return isNaN(v) ? null : v;
  const s = String(v).trim();
  let m = s.match(/^(\d{4})-(\d{2})-(\d{2})/);
  if (m) return new Date(+m[1], +m[2] - 1, +m[3]);
  m = s.match(/^(\d{1,2})[\/\-](\d{1,2})[\/\-](\d{4})/);
  if (m) return new Date(+m[3], +m[2] - 1, +m[1]);
  if (!isNaN(v) && v !== "") {
    const p = XLSX.SSF ? XLSX.SSF.parse_date_code(Number(v)) : null;
    if (p) return new Date(p.y, p.m - 1, p.d);
  }
  return null;
}
const toIsoDate = (d) => (d ? d.toISOString().slice(0, 10) : null);
const orNull = (s) => (s === "" ? null : s);

// Port fiel de parseSheet() (app/panel_semaforo.html) a Node.
function parseSheet(grid, fileName) {
  if (!grid.length) return { count: 0, rows: [] };
  const headers = grid[0].map(norm);
  const idx = {};
  headers.forEach((h, i) => {
    if (h && !(h in idx)) idx[h] = i;
  });
  const estadoCols = headers
    .map((h, i) => ({ h, i }))
    .filter((o) => / - Estado$/.test(o.h));
  if (!estadoCols.length && !("NOMBRE_CLIENTE" in idx)) return { count: 0, rows: [] };

  const rows = [];
  for (let r = 1; r < grid.length; r++) {
    const row = grid[r];
    if (!row || row.every((v) => v === "" || v == null)) continue;
    const get = (k) => (k in idx && row[idx[k]] !== undefined ? row[idx[k]] : "");

    let worst = "normal";
    estadoCols.forEach(({ h, i }) => {
      const v = strip(row[i]);
      if (v === "alerta") worst = "alerta";
      else if (v === "precaucion" && worst !== "alerta") worst = "precaucion";
    });

    const vals = {}, estados = {};
    estadoCols.forEach(({ h, i }) => {
      const param = h.replace(/ - Estado$/, "");
      const raw = param in idx ? row[idx[param]] : "";
      const num = raw !== "" && raw != null && !isNaN(parseFloat(raw)) ? parseFloat(raw) : null;
      vals[param] = num;
      const st = strip(row[i]);
      estados[param] = st === "alerta" || st === "precaucion" ? st : "normal";
    });
    const isoHeader = headers.find((h) => /^C[ÓO]DIGO ISO/i.test(h));
    const isoRaw = isoHeader ? norm(get(isoHeader)) : "";

    rows.push({
      archivo: fileName,
      vals,
      estados,
      iso: isoRaw,
      cliente: norm(get("NOMBRE_CLIENTE")) || "(Sin cliente)",
      operacion: norm(get("NOMBRE_OPERACION")) || "(Sin operación)",
      muestra: norm(get("N_MUESTRA")),
      solicitud: norm(get("N_SOLICITUD")),
      equipo: norm(get("EQUIPO")),
      tipoEquipo: norm(get("TIPO_EQUIPO")) || "(Sin tipo)",
      marcaEquipo: norm(get("MARCA_EQUIPO")),
      modeloEquipo: norm(get("MODELO_EQUIPO")),
      componente: norm(get("COMPONENTE")),
      marcaComponente: norm(get("MARCA_COMPONENTE")),
      modeloComponente: norm(get("MODELO_COMPONENTE")),
      descriptorComponente: norm(get("DESCRIPTOR_COMPONENTE")),
      producto: norm(get("PRODUCTO")),
      tipoProducto: norm(get("TIPO_PRODUCTO")),
      edadComponente: norm(get("EDAD_COMPONENTE")),
      unidadEdadComponente: norm(get("UNIDAD_EDAD_COMPONENTE")),
      edadProducto: norm(get("EDAD_PRODUCTO")),
      unidadEdadProducto: norm(get("UNIDAD_EDAD_PRODUCTO")),
      cantidadAdicionada: norm(get("CANTIDAD_ADICIONADA")),
      unidadCantidadAdicionada: norm(get("UNIDAD_CANTIDAD_ADICIONADA")),
      cambioProducto: norm(get("CAMBIO_DE_PRODUCTO")),
      cambioFiltro: norm(get("CAMBIO_DE_FILTRO")),
      nivelServicio: norm(get("NIVEL_DE_SERVICIO")),
      estadoProducto: norm(get("ESTADO_PRODUCTO")),
      estadoDesgaste: norm(get("ESTADO_DESGASTE")),
      estadoContaminacion: norm(get("ESTADO_CONTAMINACION")),
      estadoReporte: norm(get("ESTADO_REPORTE")),
      correlativo: norm(get("CORRELATIVO")),
      comentarioCliente: norm(get("COMENTARIO_CLIENTE")),
      comentarioReporte: norm(get("COMENTARIO_REPORTE")),
      usuario: norm(get("USUARIO")),
      fecha: parseDate(get("FECHA_MUESTREO")),
      fechaIngreso: parseDate(get("FECHA_INGRESO")),
      fechaRecepcion: parseDate(get("FECHA_RECEPCION")),
      fechaInforme: parseDate(get("FECHA_INFORME")),
      status: worst,
    });
  }
  return { count: rows.length, rows };
}

function rowToRecord(row, archivoId) {
  return {
    archivo_origen_id: archivoId,
    cliente: row.cliente,
    operacion: row.operacion,
    n_muestra: orNull(row.muestra),
    n_solicitud: orNull(row.solicitud),
    equipo: orNull(row.equipo),
    tipo_equipo: row.tipoEquipo,
    marca_equipo: orNull(row.marcaEquipo),
    modelo_equipo: orNull(row.modeloEquipo),
    componente: orNull(row.componente),
    marca_componente: orNull(row.marcaComponente),
    modelo_componente: orNull(row.modeloComponente),
    descriptor_componente: orNull(row.descriptorComponente),
    producto: orNull(row.producto),
    tipo_producto: orNull(row.tipoProducto),
    edad_componente: orNull(row.edadComponente),
    unidad_edad_componente: orNull(row.unidadEdadComponente),
    edad_producto: orNull(row.edadProducto),
    unidad_edad_producto: orNull(row.unidadEdadProducto),
    cantidad_adicionada: orNull(row.cantidadAdicionada),
    unidad_cantidad_adicionada: orNull(row.unidadCantidadAdicionada),
    cambio_producto: orNull(row.cambioProducto),
    cambio_filtro: orNull(row.cambioFiltro),
    nivel_servicio: orNull(row.nivelServicio),
    estado_producto: orNull(row.estadoProducto),
    estado_desgaste: orNull(row.estadoDesgaste),
    estado_contaminacion: orNull(row.estadoContaminacion),
    estado_reporte: orNull(row.estadoReporte),
    correlativo: orNull(row.correlativo),
    codigo_iso: orNull(row.iso),
    comentario_cliente: orNull(row.comentarioCliente),
    comentario_reporte: orNull(row.comentarioReporte),
    usuario: orNull(row.usuario),
    fecha: toIsoDate(row.fecha),
    fecha_ingreso: toIsoDate(row.fechaIngreso),
    fecha_recepcion: toIsoDate(row.fechaRecepcion),
    fecha_informe: toIsoDate(row.fechaInforme),
    estado_semaforo: row.status,
    parametros: row.vals,
    parametros_estado: row.estados,
  };
}

async function main() {
  const archivos = fs
    .readdirSync(carpeta)
    .filter((f) => /\.(xlsx|xls)$/i.test(f) && !f.startsWith("~$"));

  if (!archivos.length) {
    console.log("No se encontraron archivos .xlsx/.xls en " + carpeta);
    return;
  }

  console.log(`Encontrados ${archivos.length} archivo(s). Migrando...\n`);

  let totalMuestras = 0;
  for (const nombre of archivos) {
    const filePath = path.join(carpeta, nombre);
    const buf = fs.readFileSync(filePath);
    const wb = XLSX.read(buf, { type: "buffer" });
    const ws = wb.Sheets[wb.SheetNames[0]];
    const grid = XLSX.utils.sheet_to_json(ws, { header: 1, raw: true, defval: "" });
    const { count, rows } = parseSheet(grid, nombre);

    if (!count) {
      console.log(`  - ${nombre}: 0 muestras (no reconocido, se omite)`);
      continue;
    }

    const { data: archivo, error: errArchivo } = await supabase
      .from("archivos_importados")
      .insert({ nombre })
      .select()
      .single();
    if (errArchivo) {
      console.error(`  - ${nombre}: error al registrar el archivo:`, errArchivo.message);
      continue;
    }

    const registros = rows.map((r) => rowToRecord(r, archivo.id));
    const { error: errMuestras } = await supabase
      .from("muestras")
      .upsert(registros, { onConflict: "equipo,componente,n_muestra,fecha", ignoreDuplicates: false });

    if (errMuestras) {
      console.error(`  - ${nombre}: error al insertar muestras:`, errMuestras.message);
      continue;
    }

    totalMuestras += count;
    console.log(`  - ${nombre}: ${count} muestra(s) migrada(s)`);
  }

  console.log(`\nListo. ${totalMuestras} muestra(s) migradas en total.`);
}

main().catch((err) => {
  console.error("Error inesperado:", err);
  process.exit(1);
});
