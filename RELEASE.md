# Revisione layout e storico PDF — 7 ottobre 2026

Versione **1.4.1**, versionCode **2019**, ARM64, installata sul Samsung S25 FE senza disinstallazione. SHA256 `2A21F1558DBC0539B5AE7C20B42DF3343DFF5FAAA1EE7344323C8EF2CB005DC0`. Firma e allineamento ZIP 16 KB verificati.

Calendario rimosso dalla mappa, box note con padding, Enterprise Pro ed editor centrati, AI senza area chat di altezza fissa, misure report adattabili e palette/contrasto corretti, storico raggruppato per compito con apertura e download del solo PDF. Salvataggio Android tramite selettore documenti di sistema, senza permessi di accesso generale ai file.

104 test Flutter e 9 ricontrolli finali superati; analisi senza segnalazioni. Log `qa-layout-tests.log`, `qa-layout-final-regression.log`, `qa-layout-analyze.log`, `qa-layout-build.log`. Guida `AGGIORNAMENTO-LAYOUT-1.4.1.md` nel progetto web.

# Aggiornamento operativo — 7 ottobre 2026

Versione **1.4.0**, versionCode **2018**, ARM64. Installata sul Samsung S25 FE con aggiornamento senza disinstallazione. Firma APK e allineamento ZIP 16 KB verificati. SHA256 `A24AF375E5052B08CBF683CA6A95DECEFF5E91F22DE349709EC36CFFF937EE87`.

SafeArea Android globale, mappa nelle Azioni operative, rimozione Riparazioni, selezione antenna e lista di controllo interattiva nei nuovi report, storico con visualizzazione/stampa dei PDF originali, calendario personale con note e promemoria, badge backend condiviso con il web e salvataggio in galleria, aggiornamento badge e reimpostazione password, AI con layout rivisto, stato operativo coordinato alla palette e traduzioni italiane.

**98 test Flutter superati**, analisi senza segnalazioni. Log: `qa-enterprise-tests.log`, `qa-enterprise-analyze.log`, `qa-enterprise-build.log`. Procedura e limiti dell’ambiente di test nella guida `AGGIORNAMENTO-OPERATIVO-1.4.md` del progetto web. Questa è una build di test con App Check debug; la distribuzione aziendale richiede firma e configurazione release.

# Calendario su richiesta — 7 ottobre 2026

Versione **1.3.3**, versionCode **2017**, ARM64, 115.233.942 byte. SHA256 `1ABE1443268B3E55A55D1C87776E67DF1D52B55BEBD0C05361254648ACD27EED`. Firma e allineamento ZIP 16 KB verificati; aggiornamento installato sul Samsung S25 FE con `adb install -r` (Success), mantenendo dati e sessione.

La home mostra il pulsante Calendario sotto il riepilogo operativo. Il calendario completo viene aperto soltanto premendo il pulsante, in una schermata dedicata; data e ora restano sotto il logo. Navigazione mensile, filtri, ricerca, agenda e collegamenti agli incarichi conservati. La prima apertura riutilizza i dati caricati dalla home; refresh e notifiche aggiornano le attività.

Analisi senza segnalazioni e 5 test di regressione del calendario/orologio superati (`qa-calendar-button-analyze.log`, `qa-calendar-button-tests.log`); build in `qa-calendar-button-build.log`.

# Invio report, PDF professionale e anteprime web — 6 ottobre 2026

Versione di test **1.3.2**, versionCode **2016**, ARM64. APK corrente: `artifacts/RadioTech-S25FE-enterprise-pro-test.apk`, 115.232.878 byte, SHA256 `488D49B653CDBF3B48D0D81CB08731F6E5F4159ABE5879668347D29291CD865A`. Firma e allineamento ZIP a 16 KB verificati. Installato sul Samsung S25 FE il 7 ottobre 2026 con `adb install -r` (Success), senza disinstallazione. Versione 1.3.2 / 2016 e avvio verificati.

Conferma dell'invio tramite dialogo standard visibile anche con animazioni ridotte e testo ingrandito. L'avanzamento distingue verifica invii precedenti, GPS, generazione PDF e caricamento. La conferma compare soltanto dopo la risposta del server e riporta riferimento e data di ricezione quando disponibili; il pulsante torna agli incarichi. Un errore sblocca i comandi per riprovare; la coda offline e la chiave di idempotenza restano operative.

I nuovi PDF A4 contengono logo ufficiale, nome dell'antenna letto dall'API (codice asset in un campo distinto), nome dell'operatore, data/ora locale dell'invio dal dispositivo con fuso, note, checklist, misure, materiali, segnalazioni, firma nero su bianco e fotografie su pagine dedicate. Header e numerazione su ogni pagina; font Inter incluso offline. I PDF già inviati conservano il loro contenuto originale.

**94 test Flutter superati** e analisi senza segnalazioni. Log: `qa-report-preview-analyze.log`, `qa-report-preview-tests.log`, `qa-report-preview-build.log`. Test nuovi: PDF con logo/foto/firma, conferma e chiusura del report, errore e riprova, prevenzione del doppio invio, testo ingrandito e animazioni ridotte. Esempio con dati fittizi: `artifacts/qa-professional-report.pdf`.

# Calendario home e orologio — 6 ottobre 2026

Versione di test **1.3.1**, versionCode **2015**, ARM64. APK corrente: `artifacts/RadioTech-S25FE-enterprise-pro-test.apk`, 115.221.878 byte, SHA256 `5E1D047DD6E6B6DE3A5F753B02FA0FAF0D6E3D68E7C0D6C3A9534CC4C34A7822`. Firma e allineamento ZIP a 16 KB verificati. L'installazione diretta non è stata eseguita: al termine della preparazione il telefono non era collegato ad ADB. Installare come aggiornamento per conservare sessione e bozze.

Calendario nella home: mesi/anni, selezione della data, pulsante Oggi, indicatori delle scadenze, attività del giorno, ricerca, filtri Attivi/In revisione/Tutti, prossime scadenze e incarichi senza data. Le attività aprono l'incarico corrispondente; il collegamento Agenda conserva la vista operativa esistente. Il calendario condivide i dati personali della home, senza richieste duplicate.

Data e ora sotto il logo, aggiornate ogni secondo secondo l'orologio locale del telefono: `6 Ottobre 2026 - 17:04:23`. Timer sospeso in background e quando la home è coperta da altre schermate.

Verifiche: **91 test Flutter superati**, analisi senza segnalazioni (`qa-calendar-tests.log`, `qa-calendar-analyze.log`). I test del calendario coprono cambio anno, febbraio bisestile, selezione giorno, filtri, ricerca e apertura attività a 320/740/1024 px con testo ingrandito; l'orologio copre secondi, mezzanotte, pausa e ripresa. Build in `qa-calendar-build.log`, con cache Gradle separata `.gradle/raycast-cli`.

# Aggiornamento mobile Signal / Raycast — 6 ottobre 2026

Versione di test **1.3.0**, versionCode **2014**, ARM64. APK corrente: `artifacts/RadioTech-S25FE-enterprise-pro-test.apk`, 115.203.198 byte, SHA256 `4A8C8CCBE2AB98E158E9B2D0597F5B349CD6F6DA52A02DCFFB290BF1D4284BA2`. Firma e allineamento ZIP a 16 KB verificati; installato sul Samsung S25 FE con `adb install -r`, mantenendo sessione e dati.

Endpoint iniziale: `https://locate-kingston-meter-dodge.trycloudflare.com`. La preferenza presente sul telefono è stata aggiornata al link attuale. Nelle build di test è possibile cambiarla da Profilo o Incarichi → Connessione al server, senza uscire dall'account. La connessione viene verificata prima del salvataggio.

Tema Signal condiviso con la web app: Inter locale, pannelli glass, fondo animato viola/corallo/blu, griglie allineate e comandi chiari. Incarichi: refresh da notifica e ripresa dell'app, fonte personale comune con la home, stati precedenti normalizzati e rapporto ancora disponibile per COMPLETED. Vedere `DESIGN.md` per i dettagli.

Verifica finale: `flutter analyze` senza segnalazioni; **86 test superati** (`qa-raycast-analyze.log`, `qa-raycast-tests.log`). Build registrata in `qa-raycast-build.log`: invocazione Gradle con cache separata `--project-cache-dir .gradle/raycast-cli`, gli stessi parametri Android ARM64/debug e dart-define dell'invocazione Flutter, dopo la preparazione di local.properties con versione 1.3.0 e build 14. La cache standard era bloccata dall'editor. Il flusso reale di incarico e rapporto via HTTPS è verificato nel progetto backend con `authenticatedSmoke` e fixture temporanee.

# RadioTech mobile — rilascio

Consegna notifiche del 6 ottobre 2026: installare come aggiornamento `artifacts/RadioTech-S25FE-notifications-test.apk` (ARM64 debug, versionCode 2005, SHA256 `CC02EFCC640C4DE031A86C4962E6186959CEFD20476752507A8F7F1938F7587D`). La lista usa l'API personale autenticata `/api/v1/operator/me/notifications`, con aggiornamento/riprova e collegamento agli incarichi quando presente. Sostituisce il flusso allarmi/Firestore che produceva PERMISSION DENIED. 68 test Flutter e analisi superati; firma e allineamento 16 KB verificati. Dettagli backend e limiti in `radiotechwebapp/NOTIFICATIONS-FIX-2026-10-06.md`. Endpoint locale iniziale `http://192.168.1.227:8080`; conservare l'installazione esistente per mantenere sessione e report locali.

APK corrente con comando server visibile: `artifacts/RadioTech-S25FE-config-test.apk`, build debug ARM64 numero 4 (versionCode della variante 2004), endpoint iniziale `http://192.168.1.227:8080`, 112.503.532 byte, SHA256 `2CB50A7048D946B8AFC8AD5B8F85CA8E54D6C61C1E1B627989991771AD85A97A`. Il pulsante **Configura Server Backend** è ora sotto **Accedi con QR**, insieme all'indirizzo corrente. Sostituisce l'ingranaggio posto dietro il contenitore del login. Finestra server scorrevole e titolo adattabile agli schermi stretti. Test widget a 320×640: apertura, salvataggio, persistenza e aggiornamento dell'indirizzo superati; analisi Flutter senza problemi, APK compilato, firma e allineamento ZIP 16 KB verificati. Le impostazioni salvate dall'installazione precedente rimangono prioritarie rispetto al valore iniziale della build.

Aggiornamento login QR del 5 ottobre 2026: usare `artifacts/RadioTech-S25FE-LAN-test.apk` per il test locale concordato con telefono e PC sulla stessa Wi-Fi. Endpoint iniziale `http://192.168.1.227:8080`, ARM64, versionCode **2003**, 112.510.788 byte, SHA256 `5A1CFFB4F33DF102846914C9360E2DC6870C9EAA6F01E8E3B1C9F30FCE88B93F`. Build debug con numero 3 e `--dart-define=API_BASE_URL=http://192.168.1.227:8080`. Firma e allineamento ZIP 16 KB verificati. Se un indirizzo era già salvato, resta prioritario: nella schermata di accesso aprire Configura Server Backend, impostare l'IP corretto, provare la connessione e salvare. L'IP può cambiare sulla rete; questo APK non è una distribuzione di produzione.

Il login QR distingue ora connessione, credenziali rifiutate e risposta server errata, usa un'attesa massima di 20 secondi per lo scambio QR e non ripete automaticamente la scansione dopo un errore (i badge possono essere monouso). La prova connessione verifica `/api/v1/health` e l'identità della centrale RadioTech. Analisi Flutter senza problemi e tutti i **65 test** superati, inclusi 8 nuovi test di regressione QR. Le verifiche HTTP dal PC hanno confermato health UP e validazione del body del login QR sulla LAN; l'utente ha confermato che l'URL health si apre anche dal telefono. L'accesso completo con badge reale resta da confermare dall'utente.

APK per il test sul Samsung S25 FE (5 ottobre 2026): `artifacts/RadioTech-S25FE-test.apk`, ARM64, 112.508.556 byte, SHA256 `AEE6C9CA11FFE2EA5CC22EFA66A2A19D8CAB3F63E112BF7265C474137A0F5373`. Firma v2 e allineamento ZIP a 16 KB verificati; le librerie native ARM64 del pacchetto originario hanno segmenti ELF allineati ad almeno 16 KB. Generato con `flutter build apk --debug --split-per-abi --target-platform android-arm64 --build-number 2`: Flutter assegna alla variante ARM64 il versionCode **2002**. Il pacchetto usa la chiave debug esistente, non una chiave di produzione. L'installazione sul telefono rimane da confermare: nessun dispositivo ADB era collegato.

Se Samsung mostra «app non installata», verificare il download completo, il permesso «Installa app sconosciute» per l'app che apre il file e il Blocco automatico in Sicurezza e privacy ([guida Samsung](https://www.samsung.com/us/support/answer/ANS10003636/)). Disabilitare il Blocco automatico solo per il test di questo APK e riattivarlo dopo. Se persiste, collegare il telefono con debug USB e acquisire il risultato di `adb install -r artifacts/RadioTech-S25FE-test.apk`: il codice INSTALL_FAILED permette di distinguere firma, versione, spazio e altri vincoli. Non disinstallare altre copie o cancellare dati senza controllare eventuali report locali.

Aggiornamento del 5 ottobre 2026: aggiunta **Agenda interventi**, corretta la coda dei report approvati, apertura in evidenza degli incarichi da notifica/agenda e rendering della checklist Telco. Il collaudo corrente e la checklist con dispositivi reali sono in `radiotechwebapp/ACCEPTANCE-2026-10-05.md`. Usare l'APK ricompilato dopo queste modifiche, non gli hash storici del 3 ottobre.

L'app include ora **AI e previsioni** e **Squadra e sicurezza**. Gli utenti accedono al modello centrale tramite l'API HTTPS; nessun modello va installato sul telefono. La chat richiede il servizio AI del backend attivo. Le segnalazioni e i cambi di turno richiedono rete attiva; una mancata risposta non viene mostrata come registrazione riuscita. La guida `radiotechwebapp/ENTERPRISE_AI.md` descrive il deploy autoconfigurante e i controlli di accesso.

Flutter 3.44.9 / Dart 3.12.2, Java 17 e Android SDK 36. Firebase usa il progetto `gestionale-radio`. Non modificare application ID o configurazioni Firebase senza registrare nuovamente le app.

```powershell
flutter pub get
flutter analyze
flutter test
flutter build apk --debug --dart-define=API_BASE_URL=http://10.0.2.2:8080
```

L'APK debug è un artefatto QA, non una release per lo store. Il backend dell'emulatore Android è raggiungibile su `10.0.2.2`; un telefono reale deve usare l'IP LAN del server di sviluppo. Solo la variante debug permette HTTP. In release l'endpoint è HTTPS, fissato in compilazione, e App Check debug è vietato.

Per una release firmata copiare `android/key.properties.example` in `android/key.properties` con la chiave di upload esistente, oppure impostare `ANDROID_KEYSTORE_PATH`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`. Non commettere chiavi, password o simboli di debug.

```powershell
.\scripts\build-release.ps1 -ApiBaseUrl https://DOMINIO-API-REALE -BuildNumber 2
```

Lo script rifiuta backend non RadioTech/non ready e signing assente. L'AAB viene prodotto in `build/app/outputs/bundle/release/app-release.aab`; conservare `release-symbols` con il numero build. Il file `config/production.example.json` è un modello, non un endpoint attivo.

Su iOS servono macOS/Xcode, team/provisioning, APNs e Push Notifications. La build iOS non è verificabile da Windows. Verificare camera/QR, GPS accurato, foto, PDF/firma e ricezione notifiche su dispositivi reali; Android Play Integrity e Apple DeviceCheck richiedono la configurazione Firebase appropriata.

La CLI Firebase e il SDK Flutter restano tool esterni; non sono inclusi nell'app. Il vecchio plugin Kotlin è mantenuto per compatibilità Flutter 3.44.9. [La migrazione built-in Kotlin richiede Flutter 3.47+](https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin/for-app-developers), da validare come aggiornamento separato.

La documentazione infrastruttura completa è `radiotechwebapp/DEPLOYMENT.md`. Il sito `gestionale-radio.web.app` non serve l'API Spring al 3 ottobre 2026; l'URL di produzione deve essere definito e verificato prima del rilascio. È stato inizializzato un repository Git locale sul ramo `main`, senza commit o pubblicazione: collegarlo al remoto mobile e attivare la pipeline presente in `.github/workflows/ci.yml`.
