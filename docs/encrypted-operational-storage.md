# Archivio operativo Android

Android conserva coda offline, copia di recupero, bozze, ricevute e chiavi di idempotenza in SQLite con transazioni. Ogni valore e cancellazione è autenticato e cifrato AES-256-GCM con una chiave non esportabile Android Keystore. Gli identificativi dei record sono hash. Le foto gestite nella directory operativa sono cifrate con la stessa chiave, IV casuale e contesto legato all'operazione e al nome file. Il mittente legge i byte decifrati in memoria; non crea copie temporanee in chiaro per l'upload.

## Migrazione e recupero

- La migrazione da SharedPreferences avviene al primo accesso, dopo la validazione del contenuto. Le chiavi precedenti sono rimosse solo dopo il commit nativo. Le due copie della coda sono scritte nella stessa transazione.
- Una cancellazione lascia un record autenticato: un vecchio valore rimasto nelle preferenze non può riapparire.
- Una foto precedente in chiaro viene protetta durante la lettura o lo staging. I file non ancora visitati non sono già migrati: non dichiarare una bonifica completa del dispositivo.
- Un errore di lettura, corruzione o indisponibilità della chiave interrompe l'operazione. Non equivale a una coda vuota e non autorizza la sovrascrittura. Una prova cifrata nel database impedisce l'uso silenzioso di una nuova chiave anche per nuovi record.
- La cifratura copre i file operativi dell'app, non eventuali originali conservati dalla fotocamera, galleria o altre app.
- La compatibilità non Android usa il vecchio adapter per sviluppo e test. Non offre le stesse garanzie del percorso Android.

## Aggiornamento e assistenza

Conservare applicationId e chiave di firma per aggiornare sul posto. Non disinstallare, cancellare i dati o cambiare firma con operazioni locali pendenti: la chiave Keystore non è esportabile e un backup del solo database non permette di recuperare i dati. Prima di un downgrade sincronizzare le operazioni e verificare le ricevute; le versioni precedenti non leggono il nuovo archivio. In caso di archivio non disponibile preservare l'installazione e i file, raccogliere solo informazioni diagnostiche prive di contenuti personali e contattare l'assistenza.

## Evidenza e limiti

I test Dart verificano il confine nativo, ordine di migrazione, errore senza fallback, cancellazioni e coppia atomica. I test nativi Robolectric verificano SQLite reale, rollback, riapertura, rifiuto della chiave errata, autenticazione delle cancellazioni e integrità/contesto delle foto. Il test usa una chiave software iniettata; non dimostra il comportamento del Keystore hardware. Restano obbligatorie prove su almeno due Android reali: aggiornamento firmato con dati pendenti, processo interrotto, riavvio, rete degradata, chiave indisponibile e memoria con foto realistiche.
