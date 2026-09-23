-- APLICADA en Supabase el 2026-09-23 (version 20260923193322).
-- Historial de la cuenta corriente de cada cliente (ventas, compras a cuenta y pagos).
create table public.movimientos_cliente (
    id uuid primary key default gen_random_uuid(),
    cliente_id uuid not null references public.clientes(id),
    fecha date not null default (now() at time zone 'America/Argentina/Mendoza')::date,
    tipo varchar(20) not null check (tipo in ('venta', 'compra', 'pago')),
    monto numeric(10,2) not null check (monto > 0),   -- siempre positivo; el tipo define si suma (venta/compra) o resta (pago)
    concepto text,
    venta_id uuid references public.ventas(id) on delete set null,
    created_at timestamptz default now()
);
create index idx_movimientos_cliente on public.movimientos_cliente(cliente_id, fecha desc);

alter table public.movimientos_cliente enable row level security;
create policy "Solo duenos" on public.movimientos_cliente
    for all to authenticated using (public.es_dueno()) with check (public.es_dueno());

-- Registra una compra a cuenta (suma deuda) o un pago (resta deuda): movimiento + saldo en una transacción.
-- Devuelve el saldo nuevo. SECURITY INVOKER: RLS (solo dueños) sigue aplicando.
create or replace function public.registrar_movimiento_cliente(
    p_cliente_id uuid, p_tipo text, p_monto numeric, p_concepto text default null)
returns numeric
language plpgsql
security invoker
set search_path = ''
as $$
declare
    v_saldo numeric;
begin
    if p_tipo not in ('compra', 'pago') then
        raise exception 'Tipo de movimiento inválido';
    end if;
    if p_monto is null or p_monto <= 0 then
        raise exception 'El monto debe ser mayor a 0';
    end if;

    update public.clientes
    set saldo = coalesce(saldo, 0) + case p_tipo when 'compra' then p_monto else -p_monto end
    where id = p_cliente_id
    returning saldo into v_saldo;
    if not found then
        raise exception 'Cliente no encontrado';
    end if;

    insert into public.movimientos_cliente (cliente_id, tipo, monto, concepto)
    values (p_cliente_id, p_tipo, p_monto, nullif(trim(p_concepto), ''));

    return v_saldo;
end;
$$;
revoke execute on function public.registrar_movimiento_cliente(uuid, text, numeric, text) from public, anon;
grant execute on function public.registrar_movimiento_cliente(uuid, text, numeric, text) to authenticated;

-- registrar_venta ahora también deja su movimiento en el historial
create or replace function public.registrar_venta(p_cliente_id uuid, p_items jsonb)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
    v_lista text;
    v_venta_id uuid;
    v_total numeric(10,2);
begin
    if jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items) = 0 then
        raise exception 'La venta no tiene productos';
    end if;

    select coalesce(lista_precio, 'minorista') into v_lista
    from public.clientes where id = p_cliente_id;
    if not found then
        raise exception 'Cliente no encontrado';
    end if;

    if exists (
        select 1
        from jsonb_to_recordset(p_items) as i(producto_id uuid, cantidad int)
        left join public.productos p on p.id = i.producto_id and p.activo
        where p.id is null or i.cantidad is null or i.cantidad <= 0
    ) then
        raise exception 'Hay productos inexistentes, inactivos o con cantidad inválida';
    end if;

    insert into public.ventas (cliente_id, total, estado, fecha)
    values (p_cliente_id, 0, 'pendiente', (now() at time zone 'America/Argentina/Mendoza')::date)
    returning id into v_venta_id;

    insert into public.venta_detalles (venta_id, producto_id, cantidad, precio_unitario)
    select v_venta_id, p.id, i.cantidad,
           coalesce(
               case v_lista
                   when 'mayorista' then p.precio_mayorista
                   when 'distribuidor' then p.precio_distribuidor
                   else p.precio_minorista
               end,
               p.precio_venta)
    from jsonb_to_recordset(p_items) as i(producto_id uuid, cantidad int)
    join public.productos p on p.id = i.producto_id;

    select sum(subtotal) into v_total from public.venta_detalles where venta_id = v_venta_id;

    update public.ventas set total = v_total where id = v_venta_id;
    update public.clientes set saldo = coalesce(saldo, 0) + v_total where id = p_cliente_id;
    insert into public.movimientos_cliente (cliente_id, tipo, monto, concepto, venta_id)
    values (p_cliente_id, 'venta', v_total, 'Venta', v_venta_id);

    return v_venta_id;
end;
$$;
