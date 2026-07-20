# Gestión Lube

Panel de análisis de aceite usado (semáforo normal/precaución/alerta) por
equipo y componente. Hoy es un único archivo HTML (`app/panel_semaforo.html`)
que lee Excel desde una carpeta local en cada sesión y no persiste nada.
Este repo agrega la base para que los datos vivan en la nube (Supabase) y,
más adelante, un asistente de IA sobre los comentarios de cada muestra.

## Estado del plan

| Fase | Contenido | Estado |
|---|---|---|
| 0 | Esquema de base de datos (`supabase/schema.sql`) | ✅ listo para ejecutar |
| 1 | Script de migración del histórico (`scripts/migrar-historico.mjs`) | ✅ listo para correr |
| 2 | El tablero deja de depender de la carpeta local y lee/escribe en Supabase | pendiente |
| 3 | Login y uso multiusuario/multi-dispositivo | pendiente |
| 4 | Asistente de IA sobre `comentarioCliente`/`comentarioReporte` | pendiente |
| 5 | Alertas automáticas y respaldo | pendiente |

## Fase 0 — crear el proyecto Supabase

1. Crear una cuenta gratuita en [supabase.com](https://supabase.com) y un
   nuevo proyecto (elegir una región cercana).
2. En el proyecto, ir a **SQL Editor** → pegar el contenido completo de
   `supabase/schema.sql` → **Run**. Esto crea las tablas `muestras`,
   `archivos_importados`, `recomendaciones_ia` y sus políticas de seguridad.
3. En **Authentication → Providers**, dejar habilitado Email (o el método
   que prefieran) para poder crear el primer usuario.
4. En **Project Settings → API**, copiar:
   - `Project URL` → `SUPABASE_URL`
   - `service_role` key (secreta, no la `anon`) → `SUPABASE_SERVICE_ROLE_KEY`

Guardar esos dos valores en un archivo `.env` en la raíz del repo (copiar
`.env.example` como base). **No se sube al repositorio** (ya está en
`.gitignore`).

## Fase 1 — migrar el histórico de Excel

Con Node.js instalado:

```bash
npm install
cp .env.example .env   # y completar con los valores del paso anterior
npm run migrar -- "/ruta/a/la/carpeta/con/los/excel/historicos"
```

El script (`scripts/migrar-historico.mjs`) reutiliza la misma lógica de
lectura que ya usa `panel_semaforo.html` (`parseSheet`), así que cada
muestra migrada se interpreta exactamente igual que hoy en el tablero.
Se puede correr más de una vez sobre la misma carpeta sin duplicar datos
(la tabla `muestras` tiene una clave natural única por
equipo+componente+n° de muestra+fecha).

Al terminar, la base de datos en Supabase va a tener el histórico completo
disponible desde cualquier dispositivo — la Fase 2 es la que conecta el
tablero HTML a esa base en vez de la carpeta local.
