# Da fare

Cose notate e non ancora fatte. Chi ne fa una la toglie da qui (e la scrive
nel CHANGELOG, se conta per chi usa DagaWASD).

## Esploratore (lib/explore.rb)

- **Ondeggiamento e head bob.** Il `bob` dei profili ha ampiezza e frequenza
  fisse (1,2 cm, `explore_camera`) e ignora il head bob del giocatore
  (`head_bob_enabled`, frequenza, ampiezza, laterale). Chi lo spegne per
  comfort (la scheda Accessibilità lo indica) vede comunque ondeggiare
  l'esploratore: `bob` è acceso in tutti i profili. Proposta: ondeggia solo
  se è acceso anche il head bob del giocatore, con la sua ampiezza come scala.
- **Valori fissi che ignorano il profilo** (`explore_aim`): frontiere a 1 m
  con sosta 0,6 s, spazio aperto a 0,6 m senza sosta, facce sciolte con
  sosta al più 0,7 s (il Lento passa da 5 s a 0,7, il Fotografo da 2,5).
  Ricavarli da `standoff` e `dwell`, magari in una sola funzione di valori
  derivati dal profilo, ricalcolata in `explore_reprofile`.
- **Guardarsi intorno**: 100° in 1,6 s fissi (`EX_LOOK_TURN`,
  `EX_LOOK_TIME`). Con `turn_speed` basso non ci arriva (Lento, 45°/s: circa
  72°; al minimo del cursore, 20°/s: 32°). Durata da `turn_speed`.
- **Soglie in tempo e non in spazio**: la via di fuga dura 5 s ma verifica
  4 m liberi (il Soldato ne fa 18); il controllo «non avanza» (0,12 m in
  1,6 s) scatta a vuoto sotto 0,21 m/s circa vicino alla sosta.
- **Peso degli oggetti contato due volte** (`w_object` nella media
  normalizzata e come fattore assoluto di `obj_f`): a 0 gli oggetti valgono
  ancora il 40%, ed è l'unico peso che sposta la soglia minima di interesse.
- **Pazienza per lo spazio aperto** `max(attention × 0,5, 8 s)`: con
  attenzione sotto gli 8 s supera quella per gli oggetti.
- **Stime dell'IA** (`pilot_reach_of` in lib/expilot.rb): distanza di sosta
  `0,8 × size` contro `0,55 × size / tan(fov/2)` di `explore_aim`; frontiere
  1,5 m contro 1,0.
- **Profilo sempre a piedi bloccato senza via di fuga**: scrive «bloccato»
  ogni 10 s per sempre (non può alzarsi in volo).
- **Vista aerea che guarda nel vuoto**: guardandosi intorno non vede niente
  e dopo pochi secondi si ferma (cieco), con ogni profilo.

## Ponte per Claude (lib/bridge.rb)

- Un Ctrl+Z dell'utente durante una pausa della costruzione dal vivo non è
  coperto dalla guardia `bridge_building?`.

## Video: meteo nel video (lib/videometeo.rb)

- **Neve al suolo nei fotogrammi.** Il resto del meteo c'è. La neve al suolo
  sono triangoli sulle superfici, e la griglia di profondità di `vm_depth`
  non basta a coprirli bene. Proposta: geometria temporanea in un gruppo,
  che non getta ombre e ha i bordi nascosti, rifatta quando la camera si
  sposta di `SNOW_REBUILD`; l'opacità passa dall'alfa del materiale; il
  gruppo si toglie a fine export (e prima di un salvataggio).
- **La neve al suolo nell'orologio del video** parte dal livello che c'è
  quando comincia l'esportazione, non da zero: due esportazioni uguali
  possono differire lì.
