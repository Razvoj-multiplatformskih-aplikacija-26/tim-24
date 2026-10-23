# Hedrion javna biblioteka

Jaspr 0.23.5 isporučuje HTML na serveru. Pretraga, kategorije i pojedinačne stranice
rade bez JavaScript-a i prijave. Aplikacija koristi isključivo javne rute Dart API-ja;
ne čita PostgreSQL niti privatne modele direktno.

Iz korena projekta prvo pokrenuti `flutter pub get`, zatim:

```powershell
cd apps/public_web
$env:API_ORIGIN = 'http://127.0.0.1:8080'
$env:PUBLIC_ORIGIN = 'http://localhost:8081'
$env:STUDIO_ORIGIN = 'http://localhost:8082'
dart run bin/server.dart
```

Podrazumevani `HOST` je `127.0.0.1`, a `PORT` je `8081`. Za kontejner postaviti
`HOST=0.0.0.0`, a za javnu instalaciju sve tri adrese podesiti na stvarna HTTPS
porekla. Origin sme sadržati samo šemu i host/port, bez putanje ili kredencijala.

Rute: `/`, `/assets?q=&category=&page=&cursor=`, `/assets/{slug}`,
`/categories/{category}`, `/sitemap.xml`, `/robots.txt`, `/about`, `/privacy`,
`/report`. Paginacija koristi stabilan serverski slug cursor; direktan broj stranice
razrešava se na serveru. Pretraga ima najviše 100 znakova, a indeks stranice 1–100.
Sitemap prati sve javne stranice do 10.000 modela i odbija neispravan/ponovljen
cursor umesto beskonačne petlje. Za veći katalog dodati sitemap indeks.

Svaka stranica ima naslov, opis i canonical adresu; detalj ima OpenGraph sliku i
autora/licencu. Tekst i atributi prolaze kroz Jaspr HTML escaping. Search rezultati
i greške imaju `noindex`; nedostupan API daje `503` sa ponovnim pokušajem, a
nepostojeći ili povučeni model `404`. Nema lažnog sadržaja kada API nije dostupan.

Preview i GLB vode ka meterenim `/api/v1/public/assets/{slug}/files/{kind}` rutama.
Adrese objektnog skladišta iz odgovora ne koriste se. Preuzimanje je vidljivo samo
za dozvolu autora i CC BY/CC0; server ponovo odlučuje o dozvoli i kvoti. Pregled je
jasno označena slika, bez neproverenog 3D plugina.

Provere:

```powershell
dart format --output=none --set-exit-if-changed lib bin test
dart analyze
dart test
```

Testovi renderuju stvarni Jaspr HTML preko mock javnog API-ja i proveravaju
escaping, javnu vidljivost, licence, URL-ove meterenog prenosa, pretragu,
paginaciju, metapodatke, sitemap i stanja greške. Jaspr može prikazati generičko
upozorenje o odsutnom `.client.dart` fajlu; ova aplikacija namerno nema klijentski
JavaScript.
