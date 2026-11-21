# Hedrion API

Relic **1.2.0** server u `apps/server` je konačni autoritet za naloge, vlasništvo, revizije, objavljivanje, kvote i poslove. Servisni i PostgreSQL sloj je u `services/api`. Oba Flutter klijenta koriste isti `/api/v1` HTTP paket za Dart VM i browser.

## Pokretanje

Iz čistog klona kopirati `.env.example` u `.env`, pa iz korena pokrenuti `docker compose up --build -d`. Compose pokreće bazu, API i privatni CPU fake worker; API automatski primenjuje migraciju i seed. API je `http://localhost:8080`, a `GET /health` vraća `status`, `service`, `framework:"Relic"` i `frameworkVersion:"1.2.0"`. Demo nalozi su u [README-u](../README.md).

Za host Dart proces izvesti promenljive u okruženje i iz `apps/server` pokrenuti `dart run bin/server.dart`. `DATABASE_URL` mora pokazivati na host port baze, a host fake worker koristi `http://127.0.0.1:8091`; Compose server koristi interna imena `postgres` i `worker`. Relativne host putanje za migraciju i seed računaju se od serverskog app direktorijuma. Pojedinosti su u [isporuci](deployment.md).

Browser studio koristi port 8082, backoffice 8083 i API `http://localhost:8080`. Android emulator koristi `http://10.0.2.2:8080`. Flutter bira API preko `HEDRION_MODE=api` i `HEDRION_API_URL`, bez izmene koda. Browser UI i API treba da koriste isto lokalno ime hosta zbog SameSite cookie-ja.

## Zajednički ugovor i mapiranje

`packages/hedrion_contract` je čist Dart paket bez zavisnosti od domena, Flutter-a ili `dart:io`. Koriste ga server i klijenti. JSON kodiranje i dekodiranje pripada DTO klasama:

| Oblast | DTO tipovi |
|---|---|
| Prijava | `LoginRequestDto`, `RegisterRequestDto`, `RefreshRequestDto`, `IdentityDto`, `SessionDto` |
| Modeli | `AssetDto`, `AssetDraftDto`, `AssetUpdateDto`, `AssetResponseDto`, `AssetPageDto`, `PublicAssetDto` |
| Komande i poslovi | `RevisionRequestDto`, `AssetTransitionDto`, `GenerationRequestDto`, `GenerationJobDto`, `GenerationResponseDto`, `PublicationRequestDto`, `ModerationRequestDto` |
| Prijave | `PublicationSnapshotDto`, `PublicationSubmissionDto`, `ModerationAuditDto` |
| Stranice i greške | `PageRequestDto`, `ApiErrorDto` |

`packages/hedrion_mapping` je jedino mesto za prevod DTO ↔ domen: `assetToDto/assetFromDto`, `draftToDto/draftFromDto`, `actorToDto/actorFromDto`, `jobToDto/jobFromDto`, `publicationToDto/publicationFromDto`, `errorToDto/errorFromDto`. I server i HTTP adapter koriste iste funkcije. DTO-i ne proveravaju poslovnu dozvoljenost; domen proverava pravila, a server ih primenjuje nad svežim stanjem iz baze.

Na mreži su ID-jevi i stanja stringovi, revizije celi brojevi, datumi ISO 8601 UTC, a cursor neproziran string. Tema nema novčani podatak u korisničkom API-ju. Modal billing ostaje zaseban serverski/administrativni dokaz, ne Flutter polje.

## Autentikacija i sesije

Sve sledeće putanje imaju prefiks `/api/v1`.

| Metod i putanja | Telo / odgovor |
|---|---|
| `POST /auth/register` | `{email,password,displayName}` → sesija kreatora |
| `POST /auth/login` | `{email,password}` → sesija postojeće uloge |
| `POST /auth/refresh` | native `{refreshToken}`, browser scoped cookie → rotirana sesija |
| `POST /auth/logout` | native refresh token ili browser scoped cookie; opoziv i brisanje lokalne prijave |
| `GET /me` | trenutni serverom potvrđeni identitet |

Native sesijski odgovor je `{token,refreshToken,expiresAt,refreshExpiresAt,user:{id,email,displayName,role}}`. Privatni zahtevi šalju `Authorization: Bearer <token>`. Server pri svakom pozivu proverava hash tokena, istek, opoziv i korisnika; uloga i vlasnik ne dolaze iz klijentskih polja.

Lozinka ima 12–256 znakova i čuva se kao PBKDF2-HMAC-SHA256 sa 600.000 iteracija i nasumičnom solju. Sesijski tokeni su kriptografski nasumični; baza čuva njihove SHA-256 otiske. `SESSION_ACCESS_TTL_SECONDS` i `SESSION_REFRESH_TTL_SECONDS` određuju trajanje na serveru. Razvojni Compose primer postavlja 900 sekundi pristupnog i 30 dana refresh tokena. Refresh zadržava apsolutni rok početne prijave; rotacija ga ne produžava, a access rok ne prelazi taj deadline.

Browser dodaje `browserSession:true` i `browserSessionScope:"studio"` ili `"backoffice"` u auth telo. Refresh token tada nije u JSON-u nego u `HttpOnly; SameSite=Strict` cookie-ju na `/api/v1/auth`. `hedrion_refresh_studio` i `hedrion_refresh_backoffice` su odvojeni, pa različite uloge mogu istovremeno koristiti isti browser. HTTP transport šalje credentials. Cookie podrazumevano koristi Secure; lokalni Compose postavlja `SECURE_COOKIES=false` radi HTTP-a.

Browser auth proverava tačno dozvoljeni `Origin`. CORS koristi eksplicitan `CORS_ORIGINS` spisak bez wildcard-a i dozvoljava credentials. Logout može opozvati sesiju pomoću refresh credential-a i kada je access token istekao; briše samo izabrani cookie opseg.

Native klijent čuva sesiju iza `SessionStorage` porta, preko `SecureSessionStorage` adaptera. Lozinka se ne čuva. Obnova prijave koristi server; nakon isteka refresh prijave skladište se briše, korisnik vidi poruku i vraća se na prijavu. Detalji platformi su u [isporuci](deployment.md).

## Greške i stara aplikacija

`ApiErrorDto` prenosi `code`, `details` i opcioni `requestId`. Server može uključiti bezbednu tekstualnu poruku radi dijagnostike, ali korisničku poruku pravi klijent kroz zajedničko mapiranje i domenski `errorMessage`.

Primer odbijanja naziva nakon serverskog smanjenja granice na 40:

```json
{
  "code": "invalidTitle",
  "details": {"minLength": 3, "maxLength": 40, "actualLength": 45},
  "requestId": "opaque-id"
}
```

Već izgrađen klijent koristi primljenih 40 u poruci, iako lokalno još dozvoljava 60. Poznat kod zato prikazuje istu poruku kao lokalna validacija sa istim podacima. Nepoznat kod daje lokalnu poruku `serverRuleRejected`, bez exception-a ili tehničkog serverskog teksta. HTTP 5xx se mapira u `unavailable`; `invalidRefresh`/`sessionExpired` u `sessionExpired`. `activeJobLimit` ima sopstveno objašnjenje i ne predstavlja popunjenu dnevnu kvotu.

HTTP statusi: 400 JSON, 401 sesija, 403 uloga, 404 nepristupačan/nepostojeći privatni resurs, 409 revizija/stanje, 411 veličina upload-a nije poznata, 413 prevelik zahtev, 416 opseg, 422 domensko pravilo i 429 kvota/frekvencija. Odgovori i logovi ne prikazuju interne exception poruke, lozinke ili tokene.

Odbijena Bloc mutacija zadržava objašnjenje i ponovo učitava podatke. Zakasneli moderator tako vidi novu odluku drugog moderatora, umesto zastarele akcije.

## Modeli i revizije

| Metod i putanja | Ugovor |
|---|---|
| `GET /assets?cursor=<id>&limit=100` | `{assets:[AssetDto],nextCursor:string|null}`, samo sopstveni modeli |
| `POST /assets` | `{title,description?,category?,tags?,projectId?}` → model |
| `GET /assets/:id` | jedan model, tuđi privatni ID daje 404 |
| `PATCH /assets/:id` | `{baseRevision,title?,description?,favorite?,category?,tags?,projectId?}` |
| `DELETE /assets/:id` | `{baseRevision}` → `{deleted:true}`, aktivni posao sprečava brisanje |
| `POST /assets/:id/transition` | `{target,baseRevision,reason?}`, zajednička pravila prelaza |
| `GET /projects` | `{projects:[{id,ownerId,name,revision}]}` |
| `POST /projects` | `{name}` → projekat |
| `PATCH /projects/:id` | `{name,baseRevision}` → nova revizija |

`AssetDto` opisuje `id,ownerId,title,description,category,projectId,tags,favorite,lifecycle,createdAt,updatedAt,revision,outputFileId,previewFileId,rejectionReason,allowDownload,license`. Osam stanja su `draft,queued,generating,ready,pendingReview,published,failed,rejected`.

Vlasništvo potiče iz sesije. Klijentski `ownerId`, `role`, proizvoljna revizija ili lifecycle nisu dozvola za upis. Domain `validateAssetOwnership` štiti privatne akcije; moderator privatnim fajlovima pristupa samo kroz dozvoljeni prijavljeni snimak.

Privatna lista koristi stabilan redosled po ID-u. `limit` je 1–100; `nextCursor` je poslednji ID kada postoji nastavak, inače `null`. Adapter učitava sve stranice i ne potvrđuje delimičnu listu pri neispravnom/ponovljenom cursor-u.

Za mutacije je obavezan `baseRevision`; `If-Match: "3"` može ga zameniti na podržanim revision rutama. Konflikt ne prepisuje novije stanje. PATCH podržava `Idempotency-Key`: isti ključ i sadržaj vraćaju originalni rezultat, a promenjen sadržaj ili drugi model daju 409.

## Fajlovi

`POST /assets/:id/upload-url` sa `{byteLength,mime}` vraća API putanju i zaglavlja. To ne zaobilazi autorizaciju ni kvotu: konačna atomska rezervacija je na `PUT /assets/:id/source`.

```http
PUT /api/v1/assets/:id/source
Authorization: Bearer <token>
Content-Type: image/png
X-File-Length: 12345
Content-Length: 12345

<tačno 12345 bajtova slike>
```

Odgovor je `{asset,file:{id,byteLength,mime}}`. PNG/JPEG imaju najviše 10.000.000 bajtova, 8192 piksela po dimenziji i 16 miliona piksela ukupno; server proverava potpis i dekodira stvarne piksele. Chunked/nepoznata veličina daje 411 pre čitanja tela, a neslaganje dve dužine 422. Prekid zadržava potrošnju primljenih bajtova i oslobađa nepotrošeni ostatak.

`GET /assets/:id/download-url` vraća `{url,byteLength,mime}`; `GET /files/:id` vraća autorizovan, meteren sadržaj. Preview koristi isti gateway. Podržan je jedan `Range: bytes=start-end` sa 206/416. GLB preglednik dobija autentifikovane bajtove, bez tokena u URL-u renderera i bez preuzimanja spoljašnjih resursa iz modela.

## Generisanje i zajednička kvota

`GET /capabilities` vraća `provider,imageTo3d,textTo3d,demo,defaultModel,generationModels` i za Modal `referenceImageProvider`. Klijent prikazuje samo dostupne opcije.

`POST /assets/:id/generations` zahteva `Idempotency-Key` od 8–200 znakova i `GenerationRequestDto`:

```json
{
  "baseRevision": 1,
  "inputType": "text_to_3d",
  "sourcePrompt": "Mala mesingana mehanička sova",
  "modelProvider": "spar3d",
  "seed": 42
}
```

Za `image_to_3d` slika mora prethodno biti sačuvana. Seed je ceo broj 0–4.294.967.295. Modal modeli su `spar3d`, `hunyuan3d_21`, `trellis2`; tekst prvo prolazi Qwen-Image 2.1 Turbo. U lokalnom `fake` režimu izabrani provider je `fake`, rezultat je jasno označen demonstracionim. Nepodržan tip/model se odbija pre rezervacije i GPU poziva. Odgovor 202 je `{job,asset}` sa stanjem queued.

| Putanja | Namena |
|---|---|
| `GET /generations/:jobId` | vlasnikov posao i ishod |
| `GET /assets/:assetId/generations` | `{jobs:[...]}` istorija, metadata i metrics |
| `POST /generations/:jobId/cancel` | otkazuje još nepokrenuti posao |
| `POST /generations/:jobId/retry` | nova eksplicitna generacija neuspešnog posla, nova revizija i ključ |

PostgreSQL transakcija i zajednički advisory lock serijalizuju proveru i upis, uključujući više API procesa. Prvo se proverava idempotentni replay, zatim sveža revizija, domen, aktivni posao vlasnika i globalni broj prijema. Granica je **20 prihvaćenih generacija po UTC danu**, uključujući kasniji neuspeh/otkazivanje. Brisanje modela ne briše prijemnu evidenciju. Od dva zahteva za poslednje mesto prolazi samo jedan; drugi nema novi posao niti promenu modela.

Scheduler trajno čuva red. Najviše dva globalna `running` posla i jedan `queued/running` po korisniku. Lease traje pet minuta i obnavlja se na 30 sekundi. Izgubljen lease daje failed, bez automatskog kupovanja nove generacije. Zatvaranje klijenta ne prekida posao. Istekli lease ne može da potvrdi rezultat niti da se oživi heartbeat-om.

Serverski `worker_client.dart` je port ka privatnom provider-u: Bearer tajna i HMAC nad `timestamp.nonce.rawBody`. Lokalni worker vraća rezultat, Modal gateway odmah vraća identifikator i koristi potpisano proveravanje statusa. Izvorna plaćena predaja ne ponavlja se posle nejasne mrežne greške. Server proverava GLB/PNG, rezerviše prostor i trajno čuva fajlove pre ready/succeeded.

`POST /internal/v1/generations/:jobId/callback` koristi isti potpis, petominutni prozor i trajnu nonce zaštitu. Pogrešan potpis, ponovljen nonce, tuđi ili završen posao se odbija. Modeli, L40S ograničenje TRELLIS-a i benchmark dokazi opisani su u [Modal dokumentaciji](modal-generation.md).

## Objavljivanje i moderacija

| Putanja | Ugovor |
|---|---|
| `POST /assets/:id/submissions` | ključ + `{baseRevision,confirmRights:true,license:"ccBy",allowDownload:true}` → `{asset,submission}` |
| `GET /my/submissions?cursor=<assetId>&limit=100` | sopstvene najnovije prijave po modelu |
| `POST /submissions/:id/withdraw` | vlasnik povlači prijavu ili uklanja objavljivanje |
| `GET /moderation/submissions?cursor=<assetId>&limit=100` | moderatorska lista, snimci, audit i statistika |
| `GET /moderation/submissions/:id` | direktni moderatorski detalj |
| `POST /moderation/submissions/:id/approve` | ključ + `{baseRevision:<revizija prijave>}` |
| `POST /moderation/submissions/:id/reject` | isto + `{reason:"Dopunite opis"}` |

Odobravanje i odbijanje su dve zasebne moderatorske write akcije. Zajednički `validateModerationAccess` se izvršava pre odluke, pa kreator dobija forbidden i pri direktnom HTTP pozivu. Backoffice login koristi `validateBackofficeAccess` sa namenskim objašnjenjem pogrešne uloge.

Odbijanje zahteva razlog od 3–1000 znakova. Dve konkurentne odluke daju jednu izmenu i jednu 409 grešku. Klijent koji zakasni prikazuje razlog i ponovo učitava podatke. Privatni GLB ostaje nakon odbijanja.

Prijava sadrži `id,assetId,status,revision,slug,submittedAt,snapshot,submitterName`, opciono podatke odluke i `audit:[{actorName,action,createdAt,reason}]`. Snima naziv, opis, kategoriju, oznake, GLB/preview verziju i licencu. Kasnija privatna izmena ne menja javni snimak. Revizija modela i prijave su odvojene.

Liste vraćaju `{assets,submissions,nextCursor,stats}`, stabilno po assetId, do 100 po stranici. Statistika se računa nad celim dozvoljenim skupom: `reviewedToday`, `approvalRate` u opsegu 0–1 i `activeJobs`. Vlasnikova lista ograničava i statistiku na njega.

Moderator može preuzeti samo GLB/preview iz prijavljenog snimka, uključujući istorijski odobrene/odbijene prijave. Privatna izvorna slika ostaje skrivena. Brisanje modela ukida pristup svim njegovim fajlovima.

## Javni i offline ugovori

`GET /public/assets?q=&category=&cursor=&limit=24` vraća `{assets:[PublicAssetDto]}`; `GET /public/assets/:slug` javni detalj, a `GET /public/categories` kategorije. Javni model sadrži `slug,title,description,category,tags,license,allowDownload,author,format,lifecycle:"published",status:"approved",previewUrl,downloadUrl?`. Nema imejl, privatne ID-jeve ili storage putanju. Jaspr čita samo ove anonimne rute.

`POST /sync/operations` prima `{operations:[{clientOperationId,entityId,baseRevision,payload,idempotencyKey?}]}`. Operacije su nezavisne i idempotentne. Rezultat je `{results:[{clientOperationId,id,status:"applied",asset}]}` ili pojedinačni conflict/failed sa kodom i podacima greške. Konflikt ne briše lokalnu izmenu niti noviju serversku reviziju.

## Skladište i oporavak

Dnevni prenos je **1.000.000.000**, a trajno skladište **10.000.000.000** decimalnih bajtova za sve korisnike. Rezervacije i finalizacije su transakcione. Prenos preko UTC ponoći pribavlja kapacitet novog dana pre nastavka. API računa primljeni sadržaj i sadržaj predat HTTP transportu; ne može dokazati broj bajtova fizički primljenih na udaljenom uređaju.

Startup usklađuje evidenciju sa diskom, uključujući orphan fajlove. Stare nedovršene rezervacije konzervativno se knjiže u punoj veličini. Kandidat pri neuspešnoj SQL finalizaciji ostaje pod globalnim lock-om dok se ne potvrdi fizičko brisanje; neuspešno brisanje knjiži zadržane bajtove. Savepoint čuva originalnu poslovnu grešku i sprečava oslobađanje prostora koji fajl još zauzima.

Brisanje modela prvo potvrđuje tombstone i uklanja javnu prijavu, zatim čisti fajlove. `cleanupPending:true` označava preostalo čišćenje; model ostaje nedostupan, bajtovi uračunati, a restart/replay nastavlja posao. Prijemi i audit se zadržavaju.

## Provere

Iz korena, uz postavljen `TEST_DATABASE_URL`:

```sh
dart test packages/hedrion_contract/test packages/hedrion_mapping/test services/api/test packages/hedrion_api_client/test
```

PostgreSQL testovi koriste izolovanu privremenu šemu. Bez promenljive se preskaču, što nije potvrda serverskog toka. Testovi proveravaju vlasništvo/uloge, greške sa podacima pravila, revizije, sesije, konkurentnu kvotu/moderaciju, idempotentnost, meterenje, fajlove, potpise, validaciju slika i lozinki. Izvršene rezultate i stvarne platformske dokaze vodi [izveštaj o proveri](verification.md).

Zvanični izvori za korišćene biblioteke: [Relic 1.2.0](https://pub.dev/packages/relic/versions/1.2.0), [postgres](https://pub.dev/packages/postgres), [cryptography](https://pub.dev/packages/cryptography), [image](https://pub.dev/packages/image). Tačne rešene zavisnosti su u korenom `pubspec.lock`.
