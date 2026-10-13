# Notifiche mobile: correzioni e collaudo residuo

Data: 13 ottobre 2026. Repository: `Kevinni05/gestionale_radio`.
Baseline: `93e89d7` (presenza RTDB), successiva alla baseline storica del piano.
Versione di base: `1.5.3+11002`; nessun rollout avviato da questo intervento.

## Difetti verificati nel codice

- Un errore durante il recupero iniziale del token FCM interrompeva la procedura
  prima dell'installazione dei listener di ricezione, rinnovo e apertura.
- Il tocco su una notifica generale non aveva una destinazione: venivano
  considerati soltanto payload con `taskId`.
- L'inbox già aperta non ascoltava l'arrivo di avvisi né il ritorno online.
- Una ricevuta locale veniva salvata prima di sapere se il banner fosse stato
  mostrato: un errore del plugin impediva il successivo tentativo.

Questi difetti del client non dimostrano quale punto abbia interrotto gli invii
segnalati in produzione. Il contratto del backend locale è stato confrontato in
sola lettura: `notificationId`, `tenantId`, `recipientUid`, eventuale `taskId`,
endpoint autenticato `/api/v1/operator/me/fcm-token`.

## Comportamento implementato

- Listener installati prima delle operazioni fallibili; lettura dell'avviso
  iniziale separata dalla registrazione del token.
- Recupero FCM su rinnovo identità/token, resume e ritorno della rete, con
  richieste serializzate e verifica dell'identità dopo le attese.
- Registrazione diretta dell'account approvato sul relativo endpoint FCM,
  eliminando l'auto-registrazione operatore ripetuta a ogni sincronizzazione.
- Notifica generale indirizzata all'inbox soltanto dopo approvazione della
  sessione; messaggio evidenziato. Notifica incarico indirizzata al task.
- Inbox aggiornata su ricezione, resume e ritorno online; incarichi aggiornati
  su push pertinente e recupero della connessione.
- Banner foreground anche per payload dati con `title`/`message`; ricevute
  persistenti separate per account, azienda e visualizzazione/apertura.
- Cambio account: rotazione token e cancellazione banner prima della nuova
  associazione. Il proprietario del token è conservato nello storage operativo
  per rilevare il cambio anche dopo un riavvio. Se la rotazione fallisce, il
  nuovo account resta senza associazione push fino al successivo recupero.
- Logout: attesa della registrazione in corso prima della rimozione; richieste
  sospese fino all'uscita dell'identità precedente.
- Log senza token, payload o corpi delle risposte API.

Il codice presenza della baseline è stato formattato e corretto per gli avvisi
del linter; i registranti macOS/Windows includono il plugin RTDB già dichiarato
nella baseline.

## Evidenze automatiche

- `flutter pub get --enforce-lockfile`.
- `flutter analyze --no-pub`.
- `flutter test --no-pub --reporter expanded --timeout 2m`.
- `flutter build apk --debug --no-pub --target-platform android-arm64 --dart-define-from-file=config/render.json`.

Risultato locale: formattazione verificata senza modifiche, analisi senza
segnalazioni e 163 test superati. La build debug arm64 è compilata localmente.

Le regressioni coprono errore FCM iniziale, cold start, inbox generale, apertura
incarico, aggiornamento e deduplicazione, errore del banner, destinatario/azienda
errati, HTTP 503 con recupero su resume, cambio identità durante il recupero del
token, logout, sostituzione diretta account e rotazione temporaneamente fallita.
Sono prove con dipendenze controllate: non attestano consegna FCM reale.

## NOTIF-03: P0 ancora da validare in ambiente integrato

Nel dispositivo Android collegato è stata rilevata in sola lettura la versione
installata `1.5.3`, codice `11002`, Android 16. La build candidata non è stata
installata sopra quella versione e non sono state inviate notifiche di prova
agli operatori di produzione.

Per chiudere T15/T16 occorre distribuire una build candidata firmata con codice
versione crescente e usare due dispositivi/account autorizzati:

1. Dashboard distribuita: notifica generale a un destinatario, poi a più
   destinatari; assegnazione di un incarico.
2. Ripetere con app aperta, in background e normalmente terminata. Registrare
   ID operazione, destinatari, versioni web/API/mobile e tempi di ricezione.
3. Verificare separatamente dati in inbox/incarichi, banner del sistema e
   apertura della destinazione corretta, senza duplicazioni.
4. Ripetere con permesso negato, rete assente/ritorno online, rinnovo token e
   logout/login con altro account. Verificare assenza di avvisi del vecchio
   account e di dati di aziende diverse.
5. Annotare esito provider e ricezione sul dispositivo separatamente. Un HTTP
   200 o un'accettazione FCM non costituiscono prova di consegna sul telefono.

L'arresto forzato dalle impostazioni Android richiede la riapertura dell'app per
riprendere la ricezione: [documentazione Firebase](https://firebase.google.com/docs/cloud-messaging/flutter/receive-messages).
Il background handler gestisce l'aggiornamento badge; le comunicazioni operative
in background usano il payload `notification` del backend. La nuova gestione
dei messaggi dati riguarda il foreground.

Accesso persistente, revoca, restore, report/stock e tutte le altre voci del
piano mantengono i rispettivi gate: questo intervento non certifica l'intera
release Enterprise.
