# DagaWASD

[English](README.md) · [Italiano](README.it.md) · **Español** · [Français](README.fr.md) · [Deutsch](README.de.md) · [Português](README.pt.md) · [Nederlands](README.nl.md) · [Svenska](README.sv.md) · [Polski](README.pl.md) · [Čeština](README.cs.md) · [Русский](README.ru.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [中文](README.zh.md)

Extensión para SketchUp (Windows): recorre tu modelo en primera persona con
WASD y el ratón, o con un mando.

▶ Presentación oficial: https://youtu.be/8eBvtl7DiKU

▶ Vídeo de demostración: https://youtu.be/w6xE86y7iEw?is=7Gh12tF7atE_N9_K

⬇ **Descargar**: [última versión](https://github.com/Dagadam/dagawasd/releases/latest) (todas las versiones: [Releases](https://github.com/Dagadam/dagawasd/releases))

## Qué hace

- **Caminar**: inercia, correr, agacharse, saltar, escaleras y pendientes, y
  vuelta segura al suelo si caes al vacío.
- **Física de objetos**: grupos y componentes caen, rebotan y vuelcan según
  su material; se pueden patear, agarrar y lanzar.
- **Cielo y clima**: sol, luna y estrellas según la fecha, la hora y el
  lugar; lluvia, nieve, nubes, tormentas, nieve que cuaja en el suelo.
  Situaciones listas y tiempo variable que cambia solo con el tiempo del
  cielo. El tiempo también aparece en los vídeos exportados.
- **Recorridos**: graba la cámara mientras caminas, reprodúcela, expórtala
  como escenas o como vídeo AVI. Retócala en el modelo moviendo y girando sus
  posiciones (esferas con una flecha tan larga como el zoom, y el marco del
  encuadre), o construye uno desde cero. En el panel cada recorrido se abre
  con la lista de sus posiciones; un clic en una posición, o un doble clic en
  su esfera (o Intro), abre sus ajustes con una vista previa de lo que ve, y
  un clic entre dos posiciones añade una desde la vista actual. Durante la
  reproducción la lista ilumina la posición en curso. «Aclarar cámaras» une
  las esferas amontonadas unas sobre otras en una sola, su media (posición,
  mirada, zoom), si no miran a más de 45° entre sí.
- **Explorador autónomo**: la cámara mira la escena, elige lo más
  significativo, da un paso hacia ello mirándolo y vuelve a empezar; al final
  el paseo es un recorrido. Ver más abajo.
- **Fotos y galería**: P hace una foto de lo que ves; el explorador
  fotografía por sí mismo lo más interesante de su paseo. Cada recorrido
  abre su galería en el navegador: fotos instantáneas sobre una mesa, con
  notas. Ver más abajo.
- **Mando** XInput, y mirar alrededor con el teclado numérico.
- Panel de ajustes en 36 idiomas.
- **Accesibilidad**: *Accesibilidad › Sin destellos* apaga todos los
  destellos, de las fotos y de los relámpagos (ver
  [ACCESSIBILITY.md](.github/ACCESSIBILITY.md)).

Requisitos: SketchUp 2023 o posterior, en Windows. En Mac la extensión se
instala pero no arranca, y lo dice.

## Instalación

- Desde el **Extension Warehouse** de SketchUp (versión firmada), o
- descarga **`dagawasd-<versión>-warehouse.rbz`** de la
  [última versión](https://github.com/Dagadam/dagawasd/releases/latest) (en *Assets*) e instálalo desde
  *Extensiones › Administrador de extensiones › Instalar extensión*. El
  otro archivo, `dagawasd-<versión>.rbz`, contiene además el puente para
  Claude Code (ver *Dos paquetes*).

Los ajustes se guardan en `%APPDATA%\DagaWASD\settings.json`: una
actualización no los borra.

## Explorador autónomo

Botón del ojo en la barra (o *Extensiones › DagaWASD › Explorador
autónomo*): una pequeña ventana permite elegir el perfil (su carácter, ver
más abajo) y si grabar el paseo como recorrido, y recuerda tus elecciones
para la próxima vez; flechas e Intro, o doble clic en un perfil, para salir
enseguida. El mismo botón lo detiene mientras explora. El ciclo:
**analiza → elige el punto → un paso hacia el punto, mirándolo → analiza**.

- **Análisis**: una retina de rayos a través de la cuadrícula de la pantalla
  (`view.pickray` + `model.raytest`) da, para cada celda, distancia, normal,
  cara, objeto y color. De ahí la prominencia: bordes de profundidad,
  aristas, detalle, contraste de color (Lab), rareza, componentes y grupos a
  escala humana; las paredes y los suelos grandes cuentan poco. Ponderada por
  distancia, centro de la vista y novedad.
- **Memoria**: vóxeles de lo que la mirada ya ha visto, lugares ya pisados
  (en planta y en altura: el piso de arriba sigue siendo nuevo), aburrimiento
  por objetivo y por categoría (visto un sofá, los demás iguales interesan
  menos): así no vuelve siempre a las mismas cosas.
- **Plano de lo que ha visto**: a pie, los rayos que pasan a la altura del
  cuerpo marcan en un plano de celdas de 50 cm (uno por piso) el suelo visto
  con su altura (suelo, escalones, superficies de muebles) y las paredes
  alcanzadas. Sirve para dos cosas:
  - **fronteras**: el borde entre lo que ha visto y lo que nunca ha visto
    (tras una puerta, detrás de una esquina) se convierte en un objetivo,
    una «zona inexplorada»: va allí y mira dentro. Pesa como el espacio
    abierto, según las ganas de moverse del perfil; en el mapa de atención
    son los cuadraditos morados en el suelo;
  - **rutas planificadas**: para cada objetivo traza el camino sobre el plano
    (A*) hasta un punto desde el que se ve: alrededor de paredes y muebles,
    manteniendo algo de distancia, escaleras arriba (un escalón cada vez sí,
    una mesa o un sofá no) y por pendientes hasta la pendiente máxima del
    jugador, en línea recta donde puede. Donde aún no ha mirado es optimista
    y lo intenta. En cada análisis vuelve a comprobar el resto de la ruta en
    el plano nuevo y, si ahora está bloqueada, busca otra; cada 3 s la rehace
    de todos modos (quizá ha visto un atajo); donde choca, lo marca y
    recalcula. Si el objetivo desaparece detrás de algo, o la ruta se aleja
    de él, mira hacia dónde va. La ruta en curso es la línea discontinua en
    el suelo. La búsqueda trabaja por porciones, como el análisis.
- **Paso**: hacia el punto, rodeando obstáculos, subiendo escaleras, nunca
  bajando de un borde; se detiene a una distancia desde la que el objeto se
  ve entero y lo mira. Desde una vista aérea vuela y aterriza donde hay algo.
- **Rodear los objetos**: al llegar a un objeto, si el perfil lo pide
  (*Rodea los objetos*, en grados: Fotógrafo 180°, Curioso 90°) lo rodea
  mirándolo, por el lado más libre, para verlo desde varios lados; si el
  camino se cierra, da la vuelta. Luego la pausa.
- **Salto**: un obstáculo bajo que corta el paso (un murete, una valla, un
  escalón grande) sin un rodeo corto lo salta, si al otro lado hay una
  superficie donde aterrizar. Usa la fuerza de salto y la gravedad del
  jugador (con las predeterminadas los pies suben 1,08 m; salta lo que está
  por debajo del 85 % de esa altura); nunca salta sobre asientos ni mesas.
  Se desactiva en el perfil (el Lento no salta).
- **Cuerpo**: altura de los ojos, radio, escalón (como mucho 25 cm), salto y
  gravedad son los del jugador (panel › Jugador), aunque se cambien mientras
  explora.
- **Fluido**: como la construcción en directo del puente, el análisis es una
  Fiber que trabaja por porciones entre un fotograma y otro; la retina se
  ensancha o se estrecha según lo que cuesta un rayo en ese modelo. Con
  *Sistema › Rendimiento › Análisis adaptativo* también la frecuencia de los
  análisis sigue la capacidad de cálculo libre, entre un mínimo y un máximo
  por segundo, sin frenar la marcha.
- **Controles**: Esc o clic para detenerlo, botón derecho para pausar,
  «Buscar otra cosa», mapa de atención, ojo en color; rueda para la
  velocidad; I oculta o muestra las líneas de información arriba a la
  izquierda. Otra herramienta lo detiene; orbitar con el botón central lo
  suspende, y vuelve a salir desde donde pusiste la cámara.
- **¿Atascado?** Si en 10 segundos no se mueve 75 cm (indeciso entre
  objetivos cercanos, encerrado en una esquina), busca una vía de escape
  entre 12 direcciones y la sigue unos segundos; si a pie no hay salida y el
  modo es automático, alza el vuelo.
- **Al final**, si al empezar dejaste marcado «Grabar el recorrido», el
  paseo se convierte en un recorrido («Exploración 1», …): desde el panel lo
  vuelves a ver, o lo conviertes en escenas o en vídeo.

### Perfiles

El carácter del explorador es un **perfil**, un conjunto de coeficientes:
*Extensiones › DagaWASD › Perfiles del explorador…*, o botón derecho
mientras explora › *Perfil* (cambio al vuelo) y *Editar perfiles…*.

| Perfil | Carácter |
|---|---|
| Equilibrado | el de siempre |
| Curioso | se aburre pronto, busca detalles y cosas raras, explora más, rodea los objetos 90° |
| Corredor | 3,2 m/s, reflejos rápidos, pausas cortas |
| Lento | 0,5 m/s, pausas largas, una mirada que gira despacio |
| Fotógrafo | antes de acercarse amplía el objetivo (zoom), luego va y lo rodea 180° |
| Despreocupado | elecciones caprichosas, cambia de idea fácilmente, le encanta el espacio abierto |
| Soldado | reconocimiento, siempre a pie: 3,6 m/s, mira de lejos y poco rato, va primero donde aún no ha mirado |

En la ventana cada coeficiente tiene un deslizador (mientras lo arrastras,
el explorador, si usa ese perfil, cambia en directo) y un ↺ que lo devuelve
al valor original. Grupos: movimiento (velocidad, distancia de parada,
escalón, a pie/en vuelo), mirada (giro, reflejos, **continuidad** — cuánto
prefiere pasar a lo que está junto a lo que mira y no volver a lo que ya ha
dejado atrás), atención (pausa, rodear los objetos, duración,
**determinación** — durante cuántos segundos no cambia de idea sobre un
objetivo recién elegido — y **fidelidad**), curiosidad (memoria,
aburrimiento, ganas de moverse, capricho), lo que le atrae (pesos de
objetos, siluetas, detalle, color, rareza) y zoom. «Nuevo» copia el perfil
en uso; los perfiles predefinidos se pueden cambiar y luego restaurar.

En `settings.json`: `"explore_profile"` (el que está en uso),
`"explore_profiles"` (los tuyos, y los cambios a los predefinidos) y
`"explore_record"` (la casilla del recorrido de la ventana de inicio). Los
valores se suman por capas: predeterminados (`EX_DEFAULTS`,
`lib/explore.rb`) ← `"explore": { … }` ← perfil ← opciones de quien lo
inicia (el puente).

Con el puente activo, Claude Code lo controla y lo observa (los comandos de
las herramientas de desarrollo están en italiano):

```
ruby tools/esplora.rb avvia --secondi 120 --velocita 1.3   # inicia: 120 s, 1,3 m/s
ruby tools/esplora.rb avvia --profilo Fotografo    # un perfil solo para este paseo
ruby tools/esplora.rb profili                      # lista; «profilo NOMBRE» lo pone en uso
ruby tools/esplora.rb segui --foto esplorazione    # una línea y una foto por cada elección
ruby tools/esplora.rb ferma                        # lo detiene y guarda el recorrido
```

### La IA al volante

Con `pilota` y `guida` es Claude Code quien decide adónde ir, mientras el
explorador sigue caminando y mirando por sí mismo (`lib/expilot.rb`). Cada
cosa vista tiene un nombre corto y estable (`o12` un objeto, `s7` una cara,
`F3` una zona inexplorada); la IA pone destinos en una agenda, y el
explorador los alcanza uno tras otro con sus propios pasos, sus rodeos
alrededor de las paredes y su mirada. Con la agenda vacía vuelve a elegir
por sí mismo: nunca se detiene a esperar a la IA.

```
ruby tools/esplora.rb pilota                       # espera un aviso y describe lo que ve
ruby tools/esplora.rb guida --vai o12 --giro 90 --commento "El altar mayor" --vai F3
ruby tools/esplora.rb guida --guarda o7 --per 3    # se gira a mirar, sin moverse
ruby tools/esplora.rb guida --piace label:colonna=2 --evita o4
ruby tools/esplora.rb guida --sostituisci --punto 12,4,1.7   # agenda nueva: un punto en metros
ruby tools/esplora.rb guida --svuota               # sin agenda: vuelve a elegir por sí mismo
ruby tools/esplora.rb guida --foto                 # una foto en la pausa actual (o la siguiente)
ruby tools/esplora.rb guida --foto-sempre          # una foto en cada pausa (--foto-mete: solo en los destinos de la IA, --senza-foto)
```

Los avisos que despiertan a `pilota`: destino alcanzado, destino cumplido (o
abandonado, y por qué), agenda casi vacía o vacía, un destino inalcanzable,
algo notable nunca visto, una foto.

**A pie: adónde se llega.** Caminando, la descripción dice para cada cosa y
zona inexplorada si se puede llegar (`reach`: sí, quizá pasando por zonas
nunca vistas, no) y con cuántos metros de camino (`walk_m`), según el plano
que el explorador se ha hecho mirando. Un «ve» hacia algo a lo que no se
llega a pie se rechaza enseguida, con el motivo; en las fotos esas cosas
llevan la etiqueta gris claro. En Stromboli el piloto autónomo pasó de
alrededor de un destino alcanzado por minuto a tres.

**Fotos con etiquetas.** En las pausas ante los destinos de la IA el
explorador, quieto y con la mirada en el destino, toma una imagen de la
vista (800 px) y escribe junto a cada cosa visible su nombre corto: el
destino en amarillo, los objetos en azul, las caras en gris, las zonas
inexploradas en morado. Así la IA ve qué son «Grupo2577#2» y similares y los
señala por su nombre. Las fotos están en `%APPDATA%\DagaWASD\pilota` (las
últimas 40). Una foto bloquea SketchUp durante una imagen de la vista (medio
segundo en un modelo grande): por eso solo estando quieto.

En el puente: `GET /explore/percept?since=N` (descripción y avisos), `GET
/explore/wait?since=N&timeout=60` (la misma descripción, pero el puente
responde solo cuando hay un aviso que despierta: `pilota` no consulta sin
parar) y `POST /explore` con `{"cmd": "steer", …}`.

**Los comentarios en el vídeo.** Lo que dice la IA (`--commento`, `--di`, o
`say` en el steer) queda en el recorrido grabado, en el instante en que lo
dijo: se convierte en la descripción de la escena más cercana al hacer las
escenas, y en un archivo de subtítulos `.srt` junto al vídeo (AVI: el mismo
nombre, los reproductores lo abren solos; imágenes PNG: `crea_video.bat` lo
mete en el MP4).

**Piloto autónomo.** `tools/pilota_ia.rb` conduce solo, sin un comando cada
vez: espera los avisos del puente, envía a Claude la descripción y la foto
de la pausa, y pasa al puente lo que Claude decide. El motor predeterminado
es el propio Claude Code (`claude -p`, con la cuenta de este ordenador: sin
clave); con `ANTHROPIC_API_KEY` definida usa la API de Claude (gema
`anthropic`). En Stromboli un turno dura 4–5 s. Cada turno consume:
`--turni` (20) y `--secondi` (300) ponen el límite, y al final imprime los
tokens usados.

```
ruby tools/esplora.rb avvia --a-piedi                   # inicia, a pie
ruby tools/pilota_ia.rb --turni 15 --secondi 240        # esfuerzo bajo: respuestas en pocos segundos
ruby tools/pilota_ia.rb --sforzo medium --lingua inglese --modello claude-sonnet-5-5
ruby tools/pilota_ia.rb --motore api                     # la API, con la clave
```

## Fotos y galería

Caminando, **P** (se cambia en *Sistema › Controles*; con el mando el
gatillo superior derecho, RB) hace una foto de la vista, sin punto de mira
ni textos, con un flash. Si estás grabando un recorrido la foto va con él;
si no, a una serie aparte, una por cada vez que entras en el modo.

El explorador hace fotos por sí mismo cuando el paseo se convierte en
recorrido: los destinos más interesantes de los vistos hasta ese momento,
cuando su mirada se posa en ellos y los ve lo bastante grandes (muchos
destinos se miran sin llegar a ellos) o al llegar; los espacios que se abren
de vez en cuando; nunca desde donde ya ha hecho una foto, nunca más de una
foto cada 8 segundos (como mucho 30 por paseo). De cada foto escribe **qué**
hay (la cosa, lo grande que es, lo lejos que está, qué hay alrededor) y
**por qué** la eligió: la más interesante hasta entonces, el color que
destaca, nada parecido a la vista, muchos detalles, la silueta que se
recorta contra el fondo, un objeto hecho de muchas partes, una vista
panorámica. La IA que lo guía pide sus fotos con `snap` (su porqué) y `say`
(el qué).

Las fotos se guardan junto al modelo, en `<modelo>_foto/<fecha y hora>/`, en
JPG de 1600 px, con `galleria.json`; el recorrido guarda la carpeta relativa
al modelo, así la encuentra si el modelo se mueve con sus fotos. Para un
modelo nunca guardado, o si no se puede escribir junto al modelo, van a
`%APPDATA%/DagaWASD/foto`.

En *Cámara › Recorridos* cada recorrido tiene su botón **📷**, junto a
Vídeo: con el número de fotos, abre la galería en el navegador; apagado si
el recorrido no tiene ninguna, y un clic explica cómo hacerlas. Debajo de la
lista están las series que ningún recorrido contiene (fotos fuera de una
grabación, recorridos borrados).

La galería es una sola página, `galleria.html` en la carpeta de las fotos,
rehecha en cada apertura en el idioma de SketchUp. Las fotos son
instantáneas sobre una mesa de madera, que se revelan al entrar en la vista,
cada una con su hoja de notas: qué, por qué, quién la hizo, una brújula con
la dirección de la mirada y la hora. Se miran de dos maneras:

- **en fila**: se desplazan de lado con la rueda, las flechas, arrastrando o
  desde la tira de abajo (las miniaturas en película). Arriba está el paseo
  dibujado a lápiz: las fotos numeradas con el cono de lo que miraban, la
  escala, el norte, el sentido. Un mapa pequeño en una esquina sigue la foto
  en curso. Los comentarios de la IA están en pósits en su sitio del paseo,
  y al final está la ficha con duración, camino recorrido y fotos;
- **esparcidas sobre la mesa**: las fotos se cogen y se mueven con el ratón
  (o con el dedo, o con las flechas), y la disposición se conserva para la
  próxima vez. *Ordenarlas* las vuelve a poner en filas.

Un clic abre la foto en grande, con *Presentación* (una tras otra; la barra
espaciadora la detiene). Con fotos de varios autores (tú, el explorador, la
IA) los sellos de arriba las filtran. `#3` en la dirección lleva a la foto
3, `#3z` la abre en grande. Se imprime limpia (las fotos con sus notas),
funciona sin conexión y se puede enviar a alguien junto con su carpeta.

**Editar** cambia los textos ahí mismo, con la misma letra: el título de la
galería y de cada foto, *Qué*, *Por qué*, el sello y las notas de la IA; ✕
quita una foto de la galería (el archivo se queda) y ↺ la devuelve. Los
textos de SketchUp nunca se pierden: cada uno puede volver al original. Los
cambios se guardan al momento en el navegador; *Guardar en la carpeta*
(Edge, Chrome) los escribe en `galleria_modifiche.json` junto a las fotos y
en la propia página, así viajan con la carpeta.

## Dos paquetes

`tools\crea_rbz.bat` crea en `dist\`:

- `dagawasd-<versión>.rbz`: completo, con el **puente para Claude Code**
  (`lib/bridge.rb`), un servidor solo local, apagado hasta que lo enciendes
  desde el panel, a través del cual Claude Code dibuja en el modelo abierto;
- `dagawasd-<versión>-warehouse.rbz`: sin el puente, para el Extension
  Warehouse. Sin `lib/bridge.rb` la extensión funciona igual.

## Desarrollo

El código, sus comentarios y el registro de cambios están en italiano.

- `installa.bat` copia el código fuente en la carpeta Plugins de cada
  SketchUp que encuentra.
- `tests\run_tests.bat` ejecuta las pruebas (Ruby, con un SketchUp simulado;
  el panel en un navegador simulado con Node).
- `tools\controlla_warehouse.bat` comprueba el paquete con las reglas de
  Trimble (rubocop-sketchup).
- El número de versión está solo en `dagawasd.rb` (`VERSION`); cada versión
  tiene su sección en `CHANGELOG.md`.
- Los iconos nacen de los SVG de `pubblicazione/`: `tools\rendi_icone.bat`
  rehace los de la barra (`icons/`) y el de la ficha del Warehouse
  (`pubblicazione/icona_512.png`).
- La ficha del Extension Warehouse (textos en inglés y notas para los
  revisores) está en `pubblicazione/extension_warehouse.md`.
- Este README está en varios idiomas (`README.md` en inglés,
  `README.it.md`, `.es`, `.fr`, `.de`, `.pt`, `.nl`, `.sv`, `.pl`, `.cs`, `.ru`, `.ja`, `.ko`, `.zh`): un cambio va en todos.
- En el SketchUp abierto, con el puente activo y «Ventanas y teclas»
  activado en el panel (herramientas para Claude Code, no instaladas):
  - `tools\finestre.ps1` llega adonde Ruby no llega: ventanas nativas,
    avisos, menús, captura de la vista con cielo y nubes, teclas simuladas y
    clics reales en la vista 3D (por ejemplo el doble clic en una esfera);
  - `tools\collaudo.rb` prueba en directo el botón y el menú del panel, la
    confirmación de «Eliminar» y un vídeo hasta la ventana final;
  - `tools\schermate.rb` hace las imágenes de la ficha en
    `pubblicazione/schermate/` (1920×1080, con una pantalla al menos así);
  - `tools\prova_fps.rb` camina y corre en modo FPS y mide el balanceo de la
    cabeza.

## Contacto

Escribe a [DagaWASD@icloud.com](mailto:DagaWASD@icloud.com). Los errores y las ideas, mejor como
[issue](https://github.com/Dagadam/dagawasd/issues), donde otros pueden verlos y seguirlos;
los problemas de seguridad, por la [política de seguridad](.github/SECURITY.md).

Si DagaWASD te resulta útil, puedes apoyar su desarrollo en [Ko-fi](https://ko-fi.com/dagadam).

## Licencia

[MIT](LICENSE) © 2026 Dagadam. Puedes usar, modificar y redistribuir el
código libremente, también con fines comerciales, siempre que cada copia
conserve el aviso de copyright y el texto de la licencia.
