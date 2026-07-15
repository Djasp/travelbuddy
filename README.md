# TravelBuddy (macOS menu bar app)

TravelBuddy is een kleine menubalk-app voor macOS die periodiek de reistijd met de auto meet van je huidige locatie naar een instelbare bestemming, inclusief actueel verkeer (via Apple Kaarten / MapKit — geen API-key nodig).

## Wat de app doet

- Draait in de achtergrond als menubalk-app (geen dock-icoon).
- Meet standaard elke 10 minuten de reistijd (interval instelbaar 5–60 min).
- Toont de actuele reistijd in de menubalk, bijv. `32m`.
- Bouwt een referentie op: de **mediaan** van de metingen van de afgelopen 14 dagen (minimaal 5 metingen). De mediaan is robuuster dan het gemiddelde: één zware file trekt de referentie niet omhoog.
- Wordt de reistijd langer dan de referentie, dan is dat direct zichtbaar in de menubalk: `32m +9` (en een waarschuwingsicoon zodra de drempel is bereikt).
- Bij een vertraging **gelijk aan of groter dan** de instelbare drempel (standaard 10 min) krijg je één notificatie; zodra de vertraging weer onder de drempel zakt volgt een "vertraging voorbij"-notificatie.

## Vereisten

- macOS Sequoia (of recenter)
- Xcode 16+

## Installatie-optie 1: draaien vanuit Xcode (ontwikkeling)

1. Open `TravelBuddy.xcodeproj` in Xcode.
2. Kies scheme `TravelBuddy`.
3. Kies destination `My Mac`.
4. Klik op Run (`Cmd+R`).

De app verschijnt in de menubalk als auto-icoon.

## Installatie-optie 2: standalone app bouwen en zonder Xcode starten

```bash
xcodebuild -project TravelBuddy.xcodeproj -scheme TravelBuddy -configuration Release build
```

De app staat daarna in Xcode DerivedData, bijvoorbeeld:

```text
~/Library/Developer/Xcode/DerivedData/.../Build/Products/Release/TravelBuddy.app
```

Kopieer die `.app` naar `/Applications` en start hem:

```bash
open /Applications/TravelBuddy.app
```

## Eerste keer instellen

1. Bij de eerste start vraagt macOS om **locatietoegang** en om **notificaties** — sta beide toe.
2. Klik op het auto-icoon in de menubalk en open `Instellingen`.
3. Vul bij **Bestemming** een adres in (bijv. `Stationsweg 1, Zwolle`) en klik `Instellen`.
4. Stel eventueel het meetinterval en de vertragingsdrempel in.

De eerste meting volgt direct; daarna wordt op interval gemeten. Na 5 metingen is de referentie actief en worden vertragingen gedetecteerd.

## Hoe de vertraging wordt bepaald

- Elke meting (huidige locatie → bestemming, snelste autoroute met actueel verkeer) wordt opgeslagen.
- Referentie = mediaan van de metingen van de afgelopen 14 dagen.
- Reistijden **korter dan de vertragingsdrempel** tellen niet mee (en triggeren geen meldingen): dan ben je (bijna) op de bestemming — bijv. een thuiswerkdag terwijl de bestemming je huis is. Kies de drempel dus korter dan je normale reistijd.
- Vertraging = actuele reistijd − mediaan (afgerond op hele minuten, nooit negatief).
- Notificaties komen alleen op de **overgangen**: één bij het bereiken van de drempel, één bij het zakken eronder.
- Bij het wijzigen van de bestemming (>250 m verschil) wordt de geschiedenis automatisch gereset; dat kan ook handmatig via Instellingen.

## Probleemoplossing

### Menubalk toont `—`

Er is nog geen bestemming ingesteld. Open `Instellingen` en stel een adres in.

### Menubalk toont `!`

De laatste meting is mislukt. Open het menu voor de foutmelding. Meest voorkomend:

- **Locatietoegang geweigerd** — zet aan via Systeeminstellingen > Privacy en beveiliging > Locatievoorzieningen > TravelBuddy.
- **Route berekenen mislukt** — meestal tijdelijk (geen netwerk); de volgende meting probeert het opnieuw.

### Geen notificaties

Controleer Systeeminstellingen > Notificaties > TravelBuddy. Let op: notificaties komen pas zodra er een referentie is (minimaal 5 metingen) én de drempel wordt bereikt.

### Referentie klopt niet meer (bijv. na verhuizing of ander vast startpunt)

Metingen dicht bij de bestemming (korter dan de drempel) worden automatisch genegeerd, dus een thuiswerkdag met bestemming thuis vervuilt de referentie niet. Meet je structureel vanaf een ándere verre locatie, gebruik dan `Instellingen > Reset geschiedenis` om opnieuw te beginnen.

## Tests draaien

```bash
xcodebuild -project TravelBuddy.xcodeproj -scheme TravelBuddy -configuration Debug test -destination 'platform=macOS'
```
