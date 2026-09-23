-- APLICADA en Supabase el 2026-09-23 (version 20260923191813). Acceso solo para los dueños
-- (lista blanca en public.duenos) + RLS en todas las tablas.
-- Los dueños se cargaron aparte con:  insert into public.duenos (user_id) select id from auth.users where email in (...);

create table if not exists public.duenos (
    user_id uuid primary key references auth.users(id) on delete cascade
);
-- RLS sin políticas: la API no puede leer ni escribir esta tabla (solo el SQL editor / service role).
alter table public.duenos enable row level security;

create or replace function public.es_dueno()
returns boolean
language sql stable security definer
set search_path = ''
as $$
    select exists (select 1 from public.duenos where user_id = (select auth.uid()));
$$;
revoke execute on function public.es_dueno() from public, anon;
grant execute on function public.es_dueno() to authenticated;

-- RLS también en ventas y venta_detalles (estaban expuestas)
alter table public.ventas enable row level security;
alter table public.venta_detalles enable row level security;

-- Reemplazar la política de desarrollo por una que exige ser dueño
drop policy if exists "Allow all access" on public.clientes;
drop policy if exists "Allow all access" on public.productos;
drop policy if exists "Allow all access" on public.proveedores;
drop policy if exists "Allow all access" on public.ventas_diarias;
drop policy if exists "Allow all access" on public.cuenta_corriente;

do $$
declare t text;
begin
    foreach t in array array['clientes','productos','proveedores','ventas','venta_detalles','ventas_diarias','cuenta_corriente']
    loop
        execute format(
            'create policy "Solo duenos" on public.%I for all to authenticated using (public.es_dueno()) with check (public.es_dueno())', t);
    end loop;
end $$;

-- Función de saldos: no debe poder llamarla anon ni cualquier usuario; fijar search_path
revoke execute on function public.actualizar_saldo_cliente(uuid, numeric) from public, anon, authenticated;
alter function public.actualizar_saldo_cliente(uuid, numeric) set search_path = public;
alter function public.update_updated_at_column() set search_path = '';
