# RadioTech — applicazione operatori

Client Flutter per incarichi sul campo, check-in GPS, report di manutenzione, firma e allegati, inventario, notifiche e strumenti RF. L'accesso richiede un account Firebase approvato con ruolo e tenant assegnati.

## Avvio locale

Avviare il backend Spring e indicare l'URL raggiungibile dal dispositivo:

```bash
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8080
```

Per un telefono fisico usare l'indirizzo IP del computer nella rete locale.
In produzione usare sempre un endpoint HTTPS.

## Verifica e distribuzione

Usare Flutter 3.44.9, eseguire `flutter analyze` e `flutter test`. La pipeline CI compila anche l'APK Android QA.

[RELEASE.md](RELEASE.md) descrive endpoint HTTPS, firma Android, App Check, simboli di debug e requisiti iOS. Non usare l'APK debug per la distribuzione sullo store.

La coda offline conserva l'identità e il tenant che hanno creato ciascuna operazione: un cambio account ne sospende l'invio. Gli allegati locali non hanno ancora cifratura applicativa; i controlli e i limiti sono documentati nella guida infrastruttura `radiotechwebapp/DEPLOYMENT.md`.
