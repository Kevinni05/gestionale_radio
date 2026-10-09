# Release operativa Android 1.5.0+2021

Backend: `https://radiotechwebapp.onrender.com`. L'archivio allegati rimane Firestore.

- ONLINE indica una risposta valida dell'API; durante la verifica e in caso di errore mostra lo stato reale. I controlli si sospendono quando l'app va in background.
- Storico con pagine indipendenti da 30 report e 30 incarichi, ricerca sugli elementi caricati e caricamento aggiuntivo. Un errore sulla pagina successiva mantiene gli elementi già visibili.
- Il conteggio report usa una query aggregata del backend.
- Il controllo aggiornamenti verifica versione, identità applicazione, certificato e URL del repository GitHub previsto. Le build con una firma differente ricevono un avviso prima del passaggio alla versione di produzione.

La nuova chiave di produzione è `%USERPROFILE%/.radiotech/signing/radiotech-production.p12`; configurazione/password in `key.properties` nella stessa cartella privata. Nessuna chiave/password viene committata o salvata nella cartella OneDrive. Conservare una copia protetta separata; non rigenerare la chiave per gli aggiornamenti futuri. SHA-1/SHA-256 sono registrati in Firebase.

Certificato SHA-256: `73005990b6bad93b1bb3383121f6dcc2293b3e5e3a60e1ae7eaf09a7d97c4fa4`.

Build locale: `scripts/build-release.ps1`. Il workflow GitHub `production-release.yml` utilizza secret cifrati e verifica la firma dell'APK. Produce APK/AAB e artefatti con i simboli cifrati AES-256-GCM; la chiave dei simboli è separata in `%USERPROFILE%/.radiotech/signing/symbols.key`. Gli artefatti della release sono conservati per 30 giorni. La pubblicazione pubblica richiede `publish=true`; il default conserva solo gli artefatti della build.

Dopo la pubblicazione, lo script `sync-mobile-release.ps1` del backend verifica APK pubblicato, checksum e firma e prepara il manifest da committare. Il manifest attuale è predisposto con `available:false`; nessun download inesistente è presentato all'utente. APK locali e CI possono avere checksum diversi: attivare quello dell'artefatto effettivamente pubblicato.

La nuova firma non può aggiornare direttamente la build di test precedente. Nessuna disinstallazione o cancellazione dei dati sul telefono è eseguita da questo intervento. Verificare/salvare i report locali prima della prima installazione con la nuova firma. iOS non verificato su Windows.

Documentazione completa per monitoraggio, backup, restore e futura configurazione oggetti: repository web, `docs/OPERATIONS-RELEASE-2026-10-09.md`.

Verifiche locali dopo l'integrazione del commit remoto `a7884b0`: analisi Flutter senza problemi e **119 test superati**, inclusi paginazione con errori di rete, stato API e validazione del canale di aggiornamento.

Artefatti locali completati e verificati: `artifacts/RadioTech-1.5.0-2021.apk` (81.590.800 byte) e `artifacts/RadioTech-1.5.0-2021.aab` (73.987.205 byte), entrambi con il certificato di produzione indicato. APK verificato con apksigner, identità/versione con apkanalyzer; AAB compilato con esito Flutter positivo e verificato con jarsigner/keytool. L'APK include il permesso Internet e `libapp.so` per le tre architetture.

SHA-256 APK: `0cb596b8ef1a9907dfb5c9e29b03888a0d1c8464be83a3d999b09b7eaa1c7fad`.

SHA-256 AAB: `ee97794bc9820c5660cb8a5170328692520c2b26ca275a209abe75e43f54b13c`.

Gli Android command-line tools mancavano sul PC e impedivano la verifica finale del bundle; è stato installato il pacchetto ufficiale verificandone lo SHA-256 pubblicato da Google. Gli script accettano sia il formato certificato dei build-tools 36 sia quello dei build-tools 37.
