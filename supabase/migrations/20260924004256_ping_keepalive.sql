-- APLICADA en el proyecto jklsoynymbpwvlaqwzhy (version 20260924004256).
-- Función mínima para el keep-alive diario (GitHub Actions). No lee tablas ni expone datos.
create or replace function public.ping()
returns timestamptz
language sql
stable
security invoker
set search_path = ''
as $$
    select now();
$$;
grant execute on function public.ping() to anon, authenticated;
