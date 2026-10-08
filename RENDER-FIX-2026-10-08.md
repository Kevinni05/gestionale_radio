# Report e incarichi su Render — 8 ottobre 2026

Versione 1.4.2, build 2020 (superiore alla build 2019 presente sul telefono).

- API: `https://radiotechwebapp.onrender.com`.
- Compilare con `flutter build apk --debug --dart-define-from-file=config/render.json`.
  La CI usa la stessa configurazione. Un indirizzo definito in compilazione
  prevale sui vecchi indirizzi di test salvati nel dispositivo.
- Gli allegati passano dal backend, che li conserva nell’archivio Firestore persistente.
- Storico e contatore report condividono l’API autenticata. Lo storico si aggiorna
  al rientro nell’app e alle notifiche di avanzamento; un errore degli incarichi
  accessori non nasconde i report già caricati.
- Corretti il pulsante Aggiorna e i report senza `taskId`; i PDF storici mancanti
  possono essere ricostruiti dai dati registrati con un’avvertenza nel documento.
- Riconosciuto anche lo stato storico `IN LAVORAZIONE` e aumentata l’attesa per
  il server in avvio. Le operazioni offline e le chiavi di idempotenza sono conservate.

Verifiche: `flutter analyze` senza segnalazioni, 109 test superati e build APK
completata. APK installato sul telefono collegato con aggiornamento, senza
cancellazione dei dati dell’app.

Artefatto locale: `artifacts/RadioTech-Render-1.4.2.apk` (build di test, esclusa da Git).
SHA-256: `efde3197ba8bc214a0b0c27cd12f1d9713711f39d2b46f66f6f7767d59411d21`.

Il nuovo backend deve essere distribuito da Render per servire gli allegati
recuperati e le assegnazioni storiche. Il solo push del repository mobile non
aggiorna i telefoni: occorre installare l’APK, oppure distribuire una release firmata.
