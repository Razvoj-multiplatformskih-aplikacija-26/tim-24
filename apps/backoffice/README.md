# Hedrion moderacija

Jedna Flutter aplikacija za Windows i veb. Posle `flutter pub get` iz korena, iz ovog direktorijuma pokreni:

```powershell
flutter run -d windows
flutter run -d chrome --web-port 8083
```

Podrazumevani KT1 režim ima 32 nezavisna lokalna zapisa sa svim stanjima i izabranog moderatora. Meni može da izazove grešku sledećeg zahteva ili vrati početne podatke. Primeri privatnih stanja prikazuju se samo u demonstracionom režimu.

Za stvarni moderatorski nalog i podatke servera:

```powershell
flutter run -d windows --dart-define=HEDRION_MODE=api --dart-define=HEDRION_API_URL=http://localhost:8080
flutter run -d chrome --web-port 8083 --dart-define=HEDRION_MODE=api --dart-define=HEDRION_API_URL=http://localhost:8080
```

Produkcija koristi HTTPS. Server proverava ulogu, reviziju i sva pravila. U API režimu dostupne su samo podnete prijave; prikazuje se slika konkretne podnete verzije. Odobrenje objavljuje njen snimak, a odbijanje uz razlog zadržava privatni rezultat kreatora. Veb koristi poseban HttpOnly refresh kolačić za backoffice.

Browser port mora odgovarati `CORS_ORIGINS`; podrazumevani spisak uključuje
`http://localhost:8083`. Za lokalni HTTP podesiti `SECURE_COOKIES=false` i koristiti
`localhost` i za browser aplikaciju i za API adresu.

Prečice: strelice gore/dole biraju zapis, `Ctrl+Enter` odobrava, `Ctrl+Backspace` otvara odbijanje uz razlog, `Ctrl+R` osvežava. `Tab` prolazi kroz fokusabilne zapise i akcije; fokus ima vidljiv ljubičasti okvir. Pri sužavanju prozora tabela prelazi u listu i čuva izabrani zapis.

```powershell
flutter analyze
flutter test test
```
