# Golf Instinct: Garmin Instinct E 40 mm

Proyecto inicial de una aplicacion de reloj Connect IQ, escrita en Monkey C.
Dispositivo objetivo: **Instinct E 40 mm**, identificador `instincte40mm`.
Garmin confirma Watch App, pantalla monocroma de 166 x 166 y manejo por botones.
No es el Instinct original, el Instinct 2S ni el Instinct E de 45 mm.

**Estado: NO verificada para publicacion.** El codigo tiene comprobaciones
estructurales, pero no se ha compilado ni ejecutado en el simulador. En este
equipo falta el SDK, el Java activo es 8 y la red ha bloqueado las consultas
de descarga de herramientas y la consulta de datos reales. No hay un `.iq`
validado para subir. No confundas ausencia de diagnosticos con pruebas pasadas.

## Que incluye

- Pantalla de juego con hoyo, par, distancia, golpes y control + asociado al boton GPS.
- Contador de golpes, tarjeta editable y total de la vuelta para hasta 18 hoyos.
- Putts, penalizaciones y resultado respecto al par de los hoyos terminados.
- Correccion de golpes, navegacion entre hoyos y resumen.
- Guardado automatico local: al salir y volver a abrir se recupera la vuelta.
- Nueva vuelta con confirmacion antes de borrar los datos.
- Busqueda de hasta 12 campos OSM en un radio de 20 km, solicitada por el usuario.
- Descarga secuencial de los hoyos numerados del campo seleccionado y par si existe.
- Campo actual y biblioteca propia de hasta tres campos offline.
- Tarjetas manuales de 9/18 hoyos y marcado GPS de un punto del green.
- GPS local y distancia aproximada en metros al final del recorrido OSM del hoyo.
- Consentimiento antes de activar GPS o enviar la ubicacion a Overpass.
- Metros/yardas y medicion manual de la distancia recta de un golpe.
- Inicio, pausa, reanudacion, guardado y descarte de actividad FIT de golf.
- Campos FIT de resumen: golpes, putts, penalizaciones y hoyos terminados.
- Pruebas de limites, totales, datos publicos, distancias, cache y errores.

No incluye handicap, Stableford, deteccion automatica de golpes ni tarjeta nativa
de Garmin Golf. No accede al catalogo de Garmin ni a los campos que guardas en
Garmin Connect. La grabacion FIT se implementa con la API oficial ActivityRecording;
su creacion, guardado y sincronizacion concreta aun requieren validacion.
La descarga requiere telefono vinculado, Garmin Connect con acceso a Internet
y Bluetooth. Los datos descargados y el contador funcionan sin red; para mostrar
distancias hay que activar GPS y obtener una posicion fiable.

## Alcance real frente a un Approach

Esto es una Watch App independiente, no una sustitucion del firmware. Al
instalarla, se busca **Golf Instinct** en las aplicaciones/actividades del reloj;
no crea ni modifica el perfil de golf nativo. Declarar SPORT_GOLF en FIT no
habilita automaticamente funciones de un Garmin Approach.

Connect IQ no proporciona en las API publicas documentadas que usa este proyecto
una forma de leer tus campos descargados en Garmin Connect/Garmin Golf.
**Mis campos offline** es una biblioteca de esta app, no esa lista de Connect.
Tampoco hay integracion implementada con AutoShot, sensores CT10, Virtual Caddie,
PlaysLike, viento, mapas de color o posiciones actuales de bandera.
No se promete equivalencia con un reloj de golf ni una app al 100% verificada.

Funciones de referencia habituales en golf: distancia, puntuacion, tarjeta,
estadisticas, medida de golpe y actividad. Se han implementado las variantes
manuales/accesibles; frente/centro/fondo del green, obstaculos y cambio automatico
de hoyo no estan implementados porque los datos actuales no permiten ofrecerlos
de forma fiable sin inventar informacion.

## Flujo de juego

El menu principal tiene seis accesos: **Anotar hoyo**, **Tarjeta**, **Medir golpe**,
**Actividad**, **Campos** y **Mas opciones**. Los campos se gestionan en **Campos**;
estadisticas, GPS, unidades, privacidad y vistas secundarias estan en **Mas opciones**.
No hay que recorrer todas las funciones avanzadas para anotar un golpe.

En **Jugar**, GPS suma un golpe y UP resta uno. DOWN abre **Anotar hoyo** con
**Cerrar hoyo** seleccionado primero: DOWN y GPS cierran un hoyo con puntuacion
y avanzan. Los hoyos anteriores se editan desde **Tarjeta**, sin cambiar de hoyo
accidentalmente al corregir un golpe. El ultimo hoyo no avanza mas alla del final.

Para editar un numero, selecciona **Golpes**, **Par**, **Putts** o **Penalizaciones**
en **Anotar hoyo**. El editor muestra el valor grande y su rango permitido:
UP aumenta, DOWN disminuye, GPS confirma y BACK cancela sin guardar cambios.
No hace falta volver a abrir el menu por cada unidad. Al iniciar o reanudar la
grabacion se vuelve a Jugar; al guardar se muestra el resumen de la vuelta.

1. Descarga un campo OSM o crea **Campo manual 9/18 hoyos**. El cambio requiere
   confirmacion, borra la tarjeta actual y se bloquea durante una actividad FIT.
2. Usa **Guardar campo offline** y **Mis campos offline** para reutilizarlo.
   La biblioteca admite tres campos por el limite de memoria del reloj. Un campo
   con el mismo nombre sustituye la entrada anterior; no hay teclado para renombrar.
3. En **Actividad**, acepta **Iniciar GPS + FIT**. El aviso autoriza grabar datos
   de GPS para sincronizarlos con Connect. Espera un fix fiable para las distancias.
4. En **Jugar** ves hoyo, PAR, distancia y golpes. El + de la subpantalla indica
   la accion del boton fisico GPS: sumar un golpe. El reloj NO es tactil.
5. En **Anotar hoyo** corrige golpes, define par si falta, cuenta putts y anade
   penalizaciones. Los putts son parte del total: anota antes el golpe; sumar una
   penalizacion SI suma tambien un golpe. No se permite quitar golpes por debajo
   de los putts y penalizaciones ya anotados.
6. **Cerrar hoyo** lo marca terminado y avanza; no cierra un hoyo con cero golpes.
   En **Tarjeta** puedes seleccionar cualquier hoyo y corregirlo. Modificar golpes
   reabre el hoyo para que confirmes de nuevo su finalizacion.
7. **Estado / campo** muestra resultado respecto al par, putts, penalizaciones,
   hoyos terminados y coordenadas actuales cuando hay GPS fiable. No se inventa
   el par ausente: el resultado respecto al par queda sin datos si falta en algun
   hoyo terminado. No hay deteccion automatica de que hayas cambiado de hoyo.
8. **Medir golpe**: pulsa GPS en esa pantalla para marcar el origen y camina hasta
   la bola. Mide distancia recta, no trayectoria ni carry. No suma golpes solo.
   La marca no se reutiliza en otro hoyo y desaparece al cambiar de campo.
9. **Finalizar y guardar** termina el FIT; despues Garmin Connect lo sincroniza
   por el procedimiento normal del reloj. **Descartar FIT** no borra la tarjeta
   local. BACK durante una grabacion abre el menu de actividad en vez de salir.
   Si el sistema fuerza la salida normal, se intenta guardar automaticamente;
   no se garantiza recuperar FIT despues de un fallo del dispositivo.

Para un campo manual, registra el par desde **Anotar hoyo**. **Marcar green aqui**
requiere estar fisicamente en el punto del green que quieres guardar, con GPS
fiable y confirmacion. No descubre el green desde una ubicacion cualquiera.
El punto aparece como GREEN GPS, sin afirmar que sea el centro o la bandera.
No hay importador de campos de Connect ni editor de coordenadas desde el movil.

## Campos publicos y limitaciones

Fuente: **OpenStreetMap contributors**, bajo **ODbL 1.0**.
API publica sin clave: <https://overpass.private.coffee/api/interpreter>.
La politica del servicio figura en <https://wiki.openstreetmap.org/wiki/Overpass_API>.
No es una API oficial de golf de Garmin y no tiene disponibilidad garantizada.
Para una distribucion a gran escala debes acordar capacidad con el proveedor.

Desde MENU elige **Buscar campos**, acepta enviar tu ubicacion y espera el GPS.
Selecciona el campo; confirma el cambio y espera que termine la descarga.
Solo al completarse se sustituye el campo guardado y se borra la vuelta previa.
Usa **Distancia OSM** para ver metros aproximados y **Puntuacion** para anotar golpes.
Al volver a abrir, el campo sigue guardado, pero GPS no se activa automaticamente.
Usa **Activar GPS**; **Apagar GPS** detiene el sensor sin borrar los datos.

La busqueda se limita a una consulta nueva cada cinco minutos mientras la app
esta abierta. No hace consultas periodicas ni reintentos automaticos.
Descarga primero la numeracion y despues cada hoyo individual para evitar
respuestas de geometria grandes en un reloj con 128 KiB para Watch App.
El limite real de memoria todavia debe medirse con el simulador del dispositivo.

La cobertura OSM varia. Solo se admiten campos delimitados como way/relation
`leisure=golf_course`, con nombre y area utilizable por Overpass, y hoyos
`golf=hole` con `ref` numerico unico de 1 a 18. Campos con varios recorridos que
repiten numeros se rechazan en lugar de mezclar sus hoyos. La lista no garantiza
incluir todos los campos ni estar ordenada por distancia. Algunos campos no
tienen hoyos, tienen numeracion incompleta o carecen de area en Overpass.
Los huecos de numeracion se muestran sin datos, sin inventar coordenadas.

**La distancia no es a la bandera ni necesariamente al centro del green.**
Se usa el ultimo punto del recorrido mapeado del hoyo, que OSM define desde tee
hacia green/pin. No se muestran frente/fondo del green ni distancias de torneo
certificadas. Sin posicion GOOD reciente (15 segundos) o sin coordenadas,
se muestra `--`, nunca un cero ficticio. Distancias mayores de 9999 m se ocultan.

## Privacidad y atribucion

GPS esta desactivado al iniciar. **Activar GPS** lo utiliza localmente.
**Buscar campos** pide un consentimiento distinto antes de enviar latitud y
longitud redondeadas a cinco decimales a Overpass Private.coffee por HTTPS;
ese servidor y la infraestructura de conexion pueden recibir la IP y datos
tecnicos de la solicitud. No se envia puntuacion, cuenta Garmin ni historial GPS.
El telefono hace de puente mediante Garmin Connect; su tratamiento corresponde
a las condiciones de Garmin. No hay servidor propio, publicidad ni analitica.

**Iniciar GPS + FIT** es un consentimiento separado para grabar la actividad
y permitir su sincronizacion con Garmin Connect. El FIT contiene los datos que
graba Garmin con el GPS habilitado y los cuatro totales de puntuacion; no es una
tarjeta nativa Garmin Golf. El guardado local por si solo no sube la puntuacion.
Las coordenadas de los puntos manuales del green se guardan en la biblioteca local.

Campo y puntuacion se guardan juntos localmente. **Nueva vuelta** sustituye
la puntuacion; **Borrar campo** elimina el campo y reinicia la vuelta.
El menu **Datos / privacidad** muestra origen, licencia y aviso de ubicacion.
Antes de publicar, completa una politica de privacidad con tu identidad y
contacto de soporte, publicala en una URL accesible y declarala en la tienda.
Referencia de atribucion/licencia: <https://www.openstreetmap.org/copyright>.

## 1. Preparar Windows y VS Code

1. Instala Java JDK 17 o superior y comprueba `java -version`.
2. Instala la extension oficial **Monkey C**, de Garmin (`garmin.monkey-c`).
3. Descarga el **Connect IQ SDK Manager** desde
   <https://developer.garmin.com/connect-iq/sdk/>.
4. Abre SDK Manager e inicia sesion con tu cuenta Garmin directamente en su ventana.
   Instala un SDK estable reciente y seleccionalo como activo.
5. En la pestana Devices descarga **Instinct E 40mm**. Si no aparece, actualiza
   SDK Manager y su catalogo; no lo sustituyas por otro modelo.
6. En VS Code, `Ctrl+Shift+P` > **Monkey C: Verify Installation**.
7. Ejecuta **Monkey C: Generate a Developer Key**. Guarda la clave fuera del
   repositorio y configura **Monkey C: Developer Key Path** si es necesario.
   Conserva esa clave para futuras actualizaciones; no la compartas ni la subas a Git.

## 2. Probar en el simulador

1. Abre esta carpeta en VS Code.
2. Pulsa `F5` y selecciona **Golf - Instinct E 40mm**.
3. Si la extension pide el dispositivo, selecciona **instincte40mm**.
4. Comprueba la pantalla real del simulador: encabezado arriba a la izquierda,
   sin invadir la subpantalla circular superior derecha; contador en la zona inferior.

Controles esperados en el reloj y simulador:

| Boton | Accion |
| --- | --- |
| GPS / seleccionar | Sumar golpe en Jugar/Puntuacion/Distancia; marcar origen en Medir golpe |
| UP | Restar golpe en Jugar/Puntuacion; hoyo anterior en Distancia |
| DOWN | Anotar/cerrar hoyo en Jugar; hoyo siguiente en Puntuacion/Distancia |
| Mantener MENU / UP | Menu de puntuacion, campos, GPS y privacidad |
| BACK / SET | Volver a Jugar; en Jugar abre actividad si hay FIT pendiente o sale si no |

El menu utiliza los controles nativos del reloj. Los nombres fisicos pueden
variar con el idioma; verifica su correspondencia en el simulador.
En resumen no se cambian golpes ni hoyos accidentalmente.

Prueba manual: suma dos golpes, cambia de hoyo, suma uno y verifica total 3.
Sal y abre de nuevo: debe mantener el hoyo y los golpes. Cancela una nueva vuelta
y comprueba que conserva los datos; confirma el borrado y comprueba total 0.

Las pruebas Monkey C estan disponibles en el explorador de pruebas de la
extension. Configura **instincte40mm** como dispositivo. Desde la consola de
Windows, compila con `-t` y ejecuta con `monkeydo ... /t`.

## 3. Compilar desde PowerShell (opcional)

Una vez instalado el SDK, sustituye las rutas por las tuyas. No se incluye una
clave privada en el proyecto.

```powershell
$sdkBin = 'C:\ruta\al\connectiq-sdk\bin'
$key = 'C:\ruta\privada\developer_key.der'
New-Item -ItemType Directory -Force bin | Out-Null
& "$sdkBin\monkeyc.bat" -f monkey.jungle -d instincte40mm -y $key -o bin\GolfInstinct.prg
& "$sdkBin\connectiq.bat"
& "$sdkBin\monkeydo.bat" bin\GolfInstinct.prg instincte40mm
```

Para pruebas, con el simulador abierto:

```powershell
& "$sdkBin\monkeyc.bat" -f monkey.jungle -d instincte40mm -y $key -t -o bin\GolfTests.prg
& "$sdkBin\monkeydo.bat" bin\GolfTests.prg instincte40mm /t
```

### Verificacion reproducible y exportacion

Con Java compatible y el simulador oficial abierto, ejecuta:

```powershell
.\scripts\verify.ps1 -SdkBin $sdkBin -DeveloperKey $key
```

Este comando compila para `instincte40mm`, ejecuta todas las pruebas y compila
la version release. Se detiene ante un error o un resumen de pruebas que no
pueda confirmar. Guarda la salida de las pruebas en `bin/test-results.log`.
No sustituye la verificacion visual o de Internet real. Para exportar despues
de esos controles, usa el mismo comando con `-Export`.

Antes de considerar lista la app, faltan estos controles con el SDK real:

- Compilacion de pruebas y release exclusivamente para Instinct E 40mm.
- Todas las pruebas unitarias sin fallos ni errores.
- Capturas reales de puntuacion, distancias y menus a 166 x 166, sin solapamientos.
- GPS simulado: sin fix, fix GOOD, desplazamiento, perdida de fix y GPS apagado.
- Descarga real de un campo mapeado, par, regreso offline y reapertura de la app.
- Desconexion del telefono, respuesta 429, timeout y cancelacion durante descarga.
- Nueva vuelta/cambio de campo, confirmacion y conservacion del campo anterior ante error.
- Memoria por debajo de 131072 bytes, incluida la respuesta API mas grande.
- Menus de edicion, par desconocido, putts/penalizaciones y reapertura de hoyo.
- Editor numerico: limites, confirmacion, cancelacion y cambio de campo durante edicion.
- Acceso rapido GPS/UP/DOWN y estados de campo ausente, GPS apagado y sin fix.
- Inicio/pausa/reanudacion/guardado/descarte FIT, errores de almacenamiento y salida.
- Validacion del FIT real y de sus cuatro campos en Monkey Graph/Garmin Connect.
- Biblioteca de tres campos, persistencia de unidades y tarjetas manuales sin GPS.

La prueba de red de escritorio no demuestra el puente Bluetooth del telefono.
La compatibilidad de plataforma esta documentada por Garmin, pero la validacion
de esta app concreta requiere estas ejecuciones. Las pruebas en reloj fisico
siguen siendo recomendables incluso si todas las pruebas del simulador pasan.

## 4. Instalar en tu reloj por USB

1. Actualiza el firmware con Garmin Connect o Garmin Express.
2. Compila para **instincte40mm**, no para otro reloj. Puedes usar
   **Monkey C: Build for Device** desde la paleta de comandos.
3. Conecta el reloj por USB con un cable que permita transferencia de datos.
4. Si Windows muestra su almacenamiento, coloca el archivo `.prg` compilado en
   **GARMIN/APPS**. Si no aparece, comprueba cable, modo USB y las indicaciones
   de Garmin para tu modelo; no formatees el reloj.
5. Expulsa/desconecta de forma segura. Busca **Golf Instinct** en la lista de
   actividades/aplicaciones del reloj.

No necesitas publicar en Connect IQ Store para tus pruebas por USB. No copies
los archivos `.mc` al reloj: necesita el `.prg` compilado y firmado.

## 5. Publicar e instalar sin cable

Solo cuando se completen las verificaciones anteriores, ejecuta **Monkey C:
Export Project** o `scripts/verify.ps1 ... -Export` para obtener el `.iq`.
Subelo desde <https://apps.garmin.com/en-US/developer/upload> usando tu propia
cuenta Garmin. No cambies el identificador de la app ni la clave entre versiones.
Completa descripcion, capturas del simulador, soporte y politica de privacidad.
Declara que es una app independiente para **Instinct E 40mm**, con cobertura
OSM variable, distancias aproximadas y telefono necesario para descargar campos.
No afirmes que incluye todos los campos, posicion exacta de bandera o Garmin Golf.

Garmin indica que el autor puede descargar su app para probarla mientras esta
pendiente de aprobacion: <https://developer.garmin.com/connect-iq/submit-an-app/>.
La instalacion de tienda se sincroniza desde el telefono vinculado por Bluetooth.
Enviar el paquete no garantiza aprobacion ni publicacion inmediata.

## Donde desarrollar

- `source/GolfRound.mc`: puntuacion, limites y recuperacion de datos.
- `source/GolfView.mc`: pantalla de 166 x 166.
- `source/GolfDelegate.mc`: botones, menu y confirmacion de borrado.
- `source/GolfApp.mc`: ciclo de vida y almacenamiento local.
- `source/GolfRoundTests.mc`: pruebas del modelo.
- `source/GolfCourseData.mc`: validacion de OSM, cache y distancias geograficas.
- `source/GolfCourses.mc`: red, GPS, consentimiento de seleccion y descarga.
- `source/GolfRecording.mc`: ciclo de grabacion FIT y campos de resumen.
- `resources/fitcontributions/fitcontributions.xml`: metadatos de resumen para Connect.
- `scripts/verify.ps1`: compilacion/pruebas para el dispositivo y exportacion opcional.
- `manifest.xml`: producto objetivo, tipo de app y permisos.

Este proyecto no presupone acceso al catalogo de campos de Garmin ni a sus
funciones nativas de golf. Guarda el campo actual y hasta tres favoritos, no una
biblioteca mundial ni los campos de tu cuenta Garmin.

## Referencias oficiales

- Dispositivo: <https://developer.garmin.com/connect-iq/device-reference/instincte40mm/>
- Instalacion: <https://developer.garmin.com/connect-iq/connect-iq-basics/getting-started/>
- Primera app: <https://developer.garmin.com/connect-iq/connect-iq-basics/your-first-app/>
- API: <https://developer.garmin.com/connect-iq/api-docs/>
- Grabacion FIT y resumen en Connect: <https://developer.garmin.com/connect-iq/core-topics/activity-recording/>

La compilacion, pruebas Monkey C y disposicion visual requieren el SDK y el
perfil del dispositivo. La comprobacion de XML/JSON por si sola no las sustituye.