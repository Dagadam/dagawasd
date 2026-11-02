# DagaWASD

[English](README.md) · [Italiano](README.it.md) · [Español](README.es.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · **Português** · [日本語](README.ja.md) · [中文](README.zh.md)

Extensão para SketchUp (Windows): caminhe pelo seu modelo na primeira pessoa
com WASD e o rato, ou com um comando de jogos.

▶ Vídeo de demonstração: https://youtu.be/w6xE86y7iEw?is=7Gh12tF7atE_N9_K

## O que faz

- **Caminhar**: inércia, correr, agachar, saltar, escadas e rampas, e
  regresso seguro ao chão se cair no vazio.
- **Física dos objetos**: grupos e componentes caem, ressaltam e tombam
  conforme o material; pode chutá-los, agarrá-los e atirá-los.
- **Céu e tempo**: sol, lua e estrelas segundo a data, a hora e o local;
  chuva, neve, nuvens, trovoadas, neve que se acumula no chão.
- **Percursos**: grave a câmara enquanto caminha, reproduza-a, exporte-a
  como cenas ou como vídeo AVI. Afine-a no modelo movendo e rodando as suas
  posições (esferas com uma seta tão longa quanto o zoom, e a moldura do
  enquadramento), ou construa um do zero. No painel, cada percurso abre-se
  na lista das suas posições; um clique numa posição, ou um duplo clique na
  sua esfera (ou Enter), abre as suas definições com uma pré-visualização do
  que ela vê, e um clique entre duas posições acrescenta uma a partir da
  vista atual. Durante a reprodução, a lista acende a posição em curso.
  «Rarear câmaras» junta as esferas amontoadas umas sobre as outras numa só,
  a média delas (posição, olhar, zoom), desde que não olhem a mais de 45°
  umas das outras.
- **Explorador autónomo**: a câmara olha para a cena, escolhe a coisa mais
  significativa, dá um passo na sua direção enquanto olha para ela e
  recomeça; no fim, o passeio é um percurso. Ver abaixo.
- **Fotos e galeria**: P tira uma foto do que vê; o explorador fotografa
  por si as coisas mais interessantes do passeio. Cada percurso abre a sua
  galeria no navegador: fotos instantâneas numa mesa, com notas. Ver abaixo.
- **Comando** XInput, e olhar em redor com o teclado numérico.
- Painel de definições em 36 línguas.

Requisitos: SketchUp 2023 ou posterior, em Windows. Num Mac a extensão
instala-se mas não arranca, e avisa.

## Instalação

- A partir do **Extension Warehouse** do SketchUp (versão assinada), ou
- descarregue o `.rbz` de uma [Release](https://github.com/Dagadam/dagawasd/releases)
  e instale-o em *Extensões › Extension Manager › Instalar extensão*.

As definições ficam em `%APPDATA%\DagaWASD\settings.json`: uma atualização
não as apaga.

## Explorador autónomo

Botão do olho na barra (ou *Extensões › DagaWASD › Explorador autónomo*):
uma pequena janela permite escolher o perfil (o seu carácter, ver abaixo) e
se o passeio é gravado como percurso, e lembra-se das escolhas para a
próxima vez; setas e Enter, ou duplo clique num perfil, para partir logo. O
mesmo botão para-o enquanto explora. O ciclo: **analisa → escolhe o ponto →
um passo em direção ao ponto, a olhar para ele → analisa**.

- **Análise**: uma retina de raios através da grelha do ecrã
  (`view.pickray` + `model.raytest`) dá, para cada célula, distância,
  normal, face, objeto e cor. Daí a saliência: arestas de profundidade,
  vincos, detalhe, contraste de cor (Lab), raridade, componentes e grupos à
  escala humana; paredes e pavimentos grandes contam pouco. Ponderada pela
  distância, pelo centro da vista e pela novidade.
- **Memória**: vóxeis do que o olhar já viu, sítios já pisados (em planta e
  em altura: o piso de cima continua novo), aborrecimento por alvo e por
  categoria (visto um sofá, os outros iguais interessam menos): assim não
  volta sempre às mesmas coisas.
- **Planta do que viu**: a pé, os raios que passam à altura do corpo marcam
  numa planta de células de 50 cm (uma por piso) o chão visto, com a sua
  altura (chão, degraus, tampos dos móveis), e as paredes atingidas. Serve
  para duas coisas:
  - **fronteiras**: a orla entre o que viu e o que nunca viu (para lá de uma
    porta, atrás de uma esquina) torna-se um alvo, uma «zona inexplorada»:
    vai lá e espreita para dentro. Pesa como o espaço aberto, segundo a
    vontade de andar do perfil; no mapa de atenção são os quadradinhos roxos
    no chão;
  - **caminhos planeados**: para cada alvo traça o caminho na planta (A*) até
    um ponto de onde o vê: à volta de paredes e móveis, mantendo alguma
    distância, escadas acima (um degrau de cada vez sim, uma mesa ou um sofá
    não) e por rampas até à inclinação máxima do jogador, a direito onde
    pode. Onde ainda não olhou é otimista e tenta. A cada análise volta a
    verificar o resto do caminho na planta nova e, se agora estiver
    bloqueado, procura outro; a cada 3 s refá-lo de qualquer forma (talvez
    tenha visto um atalho); onde embate, marca e recalcula. Se o alvo
    desaparece atrás de algo, ou o caminho se afasta dele, olha para onde
    vai. O caminho em curso é o tracejado no chão. A procura trabalha por
    fatias, como a análise.
- **Passo**: em direção ao ponto, contornando obstáculos, subindo escadas,
  nunca descendo de uma borda; para a uma distância de onde o objeto se vê
  inteiro e olha para ele. A partir de uma vista aérea voa e aterra onde há
  algo para ver.
- **Contornar os objetos**: ao chegar a um objeto, se o perfil o pedir
  (*Contorna os objetos*, em graus: Fotógrafo 180°, Curioso 90°), contorna-o
  a olhar para ele, pelo lado mais livre, para o ver de vários lados; se o
  caminho se fechar, volta para trás. Depois, a pausa.
- **Salto**: um obstáculo baixo que corta o caminho (um muro baixo, uma
  vedação, um degrau grande) sem um desvio curto é saltado, se do outro lado
  houver uma superfície onde aterrar. Usa a força de salto e a gravidade do
  jogador (com as predefinições os pés sobem 1,08 m; salta o que estiver
  abaixo de 85 % dessa altura); nunca salta para cima de assentos e mesas.
  Desliga-se no perfil (o Lento não salta).
- **Corpo**: altura dos olhos, raio, degrau (no máximo 25 cm), salto e
  gravidade são os do jogador (painel › Jogador), mesmo que sejam alterados
  enquanto explora.
- **Fluido**: tal como a construção ao vivo da ponte, a análise é uma Fiber
  que trabalha por fatias entre uma imagem e a seguinte; a retina alarga-se
  ou estreita-se conforme o custo de um raio naquele modelo. Com *Sistema ›
  Desempenho › Análise adaptativa*, também a frequência das análises
  acompanha o poder de cálculo livre, entre um mínimo e um máximo por
  segundo, sem abrandar a caminhada.
- **Comandos**: Esc ou um clique para o parar, botão direito para pausa,
  «Procurar outra coisa», mapa de atenção, olho a cores; roda do rato para a
  velocidade; I esconde ou mostra as linhas de informação no canto superior
  esquerdo. Outra ferramenta para-o; orbitar com o botão do meio
  suspende-o, e ele recomeça a partir de onde pôs a câmara.
- **Preso?** Se em 10 segundos não se deslocar 75 cm (indeciso entre alvos
  próximos, fechado num canto), procura uma saída entre 12 direções e
  segue-a durante alguns segundos; se a pé não houver saída e o modo for
  automático, levanta voo.
- **No fim**, se deixou «Gravar o percurso» assinalado ao iniciar, o passeio
  torna-se um percurso («Exploração 1», …): no painel pode revê-lo, ou
  transformá-lo em cenas ou num vídeo.

### Perfis

O carácter do explorador é um **perfil**, um conjunto de coeficientes:
*Extensões › DagaWASD › Perfis do explorador…*, ou botão direito enquanto
explora › *Perfil* (troca na hora) e *Editar perfis…*.

| Perfil | Carácter |
|---|---|
| Equilibrado | o de sempre |
| Curioso | aborrece-se depressa, procura detalhes e coisas raras, explora mais, contorna os objetos em 90° |
| Corredor | 3,2 m/s, reflexos rápidos, pausas curtas |
| Lento | 0,5 m/s, pausas longas, um olhar que roda devagar |
| Fotógrafo | antes de se aproximar amplia o alvo (zoom), depois vai até lá e contorna-o em 180° |
| Despreocupado | escolhas caprichosas, muda de ideias com facilidade, adora espaço aberto |
| Soldado | reconhecimento, sempre a pé: 3,6 m/s, olha de longe e por pouco tempo, vai primeiro onde ainda não olhou |

Na janela, cada coeficiente tem um cursor (enquanto o arrasta, o
explorador, se usar esse perfil, muda ao vivo) e um ↺ que repõe o valor
original. Grupos: movimento (velocidade, distância de paragem, degrau, a
pé/a voar), olhar (rotação, reflexos, **continuidade** — o quanto prefere
passar ao que está ao lado do que está a ver, sem voltar ao que já deixou
para trás), atenção (pausa, contornar os objetos, duração,
**determinação** — durante quantos segundos não muda de ideias sobre um
alvo acabado de escolher — e **fidelidade**), curiosidade (memória,
aborrecimento, vontade de andar, capricho), o que o atrai (pesos de
objetos, silhuetas, detalhe, cor, raridade) e zoom. «Novo» copia o perfil
em uso; os perfis predefinidos podem ser alterados e depois repostos.

Em `settings.json`: `"explore_profile"` (o que está em uso),
`"explore_profiles"` (os seus, e as alterações aos predefinidos) e
`"explore_record"` (a caixa do percurso na janela de início). Os valores
somam-se por camadas: predefinições (`EX_DEFAULTS`, `lib/explore.rb`) ←
`"explore": { … }` ← perfil ← opções de quem o inicia (a ponte).

Com a ponte ligada, o Claude Code comanda-o e observa-o (os comandos das
ferramentas de desenvolvimento estão em italiano):

```
ruby tools/esplora.rb avvia --secondi 120 --velocita 1.3   # inicia: 120 s, 1,3 m/s
ruby tools/esplora.rb avvia --profilo Fotografo    # um perfil só para este passeio
ruby tools/esplora.rb profili                      # lista; «profilo NOME» põe-no em uso
ruby tools/esplora.rb segui --foto esplorazione    # uma linha e uma foto por cada escolha
ruby tools/esplora.rb ferma                        # para e guarda o percurso
```

### A IA ao volante

Com `pilota` e `guida` é o Claude Code que decide para onde ir, enquanto o
explorador continua a andar e a olhar por si (`lib/expilot.rb`). Cada coisa
vista tem um nome curto e estável (`o12` um objeto, `s7` uma face, `F3` uma
zona inexplorada); a IA põe destinos numa agenda, e o explorador alcança-os
um após outro com os seus próprios passos, os seus desvios à volta das
paredes e o seu olhar. Com a agenda vazia volta a escolher sozinho: nunca
para à espera da IA.

```
ruby tools/esplora.rb pilota                       # espera um aviso e descreve o que vê
ruby tools/esplora.rb guida --vai o12 --giro 90 --commento "O altar-mor" --vai F3
ruby tools/esplora.rb guida --guarda o7 --per 3    # vira-se para olhar, sem se mexer
ruby tools/esplora.rb guida --piace label:colonna=2 --evita o4
ruby tools/esplora.rb guida --sostituisci --punto 12,4,1.7   # nova agenda: um ponto em metros
ruby tools/esplora.rb guida --svuota               # sem agenda: volta a escolher sozinho
ruby tools/esplora.rb guida --foto                 # uma foto na pausa atual (ou na seguinte)
ruby tools/esplora.rb guida --foto-sempre          # uma foto em cada pausa (--foto-mete: só nos destinos da IA, --senza-foto)
```

Os avisos que acordam o `pilota`: destino alcançado, destino cumprido (ou
abandonado, e porquê), agenda quase vazia ou vazia, um destino que não se
alcança, uma coisa notável nunca vista, uma foto.

**A pé: aonde se chega.** A caminhar, a descrição diz para cada coisa e zona
inexplorada se se lá chega (`reach`: sim, talvez passando por zonas nunca
vistas, não) e com quantos metros de caminho (`walk_m`), a partir da planta
que o explorador fez ao olhar. Um «vai» para algo onde não se chega a pé é
recusado logo, com o motivo; nas fotos essas coisas têm a etiqueta cinzenta
clara. No Stromboli o piloto autónomo passou de cerca de um destino
alcançado por minuto para três.

**Fotos com etiquetas.** Nas pausas diante dos destinos da IA, o
explorador, parado e com o olhar no destino, tira uma imagem da vista
(800 px) e escreve ao lado de cada coisa visível o seu nome curto: o
destino a amarelo, os objetos a azul, as faces a cinzento, as zonas
inexploradas a roxo. Assim a IA vê o que são «Grupo2577#2» e afins e
indica-os pelo nome. As fotos ficam em `%APPDATA%\DagaWASD\pilota` (as
últimas 40). Uma foto bloqueia o SketchUp durante uma imagem da vista (meio
segundo num modelo grande): por isso só quando está parado.

Na ponte: `GET /explore/percept?since=N` (descrição e avisos), `GET
/explore/wait?since=N&timeout=60` (a mesma descrição, mas a ponte só
responde quando há um aviso que acorda: o `pilota` não pergunta sem parar)
e `POST /explore` com `{"cmd": "steer", …}`.

**Os comentários no vídeo.** O que a IA diz (`--commento`, `--di`, ou `say`
no steer) fica no percurso gravado, no instante em que o disse: torna-se a
descrição da cena mais próxima quando se fazem as cenas, e um ficheiro de
legendas `.srt` ao lado do vídeo (AVI: o mesmo nome, os leitores abrem-no
sozinhos; imagens PNG: o `crea_video.bat` põe-no no MP4).

**Piloto autónomo.** `tools/pilota_ia.rb` conduz sozinho, sem um comando de
cada vez: espera os avisos da ponte, envia ao Claude a descrição e a foto da
pausa, e passa à ponte o que o Claude decide. O motor predefinido é o
próprio Claude Code (`claude -p`, com a conta deste computador: sem chave);
com `ANTHROPIC_API_KEY` definida usa a API do Claude (gem `anthropic`). No
Stromboli um turno dura 4–5 s. Cada turno tem custo: `--turni` (20) e
`--secondi` (300) põem o limite, e no fim mostra os tokens usados.

```
ruby tools/esplora.rb avvia --a-piedi                   # inicia, a pé
ruby tools/pilota_ia.rb --turni 15 --secondi 240        # esforço baixo: respostas em poucos segundos
ruby tools/pilota_ia.rb --sforzo medium --lingua inglese --modello claude-sonnet-5-5
ruby tools/pilota_ia.rb --motore api                     # a API, com a chave
```

## Fotos e galeria

A caminhar, **P** (altera-se em *Sistema › Comandos*; no comando o botão de
ombro direito, RB) tira uma foto da vista, sem mira nem textos, com um
flash. Se estiver a gravar um percurso a foto vai com ele; se não, para uma
série à parte, uma por cada vez que entra no modo.

O explorador fotografa por si, quando o passeio se torna percurso: os
destinos mais interessantes entre os vistos até ali, quando o olhar pousa
neles e os vê suficientemente grandes (muitos destinos são vistos sem lá
chegar) ou à chegada; os espaços que se abrem de vez em quando; nunca de
onde já fotografou, nunca mais de uma foto a cada 8 segundos (no máximo 30
por passeio). De cada foto escreve **o que** lá está (a coisa, o tamanho, a
distância, o que há à volta) e **porque** a escolheu: a mais interessante
até ali, a cor que sobressai, nada parecido à vista, muitos detalhes, a
silhueta que se destaca do fundo, um objeto feito de muitas partes, uma
paisagem. A IA que o guia pede as suas fotos com `snap` (o seu porquê) e
`say` (o quê).

As fotos ficam ao lado do modelo, em `<modelo>_foto/<data e hora>/`, em JPG
de 1600 px, com `galleria.json`; o percurso guarda a pasta relativa ao
modelo, por isso encontra-a se o modelo for movido com as suas fotos. Para
um modelo nunca guardado, ou se não for possível escrever ao lado do modelo,
vão para `%APPDATA%/DagaWASD/foto`.

Em *Câmara › Percursos*, cada percurso tem o seu botão **📷**, ao lado de
Vídeo: com o número de fotos, abre a galeria no navegador; apagado se o
percurso não tiver nenhuma, e um clique explica como tirar algumas. Por
baixo da lista estão as séries que nenhum percurso contém (fotos fora de
uma gravação, percursos apagados).

A galeria é uma única página, `galleria.html` na pasta das fotos, refeita
a cada abertura na língua do SketchUp. As fotos são instantâneas numa mesa
de madeira, que se revelam ao entrar na vista, cada uma com a sua folha de
notas: o quê, porquê, quem a tirou, uma bússola com a direção do olhar e a
hora. Veem-se de duas maneiras:

- **em fila**: deslizam para o lado com a roda do rato, as setas,
  arrastando, ou a partir da película em baixo (as miniaturas). No topo está
  o passeio desenhado a lápis: as fotos numeradas com o cone do que estavam
  a ver, a escala, o norte, o sentido. Um mapa pequeno num canto acompanha a
  foto em curso. Os comentários da IA estão em post-its no seu lugar no
  passeio, e no fim há a ficha com duração, caminho feito e fotos;
- **espalhadas na mesa**: as fotos pegam-se e movem-se com o rato (ou com o
  dedo, ou com as setas), e a disposição mantém-se para a próxima vez.
  *Arrumá-las* volta a pô-las em filas.

Um clique abre a foto em grande, com *Apresentação* (uma após outra; a
barra de espaço para-a). Com fotos de vários autores (o utilizador, o
explorador, a IA), os carimbos no topo filtram-nas. `#3` no endereço leva à
foto 3, `#3z` abre-a em grande. Imprime-se limpa (as fotos com as suas
notas), funciona sem rede e pode ser enviada a alguém juntamente com a sua
pasta.

## Dois pacotes

`tools\crea_rbz.bat` cria em `dist\`:

- `dagawasd-<versão>.rbz`: completo, com a **ponte para o Claude Code**
  (`lib/bridge.rb`), um servidor apenas local, desligado até o ligar no
  painel, através do qual o Claude Code desenha no modelo aberto;
- `dagawasd-<versão>-warehouse.rbz`: sem a ponte, para o Extension
  Warehouse. Sem `lib/bridge.rb` a extensão funciona na mesma.

## Desenvolvimento

O código, os seus comentários e o registo de alterações estão em italiano.

- `installa.bat` copia o código-fonte para a pasta Plugins de cada SketchUp
  encontrado.
- `tests\run_tests.bat` corre os testes (Ruby, com um SketchUp simulado; o
  painel num navegador simulado com Node).
- `tools\controlla_warehouse.bat` verifica o pacote com as regras da
  Trimble (rubocop-sketchup).
- O número da versão está apenas em `dagawasd.rb` (`VERSION`); cada versão
  tem a sua secção em `CHANGELOG.md`.
- Os ícones nascem dos SVG em `pubblicazione/`: `tools\rendi_icone.bat`
  refaz os da barra (`icons/`) e o da ficha do Warehouse
  (`pubblicazione/icona_512.png`).
- A ficha do Extension Warehouse (textos em inglês e notas para os
  revisores) está em `pubblicazione/extension_warehouse.md`.
- Este README existe em várias línguas (`README.md` em inglês,
  `README.it.md`, `.es`, `.fr`, `.de`, `.pt`, `.ja`, `.zh`): uma alteração
  vai para todas.
- No SketchUp aberto, com a ponte ligada e «Janelas e teclas» ligado no
  painel (ferramentas para o Claude Code, não instaladas):
  - `tools\finestre.ps1` chega onde o Ruby não chega: janelas nativas,
    avisos, menus, captura da vista com céu e nuvens, teclas simuladas e
    cliques reais na vista 3D (por exemplo o duplo clique numa esfera);
  - `tools\collaudo.rb` testa ao vivo o botão e o menu do painel, a
    confirmação de «Eliminar» e um vídeo até à janela final;
  - `tools\schermate.rb` faz as imagens da ficha em
    `pubblicazione/schermate/` (1920×1080, com um ecrã pelo menos desse
    tamanho);
  - `tools\prova_fps.rb` anda e corre em modo FPS e mede o balanço da
    cabeça.

## Licença

[MIT](LICENSE) © 2026 Dagadam. Pode usar, modificar e redistribuir o código
livremente, também para fins comerciais, desde que cada cópia mantenha o
aviso de direitos de autor e o texto da licença.
