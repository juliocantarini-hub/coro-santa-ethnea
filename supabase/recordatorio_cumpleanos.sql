-- Recordatorio de cumpleaños por push notification
-- Proyecto: coral-voces-02 (Santa Ethnea, Encuentro, San Román, Sonamos)
-- Ejecutar en el SQL Editor de Supabase, UNA VEZ, después de deployar la Edge Function
-- `recordatorio-cumpleanos` (supabase functions deploy recordatorio-cumpleanos).

create extension if not exists pg_net;

-- Reemplazar <SERVICE_ROLE_KEY> por la service_role key de este proyecto
-- (Supabase → Project Settings → API → service_role). No es la anon key.
select cron.schedule(
  'recordatorio-cumpleanos',
  '0 12 * * *',  -- 12:00 UTC = 09:00 hora Argentina
  $cron$
  select net.http_post(
    url := 'https://xfddjbldwfqkdlhnwwhk.supabase.co/functions/v1/recordatorio-cumpleanos',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer <SERVICE_ROLE_KEY>'
    ),
    body := '{}'::jsonb
  );
  $cron$
);

-- Para desprogramarlo más adelante:
-- select cron.unschedule('recordatorio-cumpleanos');
