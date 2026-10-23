# Izvršene provere

Ovaj izveštaj beleži stvarno izvršene komande i odvojene spoljašnje uslove. Izvorna oba DOCX dokumenta su pročitana; implementacija prati konačnu specifikaciju uz naknadnu odluku tima da konkretan AI model još nije izabran.

## Automatizovane provere

| Provera | Izvršeni rezultat |
|---|---|
| `dart test packages/domain/test packages/blocs/test packages/hedrion_api_client/test apps/public_web/test` | 43/43 prolazi; završni API-client adapter dodatno 14/14 |
| API testovi sa `TEST_DATABASE_URL` | 34/34 prolazi, uključujući 28 stvarnih PostgreSQL integracionih provera i 6 unit/security provera |
| `flutter test` u `apps/mobile` | 7/7 prolazi |
| `flutter test` u `apps/backoffice` | 3/3 prolazi |
| Python fake worker testovi | 15/15 prolazi; bez GPU-a i obaveznih pip zavisnosti |
| Postojeći eksperimentalni CPU testovi | 9/9 prolazi sa već dostupnim Pillow-om; ne dokazuju stvarnu AI inferenciju |
| Dart format | 61 fajl, završna kontrola bez promena |
| `dart analyze` i ciljana analiza svih aplikacija/paketa | No issues found |

Testovi proveravaju domenske granice, vlasništvo, tipizirane greške, konkurentno poslednje mesto dnevne kvote, idempotentnost, rezervacije prenosa i skladišta, delimične prenose, UTC granicu, moderatorski konflikt, snimke prijava, potpisane callback-e, sesije i izolaciju browser uloga, lease oporavak, trajni outbox i eksplicitni konflikt. Widget testovi obuhvataju telefon širine 390 px, forme, učitavanje/grešku/prazan rezultat, pretragu, licence, rad tastaturom i resize bez gubitka izbora.

Završne regresije dodatno proveravaju više od 100 privatnih modela i prijava, direktan detalj poslednje prijave, audit i moderatorske pokazatelje, pristup samo fajlovima snimka i posle odluke moderatora, odsustvo čitanja neograničenog chunked upload-a, zadržavanje zauzeća posle neuspešnog fizičkog cleanup-a, vrednosnu jednakost popunjenih Bloc stanja, obnovu sačuvane rute posle autentikacije i očuvanje online oznaka bez njihovog tihog odbacivanja u offline režimu.

Jaspr javni sajt namerno renderuje samo HTML bez klijentskog JavaScript-a. Njegovo generičko upozorenje o nedostajućem `.client.dart` skriptu ne predstavlja neuspeh SSR testova.

## Povezani HTTP tok

`dart run tool/smoke.dart .local/reference.png` uspešno je izvršen nad stvarnim lokalnim Dart API-jem, PostgreSQL-om, privatnim Python fake worker-om i Jaspr serverom. Provereno je svih devet koraka: isti nalog u dve sesije, ponovljen zahtev bez novog posla, rezultat trajno sačuvan pre `ready`, GLB i PNG preuzimanje, skrivena prijava pre odobrenja, odobren anonimni HTML, javno metereno preuzimanje i nepromenjen javni snimak posle privatne izmene. Moderacija u završnom ponavljanju koristi isti `ApiAssetRepository` kao Flutter klijent.

Za izolovano završno ponavljanje korišćeni su portovi API 18080, javni veb 18081 i fake worker 18091, pošto je podrazumevani API port koristio drugi lokalni projekat. Konfiguracija je zamenljiva env promenljivama; tuđi servis nije zaustavljan.

Stvarni HTTP cookie jar dodatno je proverio da browser ne dobija refresh token u JSON-u, da studio i backoffice čuvaju zasebne HttpOnly cookie-je, da oba zadržavaju svoju ulogu posle rotacije i da odjava moderatora ne prekida sesiju kreatora.

## Provera browser interfejsa

U lokalnom in-app browser-u na `localhost:8082` stvarno su izvršeni registracija test kreatora, izbor sintetičkog PNG-a kroz file chooser, čuvanje nacrta, upload, zahtev za generisanje, obnova HttpOnly sesije i prikaz završenog PNG rezultata. Posao je nastavljen na serveru tokom reload-a.

Reload je otkrio gubitak direktne rute; ispravka čuva početnu hash rutu pre privremenog login `MaterialApp` i ima prolaznu regresionu proveru. Browser alat nije potvrdio download događaj, a kasniji pristup ovom browser poreklu nije odobren. Zato finalni ručni reload i browser save dijalog nisu označeni kao provereni. Stvarni GLB bajtovi i oba klijentska session-a provereni su povezanim HTTP scenarijem. Android sistemski gallery/share dijalog nije automatizovan ovim repozitorijumskim testovima.

## Workspace bez postojećih izlaza

Završni izvoz 167 izvornih fajlova iz `git ls-files --cached --others --exclude-standard` kopiran je i SHA256 proveren u `.local/clean-check/source-export-final`. Izvoz je osvežen završnim izmenama bez promene zavisnosti. Početni izvoz nije sadržao `.git`, privatni `.env`, postojeći `.dart_tool` ili build izlaze. `flutter pub get` iz tog izvezenog korena završio je uspešno, svih sedam paketa pokazuje na izvezeno stablo, a `pubspec.lock` nije promenjen. Ovo je provera čistog izvornog izvoza uz standardni globalni Pub keš, ne tvrdnja da je kod već predat kroz novi Git klon.

## Platforme

| Build | Stanje |
|---|---|
| Kreatorski Flutter veb, API režim | Release build prolazi |
| Moderatorski Flutter veb, API režim | Release build prolazi |
| Windows backoffice | Release build prolazi |
| Android APK, API režim | Debug build prolazi, uključujući native JNI zavisnost |
| Android APK, KT1 režim | Release build prolazi; lokalni razvojni potpis, bez store objave |
| Android stvarni offline test | Tri faze prolaze: prepare, offline, sync sa konfliktom |

Komanda `tool/test-offline-device.ps1 -DeviceId emulator-5554 -ApiUrl http://10.0.2.2:18080 -HostApiUrl http://127.0.0.1:18080 -WithConflict` proverila je pravi SQLite i secure storage u tri odvojena procesa na AVD-u `Hedrion_Test`. Android mreža stvarno je isključena; izmena naziva/favorita i outbox preživeli su restart. Drugi HTTP klijent izmenio je istu serversku reviziju; sync je izložio konflikt i primenio lokalnu izmenu tek nakon izričitog razrešenja. Skripta koristi `--no-uninstall` da Flutter ne obriše podatke između faza i `--no-enable-impeller` za lokalni emulator. Mreža se vraća i posle greške.

Posle integracionog testa prvi release pokušaj sa `--no-pub` koristio je zastarelu registraciju `integration_test` plugina. Standardni `flutter build apk --release`, koji obnavlja Flutter konfiguraciju i isključuje razvojne plugin-e, zatim je uspešno napravio APK od 52,2 MB. Generisani registrant nije ručno menjan. Pri prelasku iz test režima koristiti standardne build komande iz README-a.

Zatim je `flutter run -d emulator-5554 --no-resident --no-enable-impeller --dart-define=HEDRION_MODE=api --dart-define=HEDRION_API_URL=http://10.0.2.2:18080` uspešno izgradio, instalirao i pokrenuo običan `lib/main.dart`. Time je `app-debug.apk` vraćen sa test entrypoint-a na aplikaciju. U filtriranom Flutter log-u tog procesa nisu zabeležene neobrađene greške; to ne predstavlja ručnu proveru svih sistemskih dijaloga.

Android provera zahteva NDK `28.2.13676358`. Lokalni SDK CLI wrapper je pogrešno obradio staru sintaksu, a automatsko raspakivanje je zatim naišlo na nedostatak prostora. Za oporavak su premešteni samo novokreirani test AVD podaci na F: i uklonjeni samo potvrđeni nepotpuni privremeni fajlovi neuspešne instalacije. Korisnički projekti i prethodno instalirani NDK nisu uklanjani.

Traženi NDK je zatim raspakovan iz već preuzetog zvaničnog arhiva i njegov kompajler/revizija su provereni. Generisani Android build izlazi ovog projekta premešteni su na `F:\Hedrion_Builds\mobile`, sa lokalnim junction-om u `apps/mobile/build`, da ne pune sistemski disk. Test AVD `Hedrion_Test` nalazi se u `F:\Hedrion_Test.avd`. Ove lokalne putanje nisu zavisnost izvornog koda ni čistog izvoza; na računaru sa dovoljno prostora standardne Flutter komande koriste običan `build` direktorijum.

## Granice isporuke

Konkretan AI model i cloud nisu izabrani. Aktivni provider je označen fake; prethodni konkretni adapteri ostaju isključeni eksperimenti i ne ulaze u obaveznu instalaciju. Nisu izvršeni stvarna GPU inferencija, cloud deploy, objava u prodavnici ili potpisivanje produkcionim ključem.

Pregled rezultata koristi PNG fallback sa mogućnošću GLB preuzimanja; interaktivni 3D viewport nije implementiran. Skladište fajlova je odvojeni lokalni persistent volume; S3/MinIO adapter nije povezan. CI je pripremljen, ali GitHub workflow nije pokrenut sa ovog lokalnog nekomitovanog stabla. Prihvatanje teme, predaja do roka i usmena odbrana ostaju spoljašnji uslovi.
