# myk2 Tiempo · Versión 1

La web puede publicarse en GitHub Pages sin un servidor propio. Las cuentas, recuperación por correo, permisos y datos compartidos requieren un proyecto Supabase. El modo local no crea cuentas ni comparte información entre dispositivos.

## Activar el servicio

1. En un proyecto nuevo, ejecutar en el SQL Editor, una sola vez y en este orden: `schema.sql`, `002_admin_analytics.sql`, `003_identity_fields.sql`, `004_admin_management.sql`, `005_company_roles.sql` y `006_access_hardening.sql`, todos dentro de `supabase/`. En un proyecto existente, ejecutar únicamente las migraciones pendientes. No volver a ejecutar el esquema sobre datos existentes.
2. En Authentication, habilitar registro por correo y contraseña y confirmación del correo. Configurar el envío SMTP para producción. Comprobar la entrega real de confirmaciones y recuperaciones.
3. Configurar Site URL y Redirect URL con `https://mauroespinoza2022.github.io/myk2-tiempo/`.
4. En GitHub, Settings → Secrets and variables → Actions → Variables, crear `VITE_SUPABASE_URL` y `VITE_SUPABASE_ANON_KEY`. La segunda admite la clave pública anon o publishable. Nunca usar service_role ni una clave secreta. Ejecutar de nuevo el workflow de Pages para incorporar la configuración pública.

## Primera cuenta del desarrollador

En la portada seleccionar **Desarrollador**, luego **Crear cuenta**. Registrar `mespinozahse@gmail.com`, los datos personales reales y una contraseña nueva exclusiva de esta aplicación. La empresa puede quedar vacía para esta cuenta. Confirmar el correo recibido e ingresar seleccionando **Desarrollador**. El permiso se comprueba en la base de datos y exige el correo confirmado; elegir el rol en la pantalla no concede privilegios.

No hay contraseña predeterminada ni contraseña almacenada en GitHub. Para recuperarla, usar **Olvidé mi contraseña**; el enlace llegará al correo de la cuenta si el servicio de envío está configurado. No se solicita la contraseña de Google ni de Chrome.

## Empresas y administradores

El desarrollador crea las empresas en Administración. Los usuarios se registran eligiendo una empresa y confirman su correo. El desarrollador asigna el rol Administrador al correo confirmado y a la empresa correspondiente. Puede devolverlo al rol Usuario para retirar sus permisos administrativos. No se permite sustituir el rol del propietario ni trasladar una cuenta con historial a otra empresa mediante esa operación.

El administrador consulta usuarios, registros, saldos, solicitudes, aprobaciones y consolidados únicamente de su empresa. El desarrollador tiene visión global. Los usuarios solicitan descansos; la aprobación, confirmación y modificación de descansos confirmados corresponde a quien administra la empresa. Las asignaciones de roles y los cambios de jornadas y descansos quedan en la trazabilidad.

## Verificación antes de usar cuentas reales

Probar registro, confirmación, inicio y cierre de sesión, recuperación de contraseña y entrega de correos. Crear dos empresas de prueba y comprobar sus administradores por separado. Las pruebas automáticas verifican las políticas SQL, pero no sustituyen esta comprobación de configuración del proyecto y correo.
