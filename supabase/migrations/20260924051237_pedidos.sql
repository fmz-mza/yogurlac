-- APLICADA en el proyecto jklsoynymbpwvlaqwzhy (version 20260924051237).
-- Pedidos de los clientes: se cargan una sola vez y de ahí salen la compra a Yogurlac y la entrega/venta.
create table public.pedidos (
    id uuid primary key default gen_random_uuid(),
    cliente_id uuid not null references public.clientes(id),
    fecha_entrega date not null default (now() at time zone 'America/Argentina/Mendoza')::date,
    estado varchar(20) not null default 'pendiente' check (estado in ('pendiente', 'entregado', 'cancelado')),
    observaciones text,
    venta_id uuid references public.ventas(id) on delete set null,   -- se completa al entregar
    created_at timestamptz default now()
);
create index idx_pedidos_fecha on public.pedidos(fecha_entrega, estado);
create index idx_pedidos_cliente on public.pedidos(cliente_id);

create table public.pedido_items (
    id uuid primary key default gen_random_uuid(),
    pedido_id uuid not null references public.pedidos(id) on delete cascade,
    producto_id uuid not null references public.productos(id),
    cantidad integer not null check (cantidad > 0),
    unique (pedido_id, producto_id)
);
create index idx_pedido_items_pedido on public.pedido_items(pedido_id);

alter table public.pedidos enable row level security;
alter table public.pedido_items enable row level security;
create policy "Solo duenos" on public.pedidos for all to authenticated using (public.es_dueno()) with check (public.es_dueno());
create policy "Solo duenos" on public.pedido_items for all to authenticated using (public.es_dueno()) with check (public.es_dueno());

-- Valida la lista de items [{producto_id, cantidad}]: no vacía, productos activos, cantidades > 0
create or replace function public.validar_items_pedido(p_items jsonb)
returns void
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
    if jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items) = 0 then
        raise exception 'El pedido no tiene productos';
    end if;
    if exists (
        select 1
        from jsonb_to_recordset(p_items) as i(producto_id uuid, cantidad int)
        left join public.productos p on p.id = i.producto_id and p.activo
        where p.id is null or i.cantidad is null or i.cantidad <= 0
    ) then
        raise exception 'Hay productos inexistentes, inactivos o con cantidad inválida';
    end if;
end;
$$;

-- Crea un pedido con sus items en una transacción. Si un producto se repite, se suman las cantidades.
create or replace function public.crear_pedido(
    p_cliente_id uuid, p_fecha date, p_items jsonb, p_observaciones text default null)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
    v_id uuid;
begin
    if not exists (select 1 from public.clientes where id = p_cliente_id) then
        raise exception 'Cliente no encontrado';
    end if;
    perform public.validar_items_pedido(p_items);

    insert into public.pedidos (cliente_id, fecha_entrega, observaciones)
    values (p_cliente_id,
            coalesce(p_fecha, (now() at time zone 'America/Argentina/Mendoza')::date),
            nullif(trim(p_observaciones), ''))
    returning id into v_id;

    insert into public.pedido_items (pedido_id, producto_id, cantidad)
    select v_id, i.producto_id, sum(i.cantidad)
    from jsonb_to_recordset(p_items) as i(producto_id uuid, cantidad int)
    group by i.producto_id;

    return v_id;
end;
$$;

-- Modifica un pedido PENDIENTE (fecha, observaciones e items completos).
create or replace function public.actualizar_pedido(
    p_pedido_id uuid, p_fecha date, p_items jsonb, p_observaciones text default null)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
    v_estado text;
begin
    select estado into v_estado from public.pedidos where id = p_pedido_id for update;
    if not found then
        raise exception 'Pedido no encontrado';
    end if;
    if v_estado <> 'pendiente' then
        raise exception 'Solo se pueden modificar pedidos pendientes';
    end if;
    perform public.validar_items_pedido(p_items);

    update public.pedidos
    set fecha_entrega = coalesce(p_fecha, fecha_entrega),
        observaciones = nullif(trim(p_observaciones), '')
    where id = p_pedido_id;

    delete from public.pedido_items where pedido_id = p_pedido_id;
    insert into public.pedido_items (pedido_id, producto_id, cantidad)
    select p_pedido_id, i.producto_id, sum(i.cantidad)
    from jsonb_to_recordset(p_items) as i(producto_id uuid, cantidad int)
    group by i.producto_id;
end;
$$;

-- Cancela un pedido PENDIENTE.
create or replace function public.cancelar_pedido(p_pedido_id uuid)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
    v_estado text;
begin
    select estado into v_estado from public.pedidos where id = p_pedido_id for update;
    if not found then
        raise exception 'Pedido no encontrado';
    end if;
    if v_estado <> 'pendiente' then
        raise exception 'Solo se pueden cancelar pedidos pendientes';
    end if;
    update public.pedidos set estado = 'cancelado' where id = p_pedido_id;
end;
$$;

revoke execute on function public.validar_items_pedido(jsonb) from public, anon;
revoke execute on function public.crear_pedido(uuid, date, jsonb, text) from public, anon;
revoke execute on function public.actualizar_pedido(uuid, date, jsonb, text) from public, anon;
revoke execute on function public.cancelar_pedido(uuid) from public, anon;
grant execute on function public.validar_items_pedido(jsonb) to authenticated;
grant execute on function public.crear_pedido(uuid, date, jsonb, text) to authenticated;
grant execute on function public.actualizar_pedido(uuid, date, jsonb, text) to authenticated;
grant execute on function public.cancelar_pedido(uuid) to authenticated;
