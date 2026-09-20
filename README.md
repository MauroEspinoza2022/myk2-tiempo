# myk2 Tiempo · v1.4.0

Aplicación responsive de horas extra y descansos compensatorios. © Ing. Mauro Espinoza · myk2 · mespinozahse@gmail.com · +51 975721020.

## Uso

Confirma tu salida con el reloj de Lima o edita fecha y hora. Lunes y martes se acumula desde 16:00; miércoles a viernes desde 17:00; sábado desde 12:00. Domingo, feriado o jornada atípica: registra inicio y fin. Marca explícitamente salida al día siguiente cuando corresponda. La pausa se descuenta del intervalo extra, no de la jornada ordinaria.

La equivalencia inicial es 8 h = 1 día, configurable. Solicitado no afecta saldo; aprobado reserva; gozado descuenta; cancelado libera. No se permite aprobar/gozar por encima del saldo. Los registros existentes conservan sus horas al cambiar la equivalencia o el horario. El estado de descanso es un registro personal de la autorización empresarial, no un circuito de aprobación laboral.

PDF y Excel incluyen agrupación diaria, semanal (lunes a domingo) o mensual, filtros de fechas, detalle y comentarios. El PDF incluye portada ejecutiva con indicadores, gráfico de barras, distribución de horas, consolidado, jornadas, descansos y movimientos de saldo. El Excel contiene seis hojas, dos gráficos nativos editables, tablas con filtros, fórmulas de resumen, fechas y horas tipadas y trazabilidad del saldo. El saldo al cierre incluye la apertura anterior al período; el neto corresponde solo al intervalo. Los datos anteriores al período se exportan como instantánea y las fórmulas recalculan los rangos incluidos, según las notas de Parámetros.

## Publicación

Publicado en https://mauroespinoza2022.github.io/myk2-tiempo/ mediante GitHub Actions. Cada cambio en `main` ejecuta pruebas, compila y publica automáticamente a través de `.github/workflows/pages.yml`. El código fuente se mantiene junto con un lockfile.

`npm ci`, `npm test`, `npm run build`. El resultado está en `dist/`. Sin las variables públicas de Supabase se activa modo local, visible en toda la aplicación. No simula cuentas ni sincronización. Exporta respaldos JSON antes de borrar los datos del navegador. Esos respaldos contienen datos personales.

## Activar cuentas, administrador y sincronización

1. Crear un proyecto Supabase. Ejecutar `supabase/schema.sql`, `supabase/002_admin_analytics.sql` y `supabase/003_identity_fields.sql` y `supabase/004_admin_management.sql` y `supabase/005_company_roles.sql`, una vez y en ese orden, en su SQL Editor. Si ya se ejecutó el esquema inicial, ejecutar las migraciones 002, 003, 004 y 005.
2. Configurar Authentication > URL Configuration con Site URL y Redirect URL: `https://mauroespinoza2022.github.io/myk2-tiempo/`. Mantener confirmación de correo habilitada. Para uso con varios usuarios configurar un proveedor SMTP propio y revisar los límites de envío del servicio.
3. Configurar `VITE_SUPABASE_URL` y `VITE_SUPABASE_ANON_KEY` con la URL y clave pública publishable/anon. Se pueden guardar como variables del repositorio para Actions; localmente en `.env.local`. Nunca usar service_role ni la contraseña de base de datos en el frontend.
4. Compilar y publicar nuevamente. Registrarse con `mespinozahse@gmail.com`, confirmar correo y ejecutar el bloque comentado al final del esquema para conceder el rol administrador.
5. Los usuarios ven solo sus registros por RLS. El administrador puede ver y editar perfiles, jornadas y descansos de todos desde Administración. La gestión de identidad (bloqueo/borrado de cuentas, correos) se realiza en el panel Supabase, no en el frontend. Las contraseñas las gestiona Supabase Auth y no son legibles por el administrador.
6. Restaurar un respaldo local dentro de la cuenta para migrar los registros. El importador combina fechas sin sobrescribir las existentes.

## Seguridad y cálculo

RLS en todas las tablas; tabla de administradores sin escritura cliente; cálculo de minutos y validación de saldo en triggers; bloqueo por usuario para serializar cambios de saldo; historial de cambios de jornadas y descansos en `audit_log`. Los privilegios solo se otorgan mediante SQL administrativo. No se publica información personal de los usuarios en GitHub. El reloj de captura usa el reloj del dispositivo convertido a Lima; el backend rechaza fechas futuras según su propio reloj.

No es una liquidación laboral ni determina la legalidad de una jornada. El horario de presencia suma 53 h semanales antes de refrigerios. La equivalencia de 8 h y la compensación 1:1 requieren contrastarse con el acuerdo; los domingos y feriados tienen tratamiento específico. Referencia: [guía MTPE](https://www.gob.pe/institucion/mtpe/informes-publicaciones/6199835-como-calcular-las-horas-extras).

## Validación

Pruebas automáticas del cálculo: zona horaria, horarios, sábados, domingos, medianoche, pausas, estados de descanso y agrupación semanal. Se verifica el esquema SQL en PGlite con dos usuarios, aislamiento RLS, administrador, recálculo en servidor y saldo insuficiente. Se generan y reabren PDF/Excel para verificar el resumen. La conexión real con Supabase requiere ejecutar el esquema y verificar cuentas y correo en ese servicio.

Temas disponibles en la cabecera: Azul niebla (inicial), Gris metálico, Lavanda suave y Verde natural. La elección se guarda por navegador. Diseño comprobado a 393, 768 y 1440 píxeles; en teléfonos el registro de salida aparece antes de las métricas y los gráficos. Las tablas conservan desplazamiento horizontal cuando es necesario.

## Instalar como aplicación

La cabecera incluye **Instalar app**. En Android, abrir la dirección publicada desde Chrome o Samsung Internet y usar la instalación o Añadir a pantalla de inicio. En iPhone/iPad, Safari > Compartir > Añadir a pantalla de inicio. Nombre e icono: **myk2 Tiempo**. En escritorio se puede instalar con Chrome o Edge. El navegador decide cuándo habilitar el aviso nativo; la interfaz incluye instrucciones alternativas. No requiere contraseñas de Google/Chrome.

El service worker conserva únicamente recursos públicos del sitio. No almacena respuestas Supabase ni contraseñas. El modo local puede funcionar sin conexión después de una primera visita; el modo con cuentas necesita conexión para leer/escribir registros. No hay cola de cambios offline para cuentas sincronizadas. Las actualizaciones del service worker se activan cuando cierran las ventanas anteriores.

## Panel del dueño y estadísticas

Administración muestra registros totales y recientes, usuarios activos, sesiones, dispositivos, fuentes agregadas y actividad diaria de 30 días. El directorio incluye nombres, apellidos, correo, teléfono, DNI o CE, empresa, jornadas, saldo y acceso a sus registros. Solo un administrador asignado mediante SQL puede consultar el conjunto. Las contraseñas no son visibles; gestión de identidades y eliminación de cuentas desde Supabase.

La medición utiliza un UUID aleatorio por navegador y uno por pestaña. No guarda IP, ubicación precisa, contraseña ni URL de procedencia completa. Respeta Do Not Track/Global Privacy Control; bloqueadores o varias máquinas alteran los conteos. Dispositivos no equivale a personas y sesiones no equivale a páginas vistas. Se admiten hasta 20 sesiones por identificador en 24 h; estas métricas orientativas no son un sistema antifraude. Solo empiezan a medirse al configurar Supabase. El administrador puede conservar o borrar métricas desde la base de datos según su política de conservación.

