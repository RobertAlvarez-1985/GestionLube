-- ============================================================
-- Gestión Lube — esquema Fase 0
-- Ejecutar completo en Supabase → SQL Editor (una sola vez).
-- ============================================================

create extension if not exists pgcrypto;

-- ------------------------------------------------------------
-- archivos_importados: trazabilidad de cada Excel cargado
-- ------------------------------------------------------------
create table if not exists archivos_importados (
  id uuid primary key default gen_random_uuid(),
  nombre text not null,
  storage_path text,
  importado_por uuid references auth.users(id),
  importado_en timestamptz not null default now()
);

-- ------------------------------------------------------------
-- muestras: una fila = una muestra de laboratorio.
-- Los campos reflejan 1:1 las columnas que ya lee parseSheet()
-- en panel_semaforo.html, para que la migración sea directa.
-- ------------------------------------------------------------
create table if not exists muestras (
  id uuid primary key default gen_random_uuid(),
  archivo_origen_id uuid references archivos_importados(id) on delete set null,

  cliente text not null default '(Sin cliente)',
  operacion text not null default '(Sin operación)',
  n_muestra text,
  n_solicitud text,

  equipo text,
  tipo_equipo text not null default '(Sin tipo)',
  marca_equipo text,
  modelo_equipo text,

  componente text,
  marca_componente text,
  modelo_componente text,
  descriptor_componente text,

  producto text,
  tipo_producto text,
  edad_componente text,
  unidad_edad_componente text,
  edad_producto text,
  unidad_edad_producto text,
  cantidad_adicionada text,
  unidad_cantidad_adicionada text,
  cambio_producto text,
  cambio_filtro text,
  nivel_servicio text,

  estado_producto text,
  estado_desgaste text,
  estado_contaminacion text,
  estado_reporte text,
  correlativo text,
  codigo_iso text,

  comentario_cliente text,
  comentario_reporte text,
  usuario text,

  fecha date,
  fecha_ingreso date,
  fecha_recepcion date,
  fecha_informe date,

  -- peor estado entre todos los parámetros de la muestra (worst en parseSheet)
  estado_semaforo text not null default 'normal'
    check (estado_semaforo in ('normal','precaucion','alerta')),

  -- vals: { "HIERRO (FE)": 42, "VISCOSIDAD 40C": 198, ... }
  parametros jsonb not null default '{}'::jsonb,
  -- estados: { "HIERRO (FE)": "precaucion", ... }
  parametros_estado jsonb not null default '{}'::jsonb,

  creado_por uuid references auth.users(id),
  creado_en timestamptz not null default now()
);

create index if not exists idx_muestras_cliente on muestras (cliente);
create index if not exists idx_muestras_equipo_componente on muestras (equipo, componente, fecha);
create index if not exists idx_muestras_estado on muestras (estado_semaforo);
create index if not exists idx_muestras_fecha on muestras (fecha);
create index if not exists idx_muestras_parametros on muestras using gin (parametros);

-- evita duplicar la misma muestra si se sube/migra más de una vez.
-- Tiene que ser una restricción simple sobre las columnas (no una expresión),
-- porque así es como Postgres resuelve "ON CONFLICT (equipo,componente,n_muestra,fecha)"
-- al hacer upsert desde el tablero y desde el script de migración.
alter table muestras
  add constraint uq_muestras_natural_key unique (equipo, componente, n_muestra, fecha);

-- ------------------------------------------------------------
-- recomendaciones_ia: caché de la sugerencia de IA por muestra
-- ------------------------------------------------------------
create table if not exists recomendaciones_ia (
  id uuid primary key default gen_random_uuid(),
  muestra_id uuid not null references muestras(id) on delete cascade,
  hash_entrada text not null,
  texto text not null,
  modelo text not null,
  creado_en timestamptz not null default now(),
  unique (muestra_id, hash_entrada)
);

-- ------------------------------------------------------------
-- RLS: por ahora, cualquier usuario autenticado tiene acceso
-- completo (herramienta de un solo laboratorio). Cuando se
-- agreguen roles (Fase 3), estas políticas se reemplazan por
-- reglas por cliente/rol.
-- ------------------------------------------------------------
alter table archivos_importados enable row level security;
alter table muestras enable row level security;
alter table recomendaciones_ia enable row level security;

create policy "autenticados_archivos" on archivos_importados
  for all to authenticated using (true) with check (true);

create policy "autenticados_muestras" on muestras
  for all to authenticated using (true) with check (true);

create policy "autenticados_recomendaciones" on recomendaciones_ia
  for all to authenticated using (true) with check (true);
