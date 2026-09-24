-- APLICADA en el proyecto jklsoynymbpwvlaqwzhy (version 20260924042444).
-- Cuenta corriente con proveedores: saldo = lo que se le debe al proveedor (positivo = deuda propia).
alter table public.proveedores add column saldo numeric(10,2) not null default 0;

create table public.movimientos_proveedor (
    id uuid primary key default gen_random_uuid(),
    proveedor_id uuid not null references public.proveedores(id),
    fecha date not null default (now() at time zone 'America/Argentina/Mendoza')::date,
    tipo varchar(20) not null check (tipo in ('compra', 'pago')),
    monto numeric(10,2) not null check (monto > 0),   -- siempre positivo; compra suma deuda, pago la resta
    concepto text,
    created_at timestamptz default now()
);
create index idx_movimientos_proveedor on public.movimientos_proveedor(proveedor_id, fecha desc);

alter table public.movimientos_proveedor enable row level security;
create policy "Solo duenos" on public.movimientos_proveedor
    for all to authenticated using (public.es_dueno()) with check (public.es_dueno());

-- Registra una compra a cuenta (suma lo que se le debe) o un pago (lo resta): movimiento + saldo en una
-- transacción. Devuelve el saldo nuevo. SECURITY INVOKER: RLS (solo dueños) sigue aplicando.
create or replace function public.registrar_movimiento_proveedor(
    p_proveedor_id uuid, p_tipo text, p_monto numeric, p_concepto text default null)
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

    update public.proveedores
    set saldo = saldo + case p_tipo when 'compra' then p_monto else -p_monto end
    where id = p_proveedor_id
    returning saldo into v_saldo;
    if not found then
        raise exception 'Proveedor no encontrado';
    end if;

    insert into public.movimientos_proveedor (proveedor_id, tipo, monto, concepto)
    values (p_proveedor_id, p_tipo, p_monto, nullif(trim(p_concepto), ''));

    return v_saldo;
end;
$$;
revoke execute on function public.registrar_movimiento_proveedor(uuid, text, numeric, text) from public, anon;
grant execute on function public.registrar_movimiento_proveedor(uuid, text, numeric, text) to authenticated;
