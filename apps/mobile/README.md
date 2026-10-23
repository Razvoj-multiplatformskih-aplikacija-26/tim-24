# Hedrion studio

Isti Flutter kod radi na Androidu i vebu. Iz korena repozitorijuma prvo pokreni `flutter pub get`.

KT1 režim iz ovog direktorijuma:

```powershell
flutter run -d chrome --web-port 8082
flutter run -d <android-device-id>
```

Režim sa serverom:

```powershell
flutter run -d chrome --web-port 8082 --dart-define=HEDRION_MODE=api --dart-define=HEDRION_API_URL=http://localhost:8080
flutter run -d <android-device-id> --dart-define=HEDRION_MODE=api --dart-define=HEDRION_API_URL=http://10.0.2.2:8080
```

`10.0.2.2` je adresa računara iz Android emulatora. Release koristi HTTPS; debug dozvoljava lokalni HTTP. Za fizički telefon koristi dostupan HTTPS server ili `adb reverse tcp:8080 tcp:8080` sa API adresom `http://localhost:8080`.

Za browser studio port mora odgovarati serverskom `CORS_ORIGINS`; podrazumevani
spisak uključuje `http://localhost:8082`. Za lokalni HTTP podesiti
`SECURE_COOKIES=false` i zadržati `localhost` i u adresi UI-ja i u adresi API-ja.

KT1 ima nezavisnu memorijsku biblioteku sa svim stanjima i unapred izabranim kreatorom. Meni sadrži grešku sledećeg zahteva, vraćanje početnih podataka i primere odbijanja globalnih kvota. Podaci se vraćaju na početne nakon novog pokretanja KT1 režima. Ilustracije u ovom režimu nisu AI rezultati.

U API režimu prijavi isti nalog na telefonu i vebu. Slika se šalje pri čuvanju nacrta; generisanje se zasebno pokreće iz detalja. Server nastavlja posao kada se aplikacija zatvori. Pregled koristi stvarnu sliku rezultata; GLB preuzimanje u pregledaču čuva fajl, a Android otvara sistemski dijalog za deljenje/čuvanje. Interaktivni 3D viewport nije implementiran. Tekstualni unos nije aktivan.

Na Androidu SQLite trajno čuva biblioteku i outbox u jednoj transakciji. Izmeni naziv, opis ili omiljeni model bez mreže; status prikazuje izmene koje čekaju. Posle ponovnog povezivanja koristi „Sinhronizuj“ ili sačekaj automatsku proveru. Konflikt zahteva izbor serverske verzije ili izričito ponovno primenjivanje lokalne. Tokeni se čuvaju u Android zaštićenom skladištu, a veb obnavlja sesiju kroz HttpOnly kolačić servera.

Provere:

```powershell
flutter analyze
flutter test test
```

Za proveru stvarne Android mreže i trajnog skladišta koristi `integration_test/offline_device_test.dart` u tri zasebna pokretanja sa `DEVICE_TEST_PHASE=prepare`, `offline`, `sync`, istim `DEVICE_TEST_EMAIL`/`DEVICE_TEST_PASSWORD` i `HEDRION_API_URL`. Nakon prve faze isključi mrežu emulatora; pre treće je uključi. Ne briši podatke aplikacije između faza. `prepare` registruje zaseban novi test nalog. Opcija `DEVICE_TEST_EXPECT_CONFLICT=true` u poslednjoj fazi proverava konflikt ako je isti model u međuvremenu izmenjen drugim klijentom. Tačne izvršene provere i ograničenja navodi korenski README.
