# myk2 Tiempo · v1.0.0

Aplicación responsive de horas extra y descansos compensatorios. © Ing. Mauro Espinoza · myk2 · mespinozahse@gmail.com · +51 975721020.

## Uso

Confirma tu salida con el reloj de Lima o edita fecha y hora. Lunes y martes se acumula desde 16:00; miércoles a viernes desde 17:00; sábado desde 12:00. Domingo, feriado o jornada atípica: registra inicio y fin. Marca explícitamente salida al día siguiente cuando corresponda. La pausa se descuenta del intervalo extra, no de la jornada ordinaria.

La equivalencia inicial es 8 h = 1 día, configurable. Solicitado no afecta saldo; aprobado reserva; gozado descuenta; cancelado libera. No se permite aprobar/gozar por encima del saldo. Los registros existentes conservan sus horas al cambiar la equivalencia o el horario. El estado de descanso es un registro personal de la autorización empresarial, no un circuito de aprobación laboral.

PDF y Excel incluyen agrupación diaria, semanal (lunes a domingo) o mensual, filtros de fechas, detalle y comentarios. Excel contiene tablas editables con filtros y un gráfico incorporado como imagen. El neto del informe corresponde al período filtrado, no al saldo histórico.

## Publicación

Publicado en https://mauroespinoza2022.github.io/myk2-tiempo/ mediante GitHub Actions. Cada cambio en `main` ejecuta pruebas, compila y publica automáticamente a través de `.github/workflows/pages.yml`. El código fuente se mantiene junto con un lockfile.

`npm ci`, `npm test`, `npm run build`. El resultado está en `dist/`. Sin las variables públicas de Supabase se activa modo local, visible en toda la aplicación. No simula cuentas ni sincronización. Exporta respaldos JSON antes de borrar los datos del navegador. Esos respaldos contienen datos personales.

## Activar cuentas, administrador y sincronización

1. Crear un proyecto Supabase. Ejecutar `supabase/schema.sql` una vez en su SQL Editor.
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
