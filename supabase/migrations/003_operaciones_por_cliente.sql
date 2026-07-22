-- ============================================================
-- Permite dar acceso a una o varias "operaciones" puntuales dentro
-- de un cliente (además de poder seguir dando acceso al cliente
-- completo, como ya hacía la Fase 3).
-- Ejecutar una sola vez en Supabase → SQL Editor, después de
-- 002_fase3_clientes_permisos.sql.
-- ============================================================

create table if not exists usuario_operaciones (
  usuario_id uuid not null references auth.users(id) on delete cascade,
  cliente_id uuid not null references clientes(id) on delete cascade,
  operacion text not null,
  creado_en timestamptz not null default now(),
  primary key (usuario_id, cliente_id, operacion)
);

alter table usuario_operaciones enable row level security;

drop policy if exists "ver_propias_operaciones" on usuario_operaciones;
create policy "ver_propias_operaciones" on usuario_operaciones
  for select to authenticated using (usuario_id = auth.uid() or soy_admin());

-- ------------------------------------------------------------
-- helper: operaciones a las que tengo acceso puntual (sin acceso
-- al cliente completo)
-- ------------------------------------------------------------
create or replace function mis_operaciones()
returns table(cliente_id uuid, operacion text)
language sql security definer stable set search_path = public
as $$
  select cliente_id, operacion from usuario_operaciones where usuario_id = auth.uid();
$$;

grant execute on function mis_operaciones() to authenticated;

-- versión con nombres, para mostrar en la interfaz ("Acceso a: ...")
create or replace function mis_operaciones_detalle()
returns table(cliente text, operacion text)
language sql security definer stable set search_path = public
as $$
  select c.nombre, uo.operacion
  from usuario_operaciones uo
  join clientes c on c.id = uo.cliente_id
  where uo.usuario_id = auth.uid()
  order by 1, 2;
$$;

grant execute on function mis_operaciones_detalle() to authenticated;

-- ------------------------------------------------------------
-- RLS de muestras: se agrega la tercera condición (acceso por
-- operación puntual) a la política que ya filtraba por cliente
-- ------------------------------------------------------------
drop policy if exists "muestras_por_cliente_permitido" on muestras;
create policy "muestras_por_cliente_permitido" on muestras
  for all to authenticated
  using (
    soy_admin()
    or cliente_id in (select mis_cliente_ids())
    or (cliente_id, operacion) in (select cliente_id, operacion from mis_operaciones())
  )
  with check (
    soy_admin()
    or cliente_id in (select mis_cliente_ids())
    or (cliente_id, operacion) in (select cliente_id, operacion from mis_operaciones())
  );

-- ------------------------------------------------------------
-- catálogo de operaciones de un cliente (para el selector del panel
-- de administración)
-- ------------------------------------------------------------
create or replace function operaciones_de_cliente(p_cliente text)
returns setof text
language sql security definer stable set search_path = public
as $$
  select distinct m.operacion
  from muestras m
  join clientes c on c.id = m.cliente_id
  where soy_admin() and c.nombre = p_cliente
    and m.operacion is not null and m.operacion <> ''
  order by 1;
$$;

grant execute on function operaciones_de_cliente(text) to authenticated;

-- ------------------------------------------------------------
-- administración: dar/quitar acceso a una operación puntual
-- ------------------------------------------------------------
create or replace function admin_asignar_operacion(p_email text, p_cliente text, p_operacion text)
returns void
language plpgsql security definer set search_path = public
as $$
declare uid uuid; cid uuid;
begin
  if not soy_admin() then
    raise exception 'Solo un administrador puede asignar operaciones.';
  end if;
  select id into uid from auth.users where email = p_email;
  if uid is null then
    raise exception 'No existe ningún usuario con el correo %. Creálo primero en Authentication → Users, o que se auto-registre.', p_email;
  end if;
  select id into cid from clientes where nombre = p_cliente;
  if cid is null then
    insert into clientes (nombre) values (p_cliente) returning id into cid;
  end if;
  insert into usuario_operaciones (usuario_id, cliente_id, operacion)
  values (uid, cid, p_operacion)
  on conflict do nothing;
end;
$$;

create or replace function admin_quitar_operacion(p_email text, p_cliente text, p_operacion text)
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
  delete from usuario_operaciones
  where usuario_id = uid and cliente_id = cid and operacion = p_operacion;
end;
$$;

grant execute on function admin_asignar_operacion(text,text,text) to authenticated;
grant execute on function admin_quitar_operacion(text,text,text) to authenticated;

-- ------------------------------------------------------------
-- admin_listar_accesos ahora incluye también los accesos por
-- operación puntual (operacion queda en null en las filas de
-- acceso al cliente completo)
-- ------------------------------------------------------------
create or replace function admin_listar_accesos()
returns table(email text, cliente text, operacion text)
language sql security definer stable set search_path = public
as $$
  select u.email, c.nombre, null::text
  from usuario_clientes uc
  join auth.users u on u.id = uc.usuario_id
  join clientes c on c.id = uc.cliente_id
  where soy_admin()
  union all
  select u.email, c.nombre, uo.operacion
  from usuario_operaciones uo
  join auth.users u on u.id = uo.usuario_id
  join clientes c on c.id = uo.cliente_id
  where soy_admin()
  order by 1, 2, 3;
$$;
