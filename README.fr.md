# DagaWASD

[English](README.md) · [Italiano](README.it.md) · [Español](README.es.md) · **Français** · [Deutsch](README.de.md) · [Português](README.pt.md) · [日本語](README.ja.md) · [中文](README.zh.md)

Extension pour SketchUp (Windows) : parcourez votre modèle à la première
personne avec WASD et la souris, ou avec une manette.

▶ Vidéo de démonstration : https://youtu.be/w6xE86y7iEw?is=7Gh12tF7atE_N9_K

## Ce qu'elle fait

- **Marche** : inertie, course, accroupissement, saut, escaliers et pentes,
  retour au sol en toute sécurité si vous tombez dans le vide.
- **Physique des objets** : groupes et composants tombent, rebondissent et
  basculent selon leur matériau ; on peut les frapper du pied, les saisir et
  les lancer.
- **Ciel et météo** : soleil, lune et étoiles selon la date, l'heure et le
  lieu ; pluie, neige, nuages, orages, neige qui tient au sol.
- **Parcours** : enregistrez la caméra pendant que vous marchez, rejouez-la,
  exportez-la en scènes ou en vidéo AVI. Retouchez-la dans le modèle en
  déplaçant et en tournant ses positions (des sphères avec une flèche aussi
  longue que le zoom, et le cadre de la prise de vue), ou construisez-en un
  à partir de zéro. Dans le panneau, chaque parcours s'ouvre sur la liste de
  ses positions ; un clic sur une position, ou un double-clic sur sa sphère
  (ou Entrée), ouvre ses réglages avec un aperçu de ce qu'elle voit, et un
  clic entre deux positions en ajoute une depuis la vue actuelle. Pendant la
  lecture, la liste allume la position en cours. « Éclaircir les caméras »
  fusionne les sphères entassées les unes sur les autres en une seule, leur
  moyenne (position, regard, zoom), si elles ne regardent pas à plus de 45°
  l'une de l'autre.
- **Explorateur autonome** : la caméra regarde la scène, choisit la chose la
  plus significative, fait un pas vers elle en la regardant et recommence ;
  à la fin, la promenade devient un parcours. Voir plus bas.
- **Photos et galerie** : P prend une photo de ce que vous voyez ;
  l'explorateur photographie de lui-même les choses les plus intéressantes
  de sa promenade. Chaque parcours ouvre sa galerie dans le navigateur : des
  photos instantanées sur une table, avec des notes. Voir plus bas.
- **Manette** XInput, et regard au pavé numérique.
- Panneau de réglages en 36 langues.

Configuration requise : SketchUp 2023 ou ultérieur, sous Windows. Sur Mac,
l'extension s'installe mais ne démarre pas, et le dit.

## Installation

- Depuis l'**Extension Warehouse** de SketchUp (version signée), ou
- téléchargez le `.rbz` d'une [Release](https://github.com/Dagadam/dagawasd/releases)
  et installez-le depuis *Extensions › Gestionnaire d'extensions › Installer
  l'extension*.

Les réglages sont enregistrés dans `%APPDATA%\DagaWASD\settings.json` : une
mise à jour ne les efface pas.

## Explorateur autonome

Bouton en forme d'œil dans la barre (ou *Extensions › DagaWASD ›
Explorateur autonome*) : une petite fenêtre permet de choisir le profil (son
caractère, voir plus bas) et d'enregistrer ou non la promenade comme
parcours, et se souvient de vos choix pour la fois suivante ; flèches et
Entrée, ou double-clic sur un profil, pour partir tout de suite. Le même
bouton l'arrête pendant qu'il explore. Le cycle : **analyse → choisit le
point → un pas vers le point en le regardant → analyse**.

- **Analyse** : une rétine de rayons à travers la grille de l'écran
  (`view.pickray` + `model.raytest`) donne, pour chaque cellule, distance,
  normale, face, objet et couleur. De là, la saillance : bords de
  profondeur, arêtes, détail, contraste de couleur (Lab), rareté, composants
  et groupes à taille humaine ; les grands murs et sols comptent peu.
  Pondérée par la distance, le centre de la vue et la nouveauté.
- **Mémoire** : voxels de ce que le regard a déjà vu, lieux déjà foulés (en
  plan et en hauteur : l'étage du dessus reste nouveau), lassitude par cible
  et par catégorie (un canapé vu, les autres identiques intriguent moins) :
  ainsi il ne revient pas toujours aux mêmes choses.
- **Plan de ce qu'il a vu** : à pied, les rayons qui passent à hauteur du
  corps marquent sur un plan à cellules de 50 cm (un par étage) le sol vu
  avec sa hauteur (sol, marches, plateaux des meubles) et les murs touchés.
  Il sert à deux choses :
  - **frontières** : le bord entre ce qu'il a vu et ce qu'il n'a jamais vu
    (au-delà d'une porte, derrière un angle) devient une cible, une « zone
    inexplorée » : il y va et regarde dedans. Elle pèse comme l'espace
    ouvert, selon l'envie de bouger du profil ; dans la carte de l'attention
    ce sont les petits carrés violets au sol ;
  - **itinéraires planifiés** : pour chaque cible il trace le chemin sur le
    plan (A*) jusqu'à un point d'où on la voit : autour des murs et des
    meubles en s'en tenant un peu à l'écart, en montant les escaliers (une
    marche à la fois oui, une table ou un canapé non) et les pentes jusqu'à
    la pente maximale du joueur, tout droit là où il le peut. Là où il n'a
    pas encore regardé, il est optimiste et essaie. À chaque analyse il
    revérifie le reste de l'itinéraire sur le nouveau plan et, s'il est
    désormais barré, en cherche un autre ; toutes les 3 s il le refait de
    toute façon (il a peut-être vu un raccourci) ; là où il se cogne, il le
    note et recalcule. Si la cible disparaît derrière quelque chose, ou si
    l'itinéraire s'en éloigne, il regarde où il va. L'itinéraire en cours
    est le pointillé au sol. La recherche travaille par tranches, comme
    l'analyse.
- **Pas** : vers le point, en contournant les obstacles, en montant les
  escaliers, jamais au bas d'un rebord ; il s'arrête à une distance d'où
  l'objet se voit en entier, et le regarde. Depuis une vue aérienne il vole
  et atterrit là où il y a quelque chose.
- **Tour des objets** : arrivé à un objet, si le profil le demande (*Fait le
  tour des objets*, en degrés : Photographe 180°, Curieux 90°), il en fait le
  tour en le regardant, du côté le plus dégagé, pour le voir sous plusieurs
  angles ; si le chemin se ferme, il revient en arrière. Puis la pause.
- **Saut** : un obstacle bas qui barre le chemin (un muret, une clôture, une
  grande marche), sans détour court possible, est sauté s'il y a au-delà une
  surface où atterrir. Il utilise la force de saut et la gravité du joueur
  (avec les valeurs par défaut les pieds montent de 1,08 m ; il saute ce qui
  est sous 85 % de cette hauteur) ; il ne saute jamais sur les sièges ni les
  tables. Se désactive dans le profil (Lent ne saute pas).
- **Corps** : hauteur des yeux, rayon, marche (25 cm au plus), saut et
  gravité sont ceux du joueur (panneau › Joueur), même modifiés pendant
  qu'il explore.
- **Fluide** : comme la construction en direct du pont, l'analyse est une
  Fiber qui travaille par tranches d'une image à l'autre ; la rétine
  s'élargit ou se resserre selon ce que coûte un rayon dans ce modèle. Avec
  *Système › Performances › Analyse adaptative*, la fréquence des analyses
  suit elle aussi la puissance de calcul libre, entre un minimum et un
  maximum par seconde, sans ralentir la marche.
- **Commandes** : Échap ou un clic pour l'arrêter, clic droit pour la pause,
  « Chercher autre chose », carte de l'attention, œil couleur ; molette pour
  la vitesse ; I masque ou affiche les lignes d'information en haut à
  gauche. Un autre outil l'arrête ; l'orbite au bouton du milieu le suspend,
  et il repart de là où vous avez mis la caméra.
- **Bloqué ?** S'il ne se déplace pas de 75 cm en 10 secondes (indécis entre
  des cibles proches, coincé dans un angle), il cherche une issue parmi 12
  directions et la suit quelques secondes ; s'il n'y a pas de passage à pied
  et que le mode est automatique, il s'envole.
- **À la fin**, si vous avez laissé « Enregistrer le parcours » coché au
  départ, la promenade devient un parcours (« Exploration 1 », …) : depuis
  le panneau vous la revoyez, ou en faites des scènes ou une vidéo.

### Profils

Le caractère de l'explorateur est un **profil**, un ensemble de
coefficients : *Extensions › DagaWASD › Profils de l'explorateur…*, ou clic
droit pendant qu'il explore › *Profil* (changement à la volée) et *Modifier
les profils…*.

| Profil | Caractère |
|---|---|
| Équilibré | celui de toujours |
| Curieux | se lasse vite, cherche les détails et les choses rares, explore davantage, fait 90° autour des objets |
| Coureur | 3,2 m/s, réflexes vifs, pauses courtes |
| Lent | 0,5 m/s, pauses longues, un regard qui tourne lentement |
| Photographe | avant de s'approcher il zoome sur la cible, puis y va et en fait le tour sur 180° |
| Insouciant | choix capricieux, change facilement d'avis, aime l'espace ouvert |
| Soldat | reconnaissance, toujours à pied : 3,6 m/s, regarde de loin et brièvement, va d'abord là où il n'a pas encore regardé |

Dans la fenêtre, chaque coefficient a un curseur (pendant que vous le
faites glisser, l'explorateur, s'il utilise ce profil, change en direct) et
un ↺ qui le ramène à sa valeur d'origine. Groupes : mouvement (vitesse,
distance d'arrêt, marche, à pied/en vol), regard (rotation, réflexes,
**continuité** — à quel point il préfère passer à ce qui est à côté de ce
qu'il regarde, sans revenir à ce dont il s'est déjà détourné), attention
(pause, tour des objets, durée, **détermination** — pendant combien de
secondes il ne change pas d'avis sur une cible qu'il vient de choisir — et
**fidélité**), curiosité (mémoire, lassitude, envie de bouger, caprice), ce
qui l'attire (poids des objets, silhouettes, détail, couleur, rareté) et
zoom. « Nouveau » copie le profil en usage ; les profils prêts à l'emploi
peuvent être modifiés puis restaurés.

Dans `settings.json` : `"explore_profile"` (celui en usage),
`"explore_profiles"` (les vôtres, et les modifications des profils prêts à
l'emploi) et `"explore_record"` (la case du parcours de la fenêtre de
départ). Les valeurs s'additionnent par couches : valeurs par défaut
(`EX_DEFAULTS`, `lib/explore.rb`) ← `"explore": { … }` ← profil ← options
de qui le lance (le pont).

Avec le pont activé, Claude Code le commande et l'observe (les commandes des
outils de développement sont en italien) :

```
ruby tools/esplora.rb avvia --secondi 120 --velocita 1.3   # lance : 120 s, 1,3 m/s
ruby tools/esplora.rb avvia --profilo Fotografo    # un profil rien que pour cette promenade
ruby tools/esplora.rb profili                      # liste ; « profilo NOM » le met en usage
ruby tools/esplora.rb segui --foto esplorazione    # une ligne et une photo par choix
ruby tools/esplora.rb ferma                        # l'arrête et enregistre le parcours
```

### L'IA aux commandes

Avec `pilota` et `guida`, c'est Claude Code qui décide où aller, tandis que
l'explorateur continue de marcher et de regarder de lui-même
(`lib/expilot.rb`). Chaque chose vue a un nom court et stable (`o12` un
objet, `s7` une face, `F3` une zone inexplorée) ; l'IA inscrit des
destinations à un agenda, et l'explorateur les atteint l'une après l'autre
avec ses propres pas, ses détours autour des murs et son regard. Agenda
vide, il recommence à choisir seul : il ne s'arrête jamais pour attendre
l'IA.

```
ruby tools/esplora.rb pilota                       # attend un événement et décrit ce qu'il voit
ruby tools/esplora.rb guida --vai o12 --giro 90 --commento "Le maître-autel" --vai F3
ruby tools/esplora.rb guida --guarda o7 --per 3    # se tourne pour regarder, sans bouger
ruby tools/esplora.rb guida --piace label:colonna=2 --evita o4
ruby tools/esplora.rb guida --sostituisci --punto 12,4,1.7   # nouvel agenda : un point en mètres
ruby tools/esplora.rb guida --svuota               # pas d'agenda : il recommence à choisir seul
ruby tools/esplora.rb guida --foto                 # une photo à la pause actuelle (ou la suivante)
ruby tools/esplora.rb guida --foto-sempre          # une photo à chaque pause (--foto-mete : seulement aux destinations de l'IA, --senza-foto)
```

Les événements qui réveillent `pilota` : destination atteinte, destination
faite (ou abandonnée, et pourquoi), agenda presque vide ou vide, une
destination inaccessible, une chose remarquable jamais vue, une photo.

**À pied : où l'on peut aller.** En marchant, la description indique pour
chaque chose et zone inexplorée si on peut l'atteindre (`reach` : oui,
peut-être en passant par des zones jamais vues, non) et avec combien de
mètres de chemin (`walk_m`), d'après le plan que l'explorateur s'est fait
en regardant. Un « va » vers une chose inaccessible à pied est refusé
aussitôt, avec la raison ; sur les photos ces choses ont l'étiquette gris
clair. Sur Stromboli, le pilote autonome est passé d'environ une
destination atteinte par minute à trois.

**Photos annotées.** Aux pauses devant les destinations de l'IA,
l'explorateur, immobile et le regard sur la destination, prend une image de
la vue (800 px) et écrit à côté de chaque chose visible son nom court : la
destination en jaune, les objets en bleu, les faces en gris, les zones
inexplorées en violet. Ainsi l'IA voit ce que sont « Groupe2577#2 » et
autres, et les désigne par leur nom. Les photos sont dans
`%APPDATA%\DagaWASD\pilota` (les 40 dernières). Une photo bloque SketchUp le
temps d'une image de la vue (une demi-seconde sur un grand modèle) : c'est
pourquoi seulement à l'arrêt.

Sur le pont : `GET /explore/percept?since=N` (description et événements),
`GET /explore/wait?since=N&timeout=60` (la même description, mais le pont
ne répond que lorsqu'un événement réveille : `pilota` n'interroge pas sans
arrêt) et `POST /explore` avec `{"cmd": "steer", …}`.

**Les commentaires dans la vidéo.** Ce que dit l'IA (`--commento`, `--di`,
ou `say` dans le steer) reste dans le parcours enregistré, à l'instant où
elle l'a dit : cela devient la description de la scène la plus proche quand
on crée les scènes, et un fichier de sous-titres `.srt` à côté de la vidéo
(AVI : même nom, les lecteurs l'ouvrent tout seuls ; images PNG :
`crea_video.bat` le met dans le MP4).

**Pilote autonome.** `tools/pilota_ia.rb` conduit seul, sans une commande à
la fois : il attend les événements du pont, envoie à Claude la description
et la photo de la pause, et transmet au pont ce que Claude décide. Le moteur
par défaut est Claude Code lui-même (`claude -p`, avec le compte de cet
ordinateur : aucune clé) ; avec `ANTHROPIC_API_KEY` définie, il utilise
l'API de Claude (gem `anthropic`). Sur Stromboli un tour dure 4–5 s. Chaque
tour consomme : `--turni` (20) et `--secondi` (300) fixent la limite, et à
la fin il affiche les jetons utilisés.

```
ruby tools/esplora.rb avvia --a-piedi                   # lance, à pied
ruby tools/pilota_ia.rb --turni 15 --secondi 240        # effort faible : réponses en quelques secondes
ruby tools/pilota_ia.rb --sforzo medium --lingua inglese --modello claude-sonnet-5-5
ruby tools/pilota_ia.rb --motore api                     # l'API, avec la clé
```

## Photos et galerie

En marchant, **P** (modifiable dans *Système › Commandes* ; à la manette la
gâchette haute droite, RB) prend une photo de la vue, sans réticule ni
texte, avec un flash. Si vous enregistrez un parcours, la photo va avec lui ;
sinon dans une série à part, une pour chaque fois que vous entrez dans le
mode.

L'explorateur prend des photos de lui-même quand la promenade devient un
parcours : les destinations les plus intéressantes parmi celles vues
jusque-là, quand son regard s'y pose et les voit assez grandes (beaucoup de
destinations sont regardées sans y arriver) ou à l'arrivée ; les espaces
qui s'ouvrent de temps en temps ; jamais depuis un endroit où il a déjà pris
une photo, jamais plus d'une photo toutes les 8 secondes (30 au plus par
promenade). Pour chaque photo il écrit **ce qu'il** y a (la chose, sa
taille, sa distance, ce qui l'entoure) et **pourquoi** il l'a choisie : la
plus intéressante jusque-là, la couleur qui ressort, rien de semblable en
vue, beaucoup de détails, la silhouette qui se détache du fond, un objet
fait de nombreuses parties, un panorama. L'IA qui le guide demande ses
propres photos avec `snap` (son pourquoi) et `say` (le quoi).

Les photos sont enregistrées à côté du modèle, dans `<modèle>_foto/<date et
heure>/`, en JPG de 1600 px, avec `galleria.json` ; le parcours garde le
dossier relatif au modèle, il le retrouve donc si le modèle est déplacé avec
ses photos. Pour un modèle jamais enregistré, ou si l'on ne peut pas écrire
à côté du modèle, elles vont dans `%APPDATA%/DagaWASD/foto`.

Dans *Caméra › Parcours*, chaque parcours a son bouton **📷**, à côté de
Vidéo : avec le nombre de photos, il ouvre la galerie dans le navigateur ;
grisé si le parcours n'en a pas, et un clic explique comment en prendre.
Sous la liste se trouvent les séries qu'aucun parcours ne contient (photos
hors enregistrement, parcours supprimés).

La galerie est une seule page, `galleria.html` dans le dossier des photos,
refaite à chaque ouverture dans la langue de SketchUp. Les photos sont des
instantanés sur une table en bois, qui se développent en entrant dans la
vue, chacun avec sa fiche de notes : quoi, pourquoi, qui l'a prise, une
boussole avec la direction du regard, et l'heure. On les regarde de deux
façons :

- **en file** : elles défilent de côté avec la molette, les flèches, en
  faisant glisser, ou depuis la pellicule en bas (les miniatures). En haut,
  la promenade dessinée au crayon : les photos numérotées avec le cône de ce
  qu'elles regardaient, l'échelle, le nord, le sens. Une petite carte dans
  un coin suit la photo en cours. Les commentaires de l'IA sont sur des
  post-it à leur place dans la promenade, et à la fin il y a la fiche avec
  durée, chemin parcouru et photos ;
- **éparpillées sur la table** : on prend les photos et on les déplace à la
  souris (ou du doigt, ou avec les flèches), et la disposition est conservée
  pour la fois suivante. *Les remettre en ordre* les remet en rangées.

Un clic ouvre la photo en grand, avec *Diaporama* (l'une après l'autre ;
la barre d'espace l'arrête). Avec des photos de plusieurs auteurs (vous,
l'explorateur, l'IA), les tampons en haut les filtrent. `#3` dans l'adresse
mène à la photo 3, `#3z` l'ouvre en grand. Elle s'imprime proprement (les
photos avec leurs notes), fonctionne hors ligne et peut être envoyée à
quelqu'un avec son dossier.

## Deux paquets

`tools\crea_rbz.bat` crée dans `dist\` :

- `dagawasd-<version>.rbz` : complet, avec le **pont pour Claude Code**
  (`lib/bridge.rb`), un serveur uniquement local, éteint tant que vous ne
  l'allumez pas depuis le panneau, à travers lequel Claude Code dessine dans
  le modèle ouvert ;
- `dagawasd-<version>-warehouse.rbz` : sans le pont, pour l'Extension
  Warehouse. Sans `lib/bridge.rb`, l'extension fonctionne tout de même.

## Développement

Le code, ses commentaires et le journal des modifications sont en italien.

- `installa.bat` copie les sources dans le dossier Plugins de chaque
  SketchUp trouvé.
- `tests\run_tests.bat` lance les tests (Ruby, avec un SketchUp simulé ; le
  panneau dans un navigateur simulé avec Node).
- `tools\controlla_warehouse.bat` vérifie le paquet selon les règles de
  Trimble (rubocop-sketchup).
- Le numéro de version se trouve uniquement dans `dagawasd.rb` (`VERSION`) ;
  chaque version a sa section dans `CHANGELOG.md`.
- Les icônes naissent des SVG de `pubblicazione/` : `tools\rendi_icone.bat`
  refait celles de la barre (`icons/`) et celle de la fiche du Warehouse
  (`pubblicazione/icona_512.png`).
- La fiche de l'Extension Warehouse (textes en anglais et notes pour les
  examinateurs) se trouve dans `pubblicazione/extension_warehouse.md`.
- Ce README existe en plusieurs langues (`README.md` en anglais,
  `README.it.md`, `.es`, `.fr`, `.de`, `.pt`, `.ja`, `.zh`) : une modification va dans
  toutes.
- Dans SketchUp ouvert, avec le pont activé et « Fenêtres et touches »
  activé dans le panneau (outils pour Claude Code, non installés) :
  - `tools\finestre.ps1` va là où Ruby ne va pas : fenêtres natives,
    alertes, menus, capture de la vue avec ciel et nuages, touches simulées
    et vrais clics dans la vue 3D (par exemple le double-clic sur une
    sphère) ;
  - `tools\collaudo.rb` teste en direct le bouton et le menu du panneau, la
    confirmation de « Supprimer » et une vidéo jusqu'à la fenêtre finale ;
  - `tools\schermate.rb` fait les images de la fiche dans
    `pubblicazione/schermate/` (1920×1080, avec un écran au moins aussi
    grand) ;
  - `tools\prova_fps.rb` marche et court en mode FPS et mesure le balancement
    de la tête.

## Licence

[MIT](LICENSE) © 2026 Dagadam. Vous pouvez utiliser, modifier et
redistribuer le code librement, y compris à des fins commerciales, à
condition que chaque copie conserve la mention de copyright et le texte de
la licence.
