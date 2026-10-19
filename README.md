# tim-24
Hedrion 3D - Aplikacija za kreiranje i organizovanje 3D modela za video-igre pomoću veštačke inteligencije iz tekstualnih opisa ili slika, koja korisnicima omogućava upravljanje ličnom bibliotekom, pregled i preuzimanje modela, kao i deljenje modela u javnoj biblioteci nakon odobrenja moderatora.

# Hedrion

**AI studio za kreiranje, organizovanje i deljenje 3D modela za video-igre.**

Hedrion je multiplatformska aplikacija namenjena studentima i manjim timovima koji razvijaju igre. Korisnici kreiraju statične 3D rekvizite na osnovu referentnih slika ili tekstualnih opisa, čuvaju ih u privatnoj biblioteci, pregledaju i preuzimaju u GLB formatu. Za tekstualni unos planiran je postupak u dva koraka: generisanje referentne slike, pa pretvaranje slike u 3D model.

Korisnik može da predloži završeni model za javnu biblioteku. Moderator proverava prijavu i odlučuje o objavljivanju, a odobreni modeli dostupni su svima na javnom vebu. **Lična biblioteka je osnovna namena aplikacije; javno deljenje je opciono.** 


## Tim

| Ime i prezime | Broj indeksa | GitHub nalog |
|---|---|---|
| Vasilije Stankovic | SI 100/24 | [Vaske10024](https://github.com/Vaske10024) |
| Jovan Petrovic | SI 115/24 | [jpetrovic115si](https://github.com/jpetrovic115si) |

## Obrazloženje zahteva za temu

1. **Uloge.** Kreator putem mobilne aplikacije kreira i uređuje svoje privatne 3D modele i predlaže završene modele za javnu biblioteku. Moderator u backoffice aplikaciji pregleda prijavljene modele i ima ovlašćenje da odobri ili odbije njihovo objavljivanje.

2. **Stanja.** Glavni pojam sistema je **3D model (`Asset`)**, koji prolazi kroz stanja `draft` (nacrt), `queued` (u redu za generisanje), `generating` (generisanje), `ready` (spreman), `pendingReview` (na moderatorskoj proveri) i `published` (objavljen), uz stanja `failed` (neuspela generacija) i `rejected` (odbijena javna prijava). Objavljivanje je opciono, pa model može trajno da ostane privatan u stanju `ready`; dozvoljeni prelazi proveravaju se u zajedničkom domenskom paketu.

3. **Pravila.** Naziv modela mora imati od 3 do 60 znakova nakon uklanjanja početnih i završnih razmaka, a samo vlasnik završenog modela sa dostupnim izlaznim fajlom može da ga pošalje na moderatorsku proveru. Najviše **dve generacije mogu se izvršavati istovremeno u celom sistemu**, pa slobodan kapacitet zavisi od poslova drugih korisnika i konačnu odluku o pokretanju donosi server, dok ostali prihvaćeni zahtevi čekaju u redu.

4. **Rad bez mreže.** Korisnik može bez internet veze da promeni naziv ili opis sopstvenog modela čiji su podaci već sačuvani u lokalnoj biblioteci. Izmene se trajno pamte na uređaju i sinhronizuju po povratku veze, uz obaveštenje o eventualnom konfliktu; samo AI generisanje zahteva internet vezu.

5. **Posao za osoblje.** Moderator obrađuje veći broj prijava kroz tabelu sa pretragom, filterima, statusima i detaljima izabranog modela u bočnom panelu, za šta je potreban veći ekran. Za svaku prijavu može da odobri objavljivanje ili da ga odbije uz obrazloženje, a rad tastaturom olakšava obradu većeg broja zapisa.

6. **Javni sadržaj.** Javna biblioteka bez prijave prikazuje samo odobrene i objavljene modele, sa zasebnim stranicama koje sadrže naziv, opis, kategoriju, sliku pregleda i izabranu licencu. Stranice isporučuju sadržaj kao HTML pogodan za indeksiranje u pretraživačima, a preuzimanje modela omogućeno je kada ga autor dozvoli.

## Glavni tok rada

1. Kreator pravi nacrt modela, bira referentnu sliku ili unosi tekstualni opis i dopunjava podatke o modelu.
2. Zahtev ulazi u red čekanja, a server pokreće generisanje kada se oslobodi GPU kapacitet.
3. Nakon uspešne obrade model je spreman za pregled i preuzimanje u privatnoj biblioteci.
4. Kreator po želji šalje završeni model na pregled za javnu biblioteku.
5. Moderator odobrava ili odbija prijavu uz razlog. Samo odobreni model postaje javno dostupan.

Osnovni tok stanja:

```text
draft -> queued -> generating -> ready -> pendingReview -> published
generating -> failed -> queued
pendingReview -> rejected -> ready
```

Ponovni pokušaj generisanja pravi novi posao obrade. Odbijanje javne prijave ne briše uspešno generisani privatni model; posle dorade podataka kreator može ponovo da ga pošalje na pregled. Javna prijava vezuje se za konkretan generisani rezultat, tako da kasnije privatne izmene ne menjaju automatski već odobreni javni sadržaj.
