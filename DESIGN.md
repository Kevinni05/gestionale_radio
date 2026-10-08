# RadioTech Signal — mobile

Il tema Flutter riprende il design della web app e il riferimento [Raycast su Refero](https://styles.refero.design/style/3b6a17f0-3bdf-418c-a95e-0b89e5a8b2f8), adattato agli schermi touch.

- Font Inter variabile incluso nell'app, disponibile anche offline; licenza SIL OFL in `assets/fonts/INTER-LICENSE.txt`.
- Sfondo quasi nero `#08090d`, atmosfera viola/corallo/blu e geometria del segnale originale. Il movimento si arresta in background e rispetta la riduzione delle animazioni del sistema.
- Pannelli glass con blur circoscritto di 10 px, bordo sottile e raggio 16 px; pannelli principali 20 px. Logo RadioTech ufficiale.
- Comandi principali chiari `#e6e6e6`, testo scuro; corallo `#ff6363` per focus e feedback. Verde, ambra e rosso restano riservati agli stati operativi.
- Padding 16–24 px, distanze 8/12/16/24 px, aree touch almeno 48 px. Le azioni della stessa griglia hanno dimensioni uguali e zone coerenti per icona, titolo e descrizione.
- Il numero di colonne dipende dallo spazio effettivo del contenitore e dal testo ingrandito. Moduli, liste e pulsanti possono scorrere; i testi importanti non vengono coperti da elementi fissi.
- Transizioni di pagina leggere e feedback luminoso alla pressione delle azioni, disattivati quando il sistema richiede meno movimento.
- Copyright: Kevin Cagnazzo e Anthony Piccinonno.

Gli incarichi della home e della schermata dedicata provengono dallo stesso endpoint personale. La lista si aggiorna alla ricezione di una notifica operativa e al ritorno dell'app in primo piano. Gli interventi COMPLETED restano attivi fino all'invio del rapporto; REPORT_SUBMITTED passa alla revisione. I comandi accompagnano accettazione, trasferimento, check-in GPS, avvio e rapporto senza saltare i controlli del backend.

Nelle build di test la connessione al server è configurabile anche da Profilo e Incarichi. Il nuovo indirizzo viene verificato prima del salvataggio, senza cancellare sessione o bozze. La distribuzione aziendale mantiene l'endpoint HTTPS stabilito al rilascio.

Il pulsante Calendario nella home apre una schermata dedicata con un calendario glass con settimana da lunedì a domenica, navigazione fra mesi e anni, selezione rapida della data e ritorno a oggi. Le scadenze degli incarichi personali sono evidenziate nei giorni; ricerca e filtri Attivi/In revisione/Tutti aggiornano sia gli indicatori sia i dettagli. Le attività del giorno, le prossime scadenze e gli incarichi senza data si aprono nella schermata Incarichi. Il calendario usa la stessa richiesta della home e non crea eventi fittizi.

Sotto il logo, data e ora locali del telefono sono mostrate nel formato `6 Ottobre 2026 - 17:04:23`. Solo l'orologio si aggiorna ogni secondo: non vengono ricaricati home o dati del server. Il timer si ferma quando l'app è in background o la home è coperta da un'altra schermata, e si riallinea al ritorno.
