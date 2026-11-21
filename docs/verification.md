# KT2 provere

## Rezultati od 21.11.2026.

| Provera | Rezultat |
|---|---|
| Statika | Flutter analiza bez nalaza |
| Dart sa PostgreSQL-om | 138 testova prošlo |
| Flutter | 33 mobilna, 8 moderatorskih i 2 testa adaptera za sesije prošla |
| Python worker | 39 testova prošlo |
| Povezani KT2 HTTP tok | 55 provera prošlo nad Relic 1.2.0, PostgreSQL-om i lokalnim fake workerom |
| Podešeni istek sesije | 8 HTTP provera prošlo sa pristupnim rokom od 2 s i ukupnim rokom od 3 s |

Integracioni testovi proveravaju i poslednje mesto u globalnoj kvoti pod istovremenim zahtevima, zabranu izmena tuđih modela i odluka kreatora, zastarelu moderatorsku reviziju, ponovno pokretanje seed-a bez prepisivanja i izolaciju veb sesija. Nova HTTP regresija proverava oblik odgovora za projekte, `If-Match`, filtriranje po vlasniku i ponavljanje stare offline operacije bez duplog upisa. U odgovoru na konflikt ostaju kôd i aktuelna revizija.

Za povezanu proveru korišćen je čist izvoz Git izvora i identična kopija `.env.example`. API je bio na portu 19180, a PostgreSQL na 55435 zbog drugih lokalnih servisa. Compose je podigao sva tri servisa i automatski učitao 16 modela i četiri demo naloga. Provera je obuhvatila GLB i PNG rezultat, odobravanje i odbijanje, osvežavanje drugog klijenta i poruku pri nedostupnom serveru. HTTP proveru pokrenuti nakon PostgreSQL testova kada dele istu bazu, jer obe provere koriste isti transakcioni lock.

## Platformske i prethodne provere

Provera od 20.11. potvrdila je prijavu, osvežavanje i odjavu u oba veb klijenta. Testovi bezbednog skladišta na Android emulatoru i Windowsu prošli su kroz tri odvojena pokretanja i potvrdili obnovu sesije, odjavu i odsustvo odjavljene sesije posle restarta. Pored toga, ranija Android provera sa `tool/test-offline-device.ps1 -WithConflict` pokrila je SQLite outbox bez mreže, restart uređaja i sinhronizaciju sa stvarnim konfliktom revizije.

GitHub Actions za već poslati commit `cf8b29d` je prošao, uključujući Android APK, Windows backoffice i veb buildove. [GitHub Actions](https://github.com/Razvoj-multiplatformskih-aplikacija-26/tim-24/actions/runs/44917891816)

## Proba prethodno izgrađenog APK-a

Na emulatoru `Hedrion_Test` instaliran je debug APK iz commita `cf8b29d`, izgrađen sa granicom 60 i API adresom `http://10.0.2.2:19180`. U ekranu **Projekti** sačuvan je naziv od 45 znakova. Granica je potom promenjena na 40 u izolovanoj kopiji serverskog izvora i ponovo je podignut samo API. Baza, sesija, adresa i instalirani APK ostali su isti.

Isti APK je pri slanju drugog naziva od 45 znakova prikazao „Naziv mora imati od 3 do 40 znakova.“ Direktni HTTP zahtevi za projekat i model vratili su 422, kôd `invalidTitle` i podatke `maxLength: 40` i `actualLength: 45`. Granica u izvornom kodu za predaju je 60. [Koraci za odbranu](kt2-defense.md#izmena-pravila-uživo-i-stara-verzija)

KT2 provere su koristile lokalni fake worker sa stvarnim GLB i PNG fajlovima. Podešavanje i ranija merenja pravih Modal modela su u [Modal dokumentaciji](modal-generation.md). Ove provere nisu trošile GPU kredite.
