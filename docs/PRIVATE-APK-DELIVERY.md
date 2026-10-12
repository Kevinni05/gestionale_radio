# Distribuzione privata APK sul sito del proprietario

Canale scelto il 12 ottobre 2026: APK firmati tramite area autenticata del servizio HTTPS RadioTech esistente, con avvisi comunicati dal proprietario. Non serve acquistare un dominio per il test. Nessun messaggio viene inviato automaticamente.

## Area autenticata RadioTech

Build corrente: **1.5.3+11002**, manifest `https://radiotechwebapp.onrender.com/api/v1/distribution/latest.json`. Login Firebase e tenant sono richiesti sia al manifest sia al download APK. Il token viene trasmesso soltanto all'origin API e alla route distribution; nessun token negli URL o verso altri host. Il pannello Sistema della web app consente il download e verifica SHA256. Il codice nativo verifica SHA256, applicationId, versionCode e firma prima dell'installatore Android.

Nel test i byte immutabili sono in Firestore, chunk 512 KiB, mentre la release disponibile è un puntatore tenant-scoped. Billing risulta già attivo sul progetto Firebase, ma non esiste un bucket: non è stato cambiato il piano né attivato Storage. Per l'azienda adottare object storage privato con costi e retention approvati, mantenendo lo stesso contratto API. Pubblicare con `scripts/publish-private-release.ps1` del repository backend: verifica certificato originale e identità dell'APK, carica prima i byte verificati, aggiorna per ultimo il puntatore e registra audit. Conservare chiavi, simboli e artefatti fuori da Git.

Sul Samsung collegato sono riusciti seed, force-stop, riapertura e sostituzione APK QA 11000→11001 con bozza/coda/ricevuta conservate. La prova usa applicationId `.qa` e lascia intatta l'app commerciale. Non certifica GPS/camera/FCM/App Check; questi restano nel collaudo sul campo. [Backlog unico](https://github.com/Kevinni05/radiotechwebapp/blob/main/docs/commercial-progress.md) e [costi/handover proposti](https://github.com/Kevinni05/radiotechwebapp/blob/main/docs/COMPANY-COSTS-AND-HANDOVER.md).

## Alternativa futura: sito con dominio proprio

1. Conservare il keystore esistente e una copia recuperabile separata. Configurare ANDROID_EXPECTED_SIGNING_SHA256 con il certificato di produzione, senza inserire chiavi nel repository.
2. Creare il sito HTTPS e una cartella per gli aggiornamenti. Il manifest e l'APK devono essere sullo stesso origin, senza redirect verso altri domini, credenziali negli URL o query string. Se si vuole limitare chi può scaricare, progettare prima l'autenticazione: il semplice possesso di un URL non è controllo d'accesso.
3. Eseguire `./scripts/build-release.ps1 -UpdateManifestUrl https://DOMINIO-REALE/download/latest.json -BuildNumber NUMERO`. La procedura verifica backend/readiness, test, firma e numero di versione; genera APK, AAB, `artifacts/latest.json` e `artifacts/avviso-aggiornamento.txt`. Senza URL resta disponibile il canale configurato sul backend; la nuova origine privata resta disabilitata.
4. Pubblicare prima il nuovo APK e verificarne il digest scaricandolo dal sito; pubblicare per ultimo latest.json, in modo atomico. Manifest: Cache-Control no-cache; APK versionato: immutable. HTTPS deve avere un certificato valido. Le credenziali del sito non vanno incorporate nel pacchetto.
5. Comunicare personalmente l'avviso ai clienti. L'app controlla applicationId, incremento versionCode, SHA256 del file e certificato uguale a quello installato. Il codice nativo verifica anche il pacchetto prima di consegnarlo all'installatore Android. L'installazione richiede il consenso dell'utente Android.
6. Conservare APK precedente, simboli privati, manifest, commit e digest. Non disinstallare per aggiornare: la sostituzione con stessa firma conserva i dati Android. Provare l'upgrade con coda/bozze sintetiche prima della consegna. Per rollback distribuire codice precedente con nuovo versionCode superiore; Android impedisce il normale downgrade.

## Collaudi e limiti

Il test operativo nativo è passato sul Samsung SM-S731U collegato: apertura successiva del database cifrato, transazione e cancellazione, ricevute notifiche e separazione account. L'installazione QA usa com.example.gestionale_radio.qa; non modifica i dati dell'installazione commerciale. La CI include lo stesso test su Android 34 emulato. QR, GPS, foto, FCM, App Check e upgrade completo richiedono prove distinte: il test dell'archivio non ne certifica il funzionamento.

Il sito senza login rende gli APK scaricabili a chi conosce il link. L'accesso ai dati aziendali resta protetto dalle API e dai tenant; l'eventuale distribuzione riservata ai soli clienti richiede una soluzione di accesso al download compatibile con l'app. La firma impedisce l'accettazione di pacchetti alterati, ma non sostituisce il controllo d'accesso al sito.

Build preparata: 1.5.2+11000, superiore alla release già distribuita 10074. CI e consegna privata usano lo stesso versionCode canonico di pubspec.yaml; incrementarlo nelle release successive. Il certificato del keystore esistente ha SHA256 73005990b6bad93b1bb3383121f6dcc2293b3e5e3a60e1ae7eaf09a7d97c4fa4. Conservare il digest specifico dell’APK consegnato: una ricostruzione può avere byte diversi.

