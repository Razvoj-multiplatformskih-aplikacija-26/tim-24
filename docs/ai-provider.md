# AI worker sa zamenljivim providerom

Konkretan model za tekst/slika → 3D **još nije izabran**. Aktivni sistem koristi
zajednički `GenerationProvider` port i deterministički fake provider. Izbor
stvarnog modela ili cloud dobavljača ne menja Flutter tokove i serverski ugovor.
Sačuvani konkretni adapteri predstavljaju isključene eksperimente, bez odluke da
se koriste u proizvodu.

## Lokalni režim

`services/gpu_worker` sadrži proverljiv `GenerationProvider` port i deterministički
`FakeGenerationProvider`. Fake pravi pravi, mali GLB 2.0 fajl: kocku sa 12 trouglova,
24 verteksa, normalama i PBR materijalom. Boja zavisi od SHA-256 ulaza. PNG prikazuje
istu geometriju. Ovo proverava prenos, prikaz i čuvanje rezultata, **ne AI kvalitet**.
Metapodaci imaju `demo: true`, a provider ima naziv `fake`.

Python 3.11 ili noviji dovoljan je za fake worker i njegovih osnovnih 15 testova;
nema obaveznih pip paketa. Dodatni CPU testovi Pixal CLI adaptera zahtevaju Pillow
iz `requirements-real.txt`. Iz korena repozitorijuma:

```powershell
cd services/gpu_worker
# Postaviti slučajno generisanu tajnu i na Dart API-ju i na worker-u.
$env:WORKER_SHARED_SECRET = '<najmanje 32 nasumična znaka>'
$env:GENERATION_PROVIDER = 'fake'
python -m hedrion_worker.server
```

Testovi iz istog direktorijuma:

```powershell
python -m unittest discover -s tests -v
```

Za aktivnih 15 fake/HTTP testova dovoljan je
`python -m unittest discover -s tests -p test_worker.py -v`.
Dodatni eksperimentalni CPU testovi mogu da se izvrše kada Pillow već postoji;
nisu preduslov za lokalni demo. Prethodno je provereno svih 24 testa sa bundled
Python-om i postojećim Pillow 12.3.0. Kontrolisani CLI u testovima nije AI GPU.

Worker podrazumevano sluša `127.0.0.1:8091`. `--host`, `--port`, `WORKER_HOST` i
`WORKER_PORT` menjaju adresu. Dockerfile koristi korisnika bez administratorskih prava;
port proslediti samo internoj mreži. Worker-u nisu potrebni pristup javnoj bazi,
klijentski tokeni ni privilegije za objavljivanje modela.

## Privatni HTTP ugovor

`GET /health` vraća samo stanje i naziv providera. `POST /internal/v1/generate`
prima JSON:

```json
{
  "jobId": "generation_123",
  "ownerId": "creator_456",
  "inputType": "image_to_3d",
  "sourceImageBase64": "<base64 PNG ili JPEG slike>"
}
```

Za mock teksta koristiti `inputType: text_to_3d` i `sourcePrompt`; rezultat ostaje
označen kao fake. Stvarni tekst → slika provider nije povezan.

Obavezna zaglavlja:

| Zaglavlje | Vrednost |
|---|---|
| `Content-Type` | `application/json` |
| `Authorization` | `Bearer <WORKER_SHARED_SECRET>` |
| `X-Hedrion-Timestamp` | UTC Unix vreme u sekundama |
| `X-Hedrion-Nonce` | Jedinstvenih 16–128 slova, cifara, `_` ili `-` |
| `X-Hedrion-Signature` | Heksadecimalni HMAC-SHA256 potpis |

Potpisani bajtovi su `timestamp + "." + nonce + "." + rawJsonBody`, ključ je
`WORKER_SHARED_SECRET`. Potpis proveriti nad tačnim poslatim bajtovima. Prozor je pet
minuta. Ponovljeni nonce se odbija; legitiman ponovljeni zahtev koristi nov nonce i
isti `jobId` i payload. Za isti završen posao vraća se keširan odgovor; izmenjen
payload dobija `409 JobPayloadConflict`. Keš je ograničen na 128 rezultata i 32 MB,
živi samo tokom procesa. Trajna idempotentnost i oporavak poslova ostaju odgovornost
Dart servera; restart worker-a ili izbacivanje iz keša može ponovo izvršiti inferenciju.

Uspeh sadrži `jobId`, `provider`, `modelBase64`, `previewBase64`, `modelMime`,
`previewMime`, `metadata` i `metrics`. Slike su ograničene na 10.000.000 bajtova,
PNG dimenzije na 8192 po osi i 32 miliona piksela. Provera zaglavlja u fake režimu
nije potpuni dekoder slike. GLB se proverava kao samostalan 2.0 kontejner bez
spoljašnjih URI resursa, uz provere dužina i opsega bafera.

Najviše dve inferencije rade paralelno u procesu; zauzet worker vraća `503 WorkerBusy`.
Globalni raspored preko više instanci, kvote, lease, retry i evidenciju prijema vodi
Dart API. Server prima izmerene bajtove u privremeni prostor, atomski rezerviše trajni
prostor, čuva oba fajla i tek tada potvrđuje `ready`. Ovaj odgovor nije dozvola za
zaobilaženje kvota. Pri komunikaciji van localhost-a potreban je HTTPS i interna
mreža; korisnički klijenti ne pozivaju worker.

## Arhiva pregleda neizabranih kandidata

Sledeći nalazi čuvaju prethodni istraživački rad. Oni ne određuju aktivni model
ili cloud i ne zahtevaju instalaciju ovih biblioteka za pokretanje Hedriona.

Provera izvora obavljena je 21. oktobra 2026. Pixal3D je image-to-3D sistem.
Zvanično uputstvo traži TRELLIS.2 okruženje, dodatne zahteve, CUDA-kompatibilan
`natten` i `utils3d`. Ne treba kopirati H-series demo okruženje na drugu arhitekturu
bez provere. [Pixal3D README](https://github.com/TencentARC/Pixal3D).

Opcije `--image`, `--output`, `--low_vram` i `--resolution` postoje u zvaničnom
`inference.py`. CLI proizvodi GLB. Zaseban korak za tekstualni unos mora da proizvede
referentnu sliku pre ovog poziva. [Zvanični CLI](https://github.com/TencentARC/Pixal3D/blob/master/inference.py).

TRELLIS.2 dokumentuje Linux i proveru na A100/H100, uz CUDA ekstenzije. To nije
dokaz da Pixal3D uspešno radi na L4/L40S ili da staje u određenu memoriju.
[TRELLIS.2 instalacija](https://github.com/microsoft/TRELLIS.2#installation).

Modal dokumentuje GPU oznake `L4` i `L40S`, `Image.from_registry` i ubacivanje tajni
kroz `Secret.from_name`. Potreban je zasebno izgrađen, pinovan Linux/amd64 image,
proveren za izabranu CUDA/GPU kombinaciju; postojanje GPU oznake ne potvrđuje
kompatibilnost modela. [GPU](https://modal.com/docs/guide/gpu),
[image](https://modal.com/docs/guide/existing-images),
[tajne](https://modal.com/docs/guide/secrets).

## Licence

Pixal3D i TRELLIS.2 imaju MIT licencu za svoj kod. Pixal3D NOTICE zadržava uslove
komponenti drugih autora. [Pixal3D LICENSE](https://github.com/TencentARC/Pixal3D/blob/master/LICENSE),
[NOTICE](https://github.com/TencentARC/Pixal3D/blob/master/NOTICE),
[TRELLIS.2 LICENSE](https://github.com/microsoft/TRELLIS.2/blob/main/LICENSE).

Provereni NVIDIA `nvdiffrast` i `nvdiffrec` dokumenti licence sadrže ograničenja
nekomercijalne istraživačke/evaluacione upotrebe za korisnike van NVIDIA. MIT licenca
glavnog repozitorijuma ne menja ove uslove. Pre komercijalne isporuke proveriti tačne
pinovane zavisnosti, licence težina i sve obavezne atribucije; komercijalna dozvola
ovog kompletnog lanca nije potvrđena.
[nvdiffrast LICENSE](https://github.com/NVlabs/nvdiffrast/blob/main/LICENSE.txt),
[nvdiffrec LICENSE](https://github.com/NVlabs/nvdiffrec/blob/main/LICENSE.txt).

## Neizabrani eksperimentalni CLI adapter

`Pixal3DCliProvider` je sačuvan kao eksperimentalna referenca rada sa upstream
`inference.py` kroz odvojen proces i niz argumenata bez shell-a. Nije aktivni ili
izabrani model proizvoda. Worker ga dodatno drži isključenim kroz
`ENABLE_EXPERIMENTAL_PROVIDER=false`, uz podrazumevani `GENERATION_PROVIDER=fake`.
Samo postavljanje imena konkretnog providera ne može tiho da aktivira eksperiment.

Eksperimentalne putanje i GPU okruženje nisu obezbeđeni ovim repozitorijumom.
Izvršna putanja podrazumeva aktivni Python ako nije zadata.
Neispravan checkout, izvršni fajl, rezolucija ili timeout sprečava pokretanje;
nema prebacivanja na fake. Podržane CLI rezolucije su 1024 i 1536, bez tvrdnje
da su ostvarivi nivoi kvaliteta ili da određeni GPU može da ih izvrši.

Adapter potpuno dekodira PNG/JPEG, proverava dimenzije i uklanja EXIF/metapodatke.
Ulaz i izlaz su u zasebnom privremenom direktorijumu; čiste se i posle greške.
Worker tajna ne prosleđuje se podprocesu. Timeout, neuspešna inferencija,
nepostojeći rezultat i neispravan/prevelik GLB daju sanitizovane greške.
`text_to_3d` daje `UnsupportedInput` dok odvojeni `ReferenceImageProvider` nije
stvarno povezan. Nijedan tekstualni zahtev se ne predstavlja kao nativna Pixal3D
mogućnost.

Izlazni GLB prolazi proveru kontejnera. Fallback preview je referentna ulazna
slika sa vidljivom oznakom da **3D pregled rezultata nije napravljen**. Metapodaci
sadrže `previewKind: reference_image_fallback` i `previewIsGeneratedModel: false`.
Ne koristi se fake kocka kao rezultat stvarnog providera. Za stvarni pregled
geometrije/tekstura dodati provereni renderer pre produkcije.

## Neizabrana eksperimentalna cloud definicija

`services/gpu_worker/modal_app.py` je sačuvana referenca koja koristi dokumentovane `Image.from_registry`,
`add_local_dir`, `App.function`, `Secret.from_name` i `web_server` API-je.
[Modal Image referenca](https://modal.com/docs/sdk/py/latest/Image),
[App.function referenca](https://modal.com/docs/sdk/py/latest/App#function),
[web_server referenca](https://modal.com/docs/sdk/py/latest/web_server).

Sledeća podešavanja opisuju tu referencu; nisu aktivna konfiguracija ili odluka
da se ovaj cloud koristi:

- `PIXAL3D_IMAGE`: sopstveni provereni Linux/amd64 image, pinovan kao
  `registry/path@sha256:<64 heksadecimalne cifre>`. Ovaj repo ne sadrži izmišljeni
  image tag niti pretpostavlja da je CUDA build izvršen.
- `MODAL_GPU`: eksplicitno `L4` ili `L40S`, tek posle provere image-a na tom GPU-u.
- `MODAL_PIXAL3D_ROOT`: stvarna apsolutna Linux putanja checkout-a u image-u.
- Opciono `MODAL_PIXAL3D_PYTHON`: stvarna putanja GPU Python okruženja u image-u.
- Modal Secret `hedrion-worker` sa `WORKER_SHARED_SECRET` i potrebnim tajnama za
  preuzimanje stvarnih težina. Naziv se može promeniti kroz
  `MODAL_WORKER_SECRET_NAME`; ime aplikacije kroz `MODAL_APP_NAME`.

Opcioni eksperimentalni requirements fajl čuva SDK 1.6.2 prema provernoj
[PyPI objavi](https://pypi.org/project/modal/1.6.2/); nije zavisnost aktivnog fake
režima. Instaliranje tog paketa ne pokreće niti potvrđuje cloud inferenciju.
Definicija ima nula stalno toplih kontejnera i najviše dva kontejnera; svaki obrađuje
jednu inferenciju odjednom. To ograničenje ne zamenjuje globalni raspoređivač i
kvote u Dart API-ju. Isti potpisani HTTP ugovor ostaje obavezan. Nakon stvarnog
deploy-a postaviti dobijeni HTTPS endpoint u serverski `WORKER_URL`, nikada u
Flutter klijent. Ova definicija nije deploy-ovana iz ove sesije.

Modal Web Functions imaju HTTP prozor od 150 sekundi, posle kog koriste `303`
adresu rezultata dok pozadinski poziv traje. Pre GPU isporuke proveriti ponašanje
serverskog HTTP klijenta za isti origin, čuvanje autorizacije, broj preusmerenja
i ukupni timeout. Dugi GPU test još nije obavljen; za duže poslove koristiti
privatni dispatch/poll ili callback adapter umesto pretpostavke da jedan otvoren
HTTP zahtev može neograničeno da traje.
[Modal request timeouts](https://modal.com/docs/guide/webhook-timeouts).

## Nakon izbora stvarnog modela

Nakon odluke tima proveriti zvanični interfejs, stvarno podržane ulaze, licence i
verzije izabranog modela. Dodati ili potvrditi njegov adapter iza zajedničkog
porta, bez prepravljanja klijenata i domenskih pravila. Tek stvarni tok od ulaza
do sačuvanog i preuzetog GLB-a potvrđuje integraciju. Za tekstualni put koji
zahteva referentnu sliku koristiti odvojen adapter; ne oglašavati neproverenu
nativnu podršku. GPU/cloud način rada bira se tek ako ga izabrani model zahteva.
Kriterijumi merenja su u `docs/benchmarking.md`, a evidencija licenci u
`docs/licenses.md`. Nijedna stvarna AI inferencija nije izvršena u ovoj sesiji.
