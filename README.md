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
| 2 | El tablero deja de depender de la carpeta local y lee/escribe en Supabase | ✅ verificado en producción |
| 3 | Permisos por cliente (multiusuario) | ✅ listo para migrar |
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
   - **Secret key** (`sb_secret_...` — el reemplazo actual de la vieja
     `service_role`, no la Publishable) → `SUPABASE_SERVICE_ROLE_KEY`

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
disponible desde cualquier dispositivo.

## Fase 2 — conectar el tablero a la nube

`app/panel_semaforo.html` ahora tiene un botón **☁️ Nube** en la barra
superior de la vista **Dashboard**. Mientras no se configure nada, el
tablero funciona exactamente igual que antes (100% local) — la nube es
opcional.

1. Crear el primer usuario: en Supabase → **Authentication → Users** → **Add
   user** (email + contraseña). Este es el usuario con el que el laboratorio
   va a iniciar sesión en el tablero, no tiene por qué ser el mismo que la
   cuenta de Supabase.
2. Abrir `app/panel_semaforo.html` en el navegador → vista **Dashboard** →
   botón **☁️ Nube: sin configurar**.
3. Pegar el **Project URL** y la **Publishable key** (`sb_publishable_...`,
   Project Settings → API — es pública, a diferencia de la Secret key que
   usa el script de migración) → **Guardar conexión**.
4. Iniciar sesión con el usuario creado en el paso 1.

Al iniciar sesión, el tablero trae automáticamente todo el histórico desde
Supabase — ya no hace falta volver a elegir ninguna carpeta. Para cargar
muestras nuevas, se sigue usando "Seleccionar carpeta" como antes; después
de leerlas aparece un botón **Subir a la nube** que las sube y refresca el
tablero con el consolidado (histórico + nuevas).

La conexión (URL + clave anon) queda guardada en el navegador
(`localStorage`), no en el repositorio.

## Fase 3 — permisos por cliente

Hasta acá, cualquier usuario logueado veía y subía datos de todos los
clientes. Esta fase agrega una tabla `clientes` y permisos por usuario: un
administrador ve/sube todo, el resto solo lo que se le asigne.

1. En Supabase → **SQL Editor** → pegar el contenido completo de
   `supabase/migrations/002_fase3_clientes_permisos.sql` → **Run**.
   - Crea las tablas `clientes`, `perfiles`, `usuario_clientes`.
   - Reconoce automáticamente los clientes que ya estaban en el histórico.
   - Al final del archivo hay un `insert into perfiles...` que te convierte
     a vos (el correo que está puesto ahí) en el primer administrador —
     revisá que sea el correo correcto antes de correrlo, o cambialo.
2. Recargá `app/panel_semaforo.html` e iniciá sesión de nuevo. En el panel
   **☁️ Nube** debería aparecer, debajo de tu correo, "Administrador ·
   acceso a todos los clientes", y una sección nueva **Administración de
   accesos**.
3. El panel ☁️ Nube tiene dos pestañas: **Iniciar sesión** y **Crear
   cuenta**. Cualquier persona del laboratorio puede crear su propia
   cuenta (correo + contraseña) desde ahí — al crearla queda **sin acceso
   a ningún cliente** hasta que un administrador se lo asigne, así que no
   hay riesgo en dejar la creación de cuentas abierta.
4. Para darle acceso a un cliente a un usuario (ya sea que se creó su
   cuenta solo, o que se la creaste vos en Authentication → Users):
   - Panel ☁️ Nube → **Administración de accesos**.
   - Correo del usuario + nombre exacto del cliente (tal como aparece en
     el Excel) → **Dar acceso**.
   - Ese usuario, la próxima vez que inicie sesión, solo va a ver y poder
     subir datos de los clientes que se le asignaron — el resto del
     tablero (Dashboard, Historial, KPIs, Analytic) queda filtrado
     automáticamente, sin ningún cambio adicional.
5. Si alguien sube un Excel con muestras de varios clientes y no tiene
   acceso a todos, el tablero sube solo las filas permitidas y avisa
   cuántas quedaron afuera.

Nombrar a otro administrador (alguien que vea *todos* los clientes) sigue
siendo manual: se hace repitiendo el `insert into perfiles...` del final
de `002_fase3_clientes_permisos.sql` con el correo que corresponda, desde
el SQL Editor de Supabase.
