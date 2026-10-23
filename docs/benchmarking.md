# Provera budućeg AI providera

Konkretan model i infrastruktura još nisu izabrani. Aktivni fake provider služi
proveri aplikacionog ugovora, bez tvrdnje o AI kvalitetu, brzini ili trošku.
U ovoj sesiji nije izvršena stvarna AI inferencija. Sačuvani eksperimentalni
testovi adaptera koriste kontrolisani CPU CLI koji vraća poznat GLB.
Njihov prolaz potvrđuje ugovor, obradu grešaka i validaciju, bez tvrdnje o AI
kvalitetu, brzini, VRAM-u ili stvarnom GPU trošku.

Kada tim izabere stvarni provider, zabeležiti sledeće:

| Podatak | Način provere |
|---|---|
| Provider i verzija | Tačan API/model ili Git commit i revizija težina |
| Model weights | Sačuvati identifikator/reviziju i pročitane uslove korišćenja |
| Okruženje | Ponovljiva konfiguracija i zaključane zavisnosti odabranog providera |
| Hardver | Stvarno dodeljeni uređaj kada ga provider zahteva |
| Hladni start | Odvojiti pokretanje kontejnera/preuzimanje težina od inferencije |
| Inferencija | Početak/kraj stvarnog CLI-ja sa istim testnim slikama i seed-om |
| VRAM | Izmeriti na uređaju; ne zaključivati iz deklarisane memorije GPU-a |
| Rezultat | Validan GLB, broj stvarno izmerenih elemenata, izlazni bajtovi |
| Preview | Stvarni render ili vidljivo označen referentni fallback |
| Trošak | Aktuelna cena odabranog servisa × izmerena potrošnja |

`inference_ms` sačuvanog eksperimentalnog adaptera predstavlja izmereno zidno vreme CLI podprocesa, uključujući
njegovo učitavanje težina; dekodiranje i validacija imaju zasebne `preprocess_ms` i
`postprocess_ms`, a ceo poziv `worker_elapsed_ms`. `cold_start_ms`, `peak_vram_mb` i
`cost` su nepoznati (`null`). `gpu_type` potiče iz konfiguracije, uz zasebnu oznaku
`gpu_type_source`; nije rezultat detekcije hardvera. Ne koristiti ove vrednosti
kao produkcioni GPU benchmark dok se mereći kod ne dopuni za taj image.

Scenarij za stvarnu proveru:

1. Sačuvati verzije, licence i ponovljivu konfiguraciju prema zvaničnim izvorima
   izabranog modela ili API-ja.
2. Proveriti to okruženje na stvarno odabranom hardveru ili servisu; deklarisane
   mogućnosti nisu dokaz da konkretna integracija radi.
3. Poslati sopstvenu PNG/JPEG sliku kroz kreatorski studio, sačuvati job ID i
   ispratiti serverski posao bez otvorenog klijenta.
4. Proveriti da job postaje `ready` tek posle kvota i trajnog čuvanja oba fajla.
5. Preuzeti GLB kroz metereni API sa telefona i veba; otvoriti rezultat u
   pouzdanom GLB pregledniku i proveriti stvarnu geometriju/materijale.
6. Ponoviti iste ulaze radi procene pouzdanosti i razlike hladnog/toplog starta.
   Ne birati nivo kvaliteta samo prema rezoluciji komandne linije.
7. Proveriti OOM/timeout/nevažeći izlaz i ponavljanje istog posla, bez dodatnog
   prijema ili prekoračenja globalnih kvota.

Aktuelne cene izabranog servisa proveriti u trenutku merenja. Ovaj dokument ne
propisuje model, cloud, trajanje ni cenu inferencije. Rezultat fake kocke nije
produkcioni benchmark, a nepoznate metrike ostaju `null` ili izostavljene.
