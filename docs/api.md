# Hedrion API

Dart server je konačni autoritet za naloge, vlasništvo, revizije, javno objavljivanje, kvote i poslove. Android i veb studio koriste isti `/api/v1` ugovor i PostgreSQL. KT1 memorijski režim Flutter klijenata radi nezavisno od ovog servera.

## Lokalno pokretanje

Komande se izvršavaju iz korena repozitorijuma, zatim iz `services/api`. PowerShell primer:

```powershell
$env:POSTGRES_PASSWORD = 'izaberite-lokalnu-lozinku'
docker compose -f infrastructure/docker-compose.yml up -d
$env:DATABASE_URL = 'postgres://hedrion:izaberite-lokalnu-lozinku@127.0.0.1:55432/hedrion?sslmode=disable'
$env:WORKER_SHARED_SECRET = 'izaberite-nasumicnu-tajnu-od-najmanje-32-znaka'
$env:WORKER_URL = 'http://127.0.0.1:8091'
$env:GENERATION_PROVIDER = 'fake'
$env:SECURE_COOKIES = 'false' # Samo za lokalni HTTP; podrazumevano true.
$env:CORS_ORIGINS = 'http://localhost:8082,http://localhost:8083'
cd services/api
dart run bin/migrate.dart
dart run bin/server.dart
```

`DATABASE_URL` u produkciji koristi TLS. API se lokalno vezuje za `127.0.0.1:8080`; `API_BIND=0.0.0.0` koristite samo kada je potreban pristup emulatora/drugog uređaja ili kada je API iza HTTPS reverse proxy-ja. Android emulator obično koristi `http://10.0.2.2:8080`. `OBJECT_STORAGE_PATH` je direktorijum posvećen isključivo Hedrion fajlovima, podrazumevano `../../.data/objects` kada je radni direktorijum `services/api`.

Pokrenite Python fake worker zasebno prema `docs/ai-provider.md`. Nedostupan worker daje neuspešan posao uz očuvanu dnevnu prijemnu evidenciju; API ne izmišlja uspešan AI rezultat.

Browser studio pokrenite iz `apps/mobile` sa
`flutter run -d chrome --web-port 8082 --dart-define=HEDRION_MODE=api --dart-define=HEDRION_API_URL=http://localhost:8080`,
a backoffice iz `apps/backoffice` sa istim define-ima i `--web-port 8083`.
Nasumičan browser port nije deo podrazumevanog CORS spiska. Za lokalni browser
koristite `localhost` i u UI i u API adresi radi HttpOnly/SameSite sesije.

Moderator se ne dobija registracijom i nema ugrađenu lozinku:

```powershell
$env:MODERATOR_EMAIL = 'moderator@example.test'
$env:MODERATOR_PASSWORD = 'izaberite-lozinku-od-najmanje-12-znakova'
$env:MODERATOR_NAME = 'Moderator'
dart run bin/create_moderator.dart
```

Komanda odbija već postojeći nalog. Promocija postojećeg korisnika traži zasebnu pregledanu administrativnu izmenu.

## Autentikacija i greške

Registracija `POST /auth/register` prima `{email,password,displayName}`. Prijava `POST /auth/login` prima `{email,password}`. Odgovor je `{token,refreshToken,expiresAt,user:{id,email,displayName,role}}`. Lozinka mora imati 12–256 znakova i čuva se kao PBKDF2-HMAC-SHA256 sa 600.000 iteracija i nasumičnom solju. Sesijski tokeni su kriptografski nasumični, a u bazi se čuvaju samo SHA-256 otisci. Pristupni token traje jedan sat, refresh 30 dana.

Privatni zahtevi šalju `Authorization: Bearer <token>`. `GET /me` vraća trenutni nalog; `POST /auth/refresh` sa `{refreshToken}` rotira nativnu sesiju i opoziva staru; `POST /auth/logout` opoziva tekuću sesiju. Browser dodaje `browserSession:true` na register/login/refresh. Tada refresh token ostaje u `HttpOnly; SameSite=Strict` kolačiću ograničenom na `/api/v1/auth`, a JSON vraća samo pristupni token i korisnika. Browser HTTP klijent koristi credentials, a refresh čita i rotira HttpOnly kolačić. Za browser sesiju obavezno je tačno dozvoljeno `Origin` zaglavlje; nepoznato ili nedostajuće poreklo se odbija. `Secure` je podrazumevano uključen; `SECURE_COOKIES=false` je samo za lokalni HTTP razvoj. Logout briše refresh kolačić. Dozvoljena porekla su tačan spisak `CORS_ORIGINS`, sa credentialed CORS i bez wildcard-a. Za isporuku je obavezan HTTPS i zaštita veb aplikacije od XSS-a.

Browser auth tela takođe nose `browserSessionScope:"studio"` (podrazumevano) ili `"backoffice"`. Svaka aplikacija koristi zaseban kolačić `hedrion_refresh_studio` odnosno `hedrion_refresh_backoffice`, pa kreator i moderator mogu istovremeno biti prijavljeni u istom pregledaču. Refresh čita samo kolačić iz izabranog opsega; logout briše samo njegov opseg. Nepoznata vrednost opsega daje 422. Uloga se i dalje određuje isključivo iz serverske sesije, nikada iz imena opsega.

Greška je `{code,message,details?,requestId}`. HTTP statusi: 400 neispravan JSON, 401 sesija, 403 uloga, 404 nepristupačan/nepostojeći privatni resurs, 409 revizija/stanje, 411 nedostajuća unapred poznata veličina upload-a, 413 veličina, 416 opseg, 422 domensko pravilo ili neusaglašena veličina upload-a, 429 kvota ili frekvencija, 500 neočekivana serverska greška. Odgovori ne vraćaju interne exception poruke, lozinke ili tokene u logovima. Ograničenje frekvencije po procesu/IP-u štiti auth, generisanje i javne rute; za više produkcionih replika dodajte zajednički reverse-proxy limiter.

## Modeli i revizije

Sve sledeće putanje imaju prefiks `/api/v1`.

| Metod i putanja | Ugovor |
|---|---|
| `GET /assets?cursor=<id>&limit=100` | `{assets:[Asset],nextCursor:string\|null}`, samo vlasnik; stabilan redosled po ID-u, do 100 zapisa po stranici |
| `POST /assets` | `{title,description?,category?,tags?,projectId?}` → privatni `Asset` |
| `GET /assets/:id` | jedan `Asset`; tuđi privatni ID vraća 404 |
| `PATCH /assets/:id` | `{baseRevision,title?,description?,favorite?,category?,tags?,projectId?}` → ažurirani model |
| `DELETE /assets/:id` | `{baseRevision}` → `{deleted:true}`; odbija aktivne poslove |
| `POST /assets/:id/transition` | `{target:"ready",baseRevision}`; vlasnik vraća odbijen/povučen/objavljen model u privatnu pripremu |
| `GET /projects` | `{projects:[{id,ownerId,name,revision}]}` |
| `POST /projects` | `{name}` → projekat |
| `PATCH /projects/:id` | `{name,baseRevision}` → nova revizija |

`Asset` koristi zajedničku serijalizaciju `packages/domain`: `id,ownerId,title,description,category,projectId,tags,favorite,lifecycle,createdAt,updatedAt,revision,outputFileId,previewFileId,rejectionReason,allowDownload,license`. Datumi su ISO 8601 UTC. Životni ciklus ima osam stanja iz specifikacije. Vlasništvo potiče iz sesije; klijentski `ownerId`, `role`, `revision` i proizvoljan `lifecycle` nisu prihvaćene izmene. Forma i server koriste zajednički `validateDraft`, `validateTitle` i `validateTransition`.

`nextCursor` je identifikator poslednjeg modela trenutne stranice kada postoji
sledeća, inače `null`. Sledeći zahtev šalje tu vrednost kao `cursor`; `limit` je
1–100, podrazumevano 100. Kompletna biblioteka zahteva čitanje svih stranica,
ne samo prvog odgovora. Cursor ne menja proveru vlasništva.

Za izmene je obavezan `baseRevision`; HTTP `If-Match: "3"` je podržana zamena u PATCH/DELETE/transition/moderation telu. Konflikt nikada tiho ne prepisuje noviju izmenu. PATCH prihvata `Idempotency-Key`; isti ključ i isti sadržaj vraćaju originalni odgovor čak i nakon kasnijih izmena. Ključ ponovljen sa drugim sadržajem ili drugim modelom daje 409.

## Slike, GLB i zajednički prenos

`POST /assets/:id/upload-url` sa `{byteLength,mime}` vraća kontrolisanu API putanju i zaglavlja za sledeći poziv. To je instrukcija za upload, bez zaobilaženja kvote: konačna atomska rezervacija obavlja se neposredno pre prihvatanja tela na `PUT /assets/:id/source`. Vraćena putanja ne daje javno pravo pristupa.

```http
PUT /api/v1/assets/:id/source
Authorization: Bearer <token>
Content-Type: image/png
X-File-Length: 12345
Content-Length: 12345

<tačno 12345 bajtova slike>
```

Odgovor je `{asset,file:{id,byteLength,mime}}`. PNG/JPEG ulazi imaju najviše 10.000.000 bajtova, najviše 8192 piksela po dimenziji i 16 miliona piksela ukupno; validacija zaista dekodira sliku, uz proveru potpisa i dimenzija pre dekodiranja. Nedovršen ili prevelik prenos se odbija, uz naplatu već primljenog sadržaja i oslobađanje ostatka rezervacije. Izmena ulaza dostupna je samo za nacrt ili neuspešan model.

`Content-Length` mora biti unapred poznat i jednak `X-File-Length`. Chunked upload
ili izostala veličina daje `411 lengthRequired`, a nepodudaranje
`422 lengthMismatch`, pre čitanja tela i pre rezervacije kvote. Time se mala
deklarisana rezervacija ne može koristiti za neograničen ulazni tok. Standardni
HTTP/browser klijent postavlja `Content-Length` za poznate bajtove tela.

`GET /assets/:id/download-url` vraća `{url,byteLength,mime}` za `GET /files/:fileId`. Zahtev ponovo proverava sesiju/vlasništvo i atomski rezerviše prenos. Podržani su pojedinačni HTTP `Range: bytes=start-end` i suffix opsezi, sa statusom 206 i `Content-Range`. Svaki stvarni ponovljeni download troši kvotu ponovo. Preview fajlovi koriste istu metered putanju. Moderator može dobiti fajl samo modela koji ima aktivnu prijavu za pregled.

Ne postoje direktni javni storage linkovi. Javni pregled/preuzimanje ide preko `/public/assets/:slug/files/preview` i `/public/assets/:slug/files/model`, uz istu globalnu kvotu. Download modela zahteva autorovo `allowDownload` i licencu `ccBy` ili `cc0`.

## Generisanje i trajni poslovi

`POST /assets/:id/generations` zahteva `Idempotency-Key` (8–200 znakova) i `{baseRevision,inputType:"image_to_3d",sourcePrompt?}`. Ulazna slika prethodno mora biti sačuvana. Fake worker takođe podržava označeni demonstracioni `text_to_3d`; produkcioni tekstualni tok ne smatra se aktivnim bez zasebnog text-to-image providera. Odgovor 202 je `{job,asset}`, uz stanje `queued`.

`GET /generations/:jobId` vraća vlasnikov posao i ishod. `POST /generations/:jobId/cancel` otkazuje samo još nepokrenut posao. `POST /generations/:jobId/retry` sa `{baseRevision}` i novim `Idempotency-Key` pravi novi posao samo posle neuspeha. Ne menja se neuspešna istorijska evidencija.

`GET /assets/:assetId/generations` vraća vlasnikovu istoriju `{jobs:[...]}` od najnovijeg prijema, sa `status,failureCode,failureMessage,startedAt,finishedAt`, metadata i metrics kada postoje. Tuđi model daje 404. `GET /capabilities` oglašava `provider,imageTo3d,textTo3d,demo`; `GENERATION_PROVIDER=fake` eksplicitno dopušta demonstracioni tekstualni unos. Za druge providere server odbija `text_to_3d` pre prijema/upisa, dok zaseban potvrđen reference-image provider nije integrisan. Podrazumevani privatni worker je `http://127.0.0.1:8091`.

PostgreSQL transakcija i zajednički advisory lock serijalizuju proveru i upis, uključujući više API procesa. Sve mutacije koriste isti lock radi jasne demonstrabilne ispravnosti pri malom planiranom opterećenju; taj izbor smanjuje paralelizam. Prvo se proverava idempotentni replay, zatim sveža revizija, domen, aktivni posao vlasnika i globalni broj primljenih zahteva. Granica je **20 prihvaćenih generacija po UTC danu**, uključujući kasniji neuspeh/otkazivanje. Odbijeni zahtev nema posao ni promenu modela. Brisanje modela ne briše njegovu prijemnu evidenciju. Novi UTC dan dozvoljava novi eksplicitni zahtev.

Scheduler trajno čuva red i atomski preuzima najstariji posao. Najviše dva važeća globalna `running` posla, a najviše jedan `queued/running` po korisniku. Lease traje pet minuta i obnavlja se na 30 sekundi; izgubljen lease postaje `failed`, bez automatskog ponavljanja plaćene obrade. Zatvaranje aplikacije ne prekida posao.

Heartbeat ne može ponovo da oživi već istekao lease, a rezultat sa isteklim lease-om odbija se pre upisa fajlova. Ako baza privremeno nije dostupna baš pri beleženju neuspeha worker-a, API ostaje aktivan: postojeći trajni posao čeka oporavak baze i redovnu lease proveru umesto neobrađene asinhrone greške koja bi zaustavila proces.

Dart API poziva privatni Python worker sa Bearer tajnom i HMAC potpisom nad `timestamp.nonce.rawBody`. Worker vraća izmerene bajtove, metadata i metrics. API proverava GLB header/dužinu/chunkove/JSON i PNG, rezerviše skladište, čuva fajlove, pa tek onda postavlja `ready` i `succeeded`. Provider se u rezultatu beleži stvarnim imenom, npr. `fake`.

`POST /internal/v1/generations/:jobId/callback` podržava isti Bearer/HMAC ugovor, vremenski prozor od pet minuta i trajnu zaštitu od ponovljenog nonce-a. Nevalidan potpis, tuđi jobId, duplikat ili završen posao se odbijaju. Sinhroni lokalni worker rezultat trenutno stiže direktnim serverskim pozivom, a callback je zasebna pripremljena mogućnost.

## Objavljivanje i moderacija

| Putanja | Ugovor |
|---|---|
| `POST /assets/:id/submissions` | `Idempotency-Key`, `{baseRevision,confirmRights:true,license:"ccBy",allowDownload:true}` → `{asset,submission}` |
| `GET /my/submissions?cursor=<assetId>&limit=100` | vlasnikove najnovije prijave po modelu `{assets,submissions,nextCursor,stats}` |
| `POST /submissions/:id/withdraw` | vlasnik povlači pending prijavu ili uklanja odobreno objavljivanje |
| `GET /moderation/submissions?cursor=<assetId>&limit=100` | moderator; najnovija prijava po modelu, snapshot za inspector i `{assets,submissions,nextCursor,stats}` |
| `GET /moderation/submissions/:id` | moderator; direktan detalj prijave sa autorom, vremenom odluke i audit istorijom |
| `POST /moderation/submissions/:id/approve` | `Idempotency-Key`, `{baseRevision:<revizija prijave>}` |
| `POST /moderation/submissions/:id/reject` | isto, plus `{reason:"Dopunite opis"}` |

Odbijanje zahteva razlog od 3–1000 znakova. Dve različite konkurentne odluke daju tačno jednu promenu i jednu 409 grešku. Audit beleži moderatora, radnju, razlog i vreme. Privatni uspešni GLB ostaje sačuvan nakon odbijanja.

Obe liste prijava koriste stabilan redosled po `assetId`, do 100 modela po
stranici. `nextCursor` vraća poslednji `assetId` kada postoji nastavak, inače
`null`; sve stranice treba pročitati za kompletnu moderatorsku evidenciju.
`stats` se računa nad celim dozvoljenim skupom, nezavisno od trenutne stranice:
`reviewedToday` broji odluke u tekućem UTC danu, `approvalRate` je odnos
odobrenih i svih obrađenih prijava u opsegu 0–1 (0 kada nema odluka), a
`activeJobs` broji trenutno `running` poslove. Vlasnikov `/my/submissions`
odgovor ograničava podatke i statistiku na tog vlasnika.

Objekat prijave sadrži `id,assetId,status,revision,slug,submittedAt,snapshot`,
`submitterName`, opciono `reviewedAt`, `reviewedBy` i `rejectionReason`, te
`audit:[{actorName,action,createdAt,reason}]`. Direktan detalj dobija se prema ID-u
prijave i ne zavisi od toga da li je njen model na prvoj stranici liste.

Prijava snima naziv, opis, kategoriju, oznake, konkretnu GLB/preview verziju i licencu. Kasnija privatna izmena ne menja prijavljeni/odobreni sadržaj. Inspector koristi snapshot prijave; revizija modela i revizija prijave jesu odvojeni brojevi. Samo moderator/admin može odobriti prijavu.

Moderator može preuzeti samo GLB/preview fajlove navedene u sačuvanom snimku, uključujući već odobrene ili odbijene prijave radi istorijskog pregleda. Privatna izvorna slika i fajlovi koji nikada nisu podneti na proveru ostaju nedostupni. Brisanje modela i dalje ukida pristup svim njegovim fajlovima.

## Javni i offline ugovori

`GET /public/assets?q=&category=&cursor=&limit=24` daje `{assets:[PublicAsset]}`. `GET /public/assets/:slug` vraća direktan `PublicAsset`; `GET /public/categories` vraća `{categories:[string]}`. Javni model ima `slug,title,description,category,tags,license,allowDownload,author,format,lifecycle:"published",status:"approved",previewUrl,downloadUrl?`. Ne sadrži imejl, ID vlasnika, privatni ID fajla ili storage putanju. Jaspr SSR koristi ove anonimne rute; odobreni snapshot je jedini izvor javnog sadržaja.

`POST /sync/operations` prima `{operations:[{clientOperationId,entityId,baseRevision,payload:{title,description,favorite},idempotencyKey?}]}`. Svaka operacija se obrađuje nezavisno i idempotentno; kada ključ nije dat koristi se `clientOperationId`. Odgovor `{results:[{clientOperationId,id,status:"applied",asset}]}` ili per-operation `status:"conflict"|"failed",code,message`. Klijent mora proveriti svaki status; konflikt se ne smatra uspehom i ne briše noviju serversku reviziju.

## Evidencija kapaciteta i oporavak

Globalne granice koriste decimalne bajtove: dnevni prenos **1.000.000.000**, trajno skladište **10.000.000.000**. Rezervacije i finalizacije su transakcione. Prenos preko UTC ponoći finalizuje prethodni interval i pribavlja kapacitet novog dana pre nastavka. Normalan prekid čuva broj bajtova već predatih transportu/primljenih sa transporta i oslobađa neiskorišćen ostatak. API nivo ne može dokazati broj bajtova koje je udaljeni uređaj fizički primio nakon mrežnog prekida; konzervativno računa sadržaj predat HTTP transportu.

Pokretanje servera usklađuje skladišnu evidenciju sa stvarnim fajlovima, uključujući osirotele rezultate prekinutog procesa. Takvi fajlovi ostaju uračunati dok se kontrolisano ne uklone. Starije od sat vremena nedovršene transfer rezervacije konzervativno se naplaćuju u punoj veličini, pošto se stvarni poslednji mrežni bajt nakon pada procesa ne može pouzdano rekonstruisati. To može privremeno umanjiti raspoloživu kvotu, ali ne dozvoljava prekoračenje.

Pri neuspešnoj SQL finalizaciji kandidat se briše dok je globalni transakcioni lock još zauzet. Poslovne SQL izmene prvo se poništavaju do savepoint-a, zatim se potvrđuje fizičko uklanjanje kandidata. Ako brisanje ne uspe, stvarni zadržani bajtovi odmah se knjiže kao zauzeti prostor u spoljnoj transakciji, pa se originalna greška vraća pozivaocu. Ako ni merenje fajla ne uspe, zadržava se puna rezervisana veličina. Drugi zahtev zato ne može zauzeti prostor između rollback-a i neuspešnog cleanup-a. Osiroteli fajl može ostati bez poslovnog `stored_files` reda; restart ga ponovo broji disk pregledom bez duplog knjiženja. Prostor se oslobađa tek nakon potvrđenog fizičkog uklanjanja i reconciliation-a.

Fajlovi nisu u PostgreSQL-u. `DELETE /assets/:id` prvo potvrđuje tombstone i uklanjanje javne prijave u transakciji, pa tek potom fizički briše fajlove i pojedinačno oslobađa prostor. Neuspešno čišćenje daje `cleanupPending:true`; model ostaje nedostupan, preostali bajtovi ostaju uračunati, a restart/replay nastavlja čišćenje. Već uklonjen prvi fajl zato ne može da se vrati kao dostupan model kada brisanje drugog fajla ne uspe. Generacioni prijemi i audit se zadržavaju. Za produkcionu isporuku treba dodatno proveriti prekid mreže/procesa tokom pravog cloud GPU poziva: lease kontroliše API scheduler, dok prestanak udaljene GPU obrade zahteva providerov potvrđen prekid.

## Provere

```powershell
cd services/api
dart analyze
dart test test/security_test.dart
$env:TEST_DATABASE_URL = $env:DATABASE_URL
dart test
```

Integracioni testovi kreiraju izolovanu, jedinstveno imenovanu PostgreSQL šemu i uklanjaju je posle testova; ne menjaju glavne aplikacione tabele. Bez `TEST_DATABASE_URL` jasno se preskaču. Testovi proveravaju vlasništvo/uloge, revizije, offline idempotentnost, UTC reset, konkurenciju poslednjeg generacionog mesta, rezervacije prenosa i delimičan prenos, skladišnu granicu, snapshot objavljivanja, konkurentnu moderaciju, dva scheduler mesta, neispravan worker rezultat, CORS, HMAC, dekodiranje slika i proveru lozinki.

Driver i serverski API-ji provereni su prema zvaničnoj dokumentaciji: [postgres](https://pub.dev/packages/postgres), [Shelf](https://pub.dev/packages/shelf), [shelf_router](https://pub.dev/packages/shelf_router), [cryptography](https://pub.dev/packages/cryptography), [image](https://pub.dev/packages/image). Tačne rešene verzije nalaze se u korenom `pubspec.lock`.
