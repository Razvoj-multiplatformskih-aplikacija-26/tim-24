# Studio redesign

Rad je na branch-u `design-redesign`. Vizuelna osnova prati priložene reference starog Meshy interfejsa, uz Hedrion identitet: ugljenosiva pozadina, limeta akcije, uska navigacija i tri panela.

## Pregled bez servera ili GPU-a

Iz korena repozitorijuma:

```sh
dart run apps/public_web/bin/preview.dart
```

U drugom terminalu:

```sh
cd apps/mobile
flutter run -d chrome --web-port 8082
```

Landing: `http://127.0.0.1:8081`. Studio: `http://localhost:8082/#/workspace`.

Preview server služi isključivo šest jasno označenih lokalnih ilustracija za pregled dizajna. Standardni `apps/public_web/bin/server.dart` i dalje prikazuje samo odobrene objave iz javnog API-ja. Ako javni API nije dostupan, početna stranica i ulazak u studio ostaju dostupni.

## Tokovi i granice ove faze

- `/workspace?flow=text-to-3d`: prompt, model, Standard/Low Poly, tekstura, poza i seed.
- `/workspace?flow=image-to-3d`: lokalni PNG/JPEG do 10 MB, opcioni prompt, model i podešavanja. U API režimu čuvanje nacrta koristi postojeći upload endpoint.
- `/workspace?flow=text-to-image`: prompt, izbor image modela i kvadratni demo koncept.
- **Novi model** otvara studio. U opcionim detaljima mogu da se unesu naziv, kategorija, projekat i oznake.
- `/` ostaje privatna biblioteka, sa novim CTA blokom. Projekti, objave, detalji, postojeće generisanje i offline sinhronizacija ostaju povezani.

`GenerationSetup` čuva podešavanja nezavisno od AI providera. Dugme **Prikaži demo uzorak** koristi `LocalPreviewGateway` za prikaz unapred pripremljene lokalne geometrije i ne utiče na kvotu.

U toku **Text to 3D** dugme **Zatraži demo generisanje** upisuje privatni model kao nacrt, odmah šalje zahtev i po prijemu otvara detalje sa statusom posla. Ako zahtev bude odbijen, unos ostaje u formi, a ponovni pokušaj koristi isti nacrt. U API režimu opcija je dostupna kada je server oglašava u `/api/v1/capabilities`. Lokalni KT1 demo beleži zahtev u memoriji, a API sa fake workerom proizvodi demonstracioni GLB.

U toku **Image to 3D** dugme **Sačuvaj nacrt** otvara detalje modela, odakle **Zatraži generisanje** šalje zahtev.

Interaktivni viewport renderuje lokalne 3D uzorke: prevlačenje rotira, skrol/pinch zumira, desni drag pomera, dvoklik/reset vraća kameru. Studio, clay, wireframe, grid i fullscreen rade lokalno. Sačuvani API modeli trenutno koriste postojeći 2D thumbnail; GLB loader je sledeća faza.

Demo istorija, referentna slika i provider podešavanja važe za trenutni workspace. Čuvanje 3D nacrta trajno upisuje naziv i prompt u postojeći repozitorijum (u memoriju u demo režimu, na server u API režimu). Image koncepti ne stvaraju lažan 3D asset. Za produkcionu inferenciju treba proširiti ugovor posla podešavanjima i izlaznim tipom.

CTA linkovi nose izabrani tok u hash ruti. U API režimu postojeća prijava/registracija zadržava rutu i nakon prijave otvara pravi tok. Podrazumevani KT1 demo, kao i ranije, radi bez naloga.

Na užim ekranima paneli prelaze na Create/Preview/Assets tabove; privatna biblioteka i detalji ostaju prilagođeni telefonu.
