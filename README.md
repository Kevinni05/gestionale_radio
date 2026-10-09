# RadioTech — applicazione operatori

Client Flutter per operazioni tecniche sul campo: incarichi, check-in/check-out
GPS, report di manutenzione, firma e fotografie, PDF, inventario, notifiche e
strumenti RF. L'accesso richiede un account Firebase approvato con ruolo e
tenant assegnati.

## Runtime

- Flutter 3.44.9 / Dart 3.12.2 / Java 17.
- Firebase Authentication, App Check e Cloud Messaging.
- Backend Spring RadioTech via API autenticata.
- Endpoint di produzione HTTPS: configurato in compilazione.
- Report e allegati di produzione passano dal backend autenticato.
- Coda offline con idempotenza, retry limitato e isolamento per utente/tenant.
- Build release con firma Android stabile.

## Avvio locale

Avviare il backend Spring e indicare l'URL raggiungibile dal dispositivo:

```bash
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8080
```

Per un telefono fisico usare l'indirizzo IP del computer nella rete locale.
Le build release accettano soltanto endpoint di produzione HTTPS.

## Quality gate

Prima di una release:

```bash
flutter pub get --enforce-lockfile
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

La CI esegue analisi, test e build Android QA e rifiuta materiale di firma o
chiavi private tracciate accidentalmente. La distribuzione mobile firmata può
essere pubblicata automaticamente tramite Firebase App Distribution.

## Release e sicurezza

[RELEASE.md](RELEASE.md) descrive firma Android, App Check, simboli di debug e
requisiti iOS. [AUDIT_REPORT.md](AUDIT_REPORT.md) contiene lo stato aggiornato
dei controlli enterprise e i gate di accettazione.

La coda offline conserva l'identità e il tenant che hanno creato ciascuna
operazione: un cambio account sospende il replay. Gli allegati temporanei sono
limitati, validati e conservati nello storage privato dell'app fino alla
sincronizzazione. Non commettere credenziali Firebase Admin, keystore,
`key.properties`, file `.env` o configurazioni private.
