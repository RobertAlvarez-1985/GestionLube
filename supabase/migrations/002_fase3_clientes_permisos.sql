-- ============================================================
-- Fase 3 — clientes + permisos por usuario
-- Ejecutar una sola vez en Supabase → SQL Editor, después de schema.sql.
-- ============================================================

-- ------------------------------------------------------------
-- tablas nuevas
-- ------------------------------------------------------------
create table if not exists clientes (
  id uuid primary key default gen_random_uuid(),
  nombre text not null unique,
  creado_en timestamptz not null default now()
);

create table if not exists perfiles (
  id uuid primary key references auth.users(id) on delete cascade,
  es_admin boolean not null default false,
  creado_en timestamptz not null default now()
);

create table if not exists usuario_clientes (
  usuario_id uuid not null references auth.users(id) on delete cascade,
  cliente_id uuid not null references clientes(id) on delete cascade,
  creado_en timestamptz not null default now(),
  primary key (usuario_id, cliente_id)
);

alter table muestras add column if not exists cliente_id uuid references clientes(id);
create index if not exists idx_muestras_cliente_id on muestras (cliente_id);

-- ------------------------------------------------------------
-- backfill: crear clientes a partir del histórico que ya existe
-- ------------------------------------------------------------
insert into clientes (nombre)
select distinct cliente from muestras
where cliente is not null and cliente <> ''
on conflict (nombre) do nothing;

update muestras m set cliente_id = c.id
from clientes c
where m.cliente_id is null and m.cliente = c.nombre;

-- ------------------------------------------------------------
-- trigger: resuelve (y crea si hace falta) cliente_id a partir del
-- texto "cliente" que ya manda el tablero -no hace falta cambiar cómo
-- sube los datos-.
-- ------------------------------------------------------------
create or replace function resolver_cliente_id()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  cid uuid;
begin
  if new.cliente is null or new.cliente = '' then
    new.cliente_id := null;
    return new;
  end if;
  select id into cid from clientes where nombre = new.cliente;
  if cid is null then
    insert into clientes (nombre) values (new.cliente) returning id into cid;
  end if;
  new.cliente_id := cid;
  return new;
end;
$$;

drop trigger if exists trg_resolver_cliente_id on muestras;
create trigger trg_resolver_cliente_id
  before insert or update of cliente on muestras
  for each row execute function resolver_cliente_id();

-- ------------------------------------------------------------
-- funciones de permisos (security definer para evitar recursión
-- de RLS al consultar perfiles/usuario_clientes desde una policy)
-- ------------------------------------------------------------
create or replace function soy_admin()
returns boolean
language sql security definer stable set search_path = public
as $$ select coalesce((select es_admin from perfiles where id = auth.uid()), false); $$;

create or replace function mis_cliente_ids()
returns setof uuid
language sql security definer stable set search_path = public
as $$ select cliente_id from usuario_clientes where usuario_id = auth.uid(); $$;

create or replace function mis_clientes_nombres()
returns setof text
language sql security definer stable set search_path = public
as $$
  select c.nombre from clientes c
  where soy_admin() or c.id in (select cliente_id from usuario_clientes where usuario_id = auth.uid())
  order by c.nombre;
$$;

-- ------------------------------------------------------------
-- administración de accesos (solo para quien tenga es_admin=true)
-- ------------------------------------------------------------
create or replace function admin_asignar_cliente(p_email text, p_cliente text)
returns void
language plpgsql security definer set search_path = public
as $$
declare uid uuid; cid uuid;
begin
  if not soy_admin() then
    raise exception 'Solo un administrador puede asignar clientes.';
  end if;
  select id into uid from auth.users where email = p_email;
  if uid is null then
    raise exception 'No existe ningún usuario con el correo %. Creálo primero en Authentication → Users.', p_email;
  end if;
  select id into cid from clientes where nombre = p_cliente;
  if cid is null then
    insert into clientes (nombre) values (p_cliente) returning id into cid;
  end if;
  insert into usuario_clientes (usuario_id, cliente_id) values (uid, cid)
  on conflict do nothing;
end;
$$;

create or replace function admin_quitar_cliente(p_email text, p_cliente text)
returns void
language plpgsql security definer set search_path = public
as $$
declare uid uuid; cid uuid;
begin
  if not soy_admin() then
    raise exception 'Solo un administrador puede quitar accesos.';
  end if;
  select id into uid from auth.users where email = p_email;
  select id into cid from clientes where nombre = p_cliente;
  if uid is null or cid is null then return; end if;
  delete from usuario_clientes where usuario_id = uid and cliente_id = cid;
end;
$$;

create or replace function admin_listar_accesos()
returns table(email text, cliente text)
language sql security definer stable set search_path = public
as $$
  select u.email, c.nombre
  from usuario_clientes uc
  join auth.users u on u.id = uc.usuario_id
  join clientes c on c.id = uc.cliente_id
  where soy_admin()
  order by u.email, c.nombre;
$$;

grant execute on function soy_admin() to authenticated;
grant execute on function mis_cliente_ids() to authenticated;
grant execute on function mis_clientes_nombres() to authenticated;
grant execute on function admin_asignar_cliente(text,text) to authenticated;
grant execute on function admin_quitar_cliente(text,text) to authenticated;
grant execute on function admin_listar_accesos() to authenticated;

-- ------------------------------------------------------------
-- RLS
-- ------------------------------------------------------------
alter table clientes enable row level security;
alter table perfiles enable row level security;
alter table usuario_clientes enable row level security;

drop policy if exists "leer_clientes" on clientes;
create policy "leer_clientes" on clientes for select to authenticated using (true);

drop policy if exists "ver_propio_perfil" on perfiles;
create policy "ver_propio_perfil" on perfiles for select to authenticated using (id = auth.uid() or soy_admin());

drop policy if exists "ver_propias_asignaciones" on usuario_clientes;
create policy "ver_propias_asignaciones" on usuario_clientes for select to authenticated using (usuario_id = auth.uid() or soy_admin());

-- reemplaza la política abierta de la Fase 0 (cualquier autenticado veía
-- y subía todo) por una filtrada según los clientes asignados
drop policy if exists "autenticados_muestras" on muestras;
create policy "muestras_por_cliente_permitido" on muestras
  for all to authenticated
  using (soy_admin() or cliente_id in (select mis_cliente_ids()))
  with check (soy_admin() or cliente_id in (select mis_cliente_ids()));

-- ------------------------------------------------------------
-- IMPORTANTE: convertite en el primer administrador.
-- Reemplazá el correo por el tuyo y ejecutalo (podés cambiarlo y
-- volver a correr esta última parte cuando quieras dar de alta a
-- otro administrador).
-- ------------------------------------------------------------
insert into perfiles (id, es_admin)
select id, true from auth.users where email = 'ralvarez.1985@gmail.com'
on conflict (id) do update set es_admin = true;
