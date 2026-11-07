# RJ Wallpaper Studio

Native iPhone-App für eigene Wallpaper. Ab iOS 26, mit SwiftUI und Apples Liquid Glass.

- Import aus Fotos oder Dateien, inklusive MP4, MOV, GIF, JPEG, HEIC und PNG.
- Sperrbildschirm-Vorschau, Pinch-Zoom, Verschieben, Filter, Abdunkeln und Studio-Presets.
- Video- und GIF-Ausschnitte mit eigener Startposition, Länge und Auswahl des Titelbilds.
- JPEG und lautlose HEVC-MP4 in 2160 × 3840. Live Photos in 1080 × 1920 mit HEIC-Standbild und bis zu zwei Sekunden Bewegung bei 60 fps.
- Sperrbildschirm-Player mit lokaler Audiodatei und animiertem 3:4-Cover aus Video oder GIF.
- Export in Fotos, Teilen von JPEG und MP4. Die Medienverarbeitung findet auf dem iPhone statt.

Das [Live Photo in den iPhone-Einstellungen als Hintergrund auswählen](https://support.apple.com/de-de/120734).
Die Animation spielt bei einem geeigneten Live Photo beim Aufwecken des Sperrbildschirms.
Die 4K-Angabe bezeichnet die Ausgabeauflösung. Die sichtbaren Details hängen vom Original ab.

## Sperrbildschirm-Player

Ein GIF oder Video importieren, den Ausschnitt wählen und **Sperrbildschirm-Player** öffnen.
Eine Audiodatei oder ein Video mit Ton aus Dateien wählen. Bei einem geladenen Video lässt sich dessen Ton auch direkt übernehmen. Anschließend die Wiedergabe starten. Auf dem Sperrbildschirm bei Bedarf auf das kleine Cover tippen.
iOS zeigt das animierte Cover in der System-Medienanzeige während der Wiedergabe. Mit **Stopp** wird die Medienanzeige für RJ Wallpaper beendet.

## Build

`RJWallpaper.xcodeproj` in Xcode 26 oder neuer öffnen und das Scheme `RJWallpaper` auswählen.
GitHub Actions baut mit Xcode 27 eine unsignierte IPA und prüft App-Start, 4K-Fotoexport, Cover-Rendern und Audiowiedergabe im iPhone-Simulator.
Beim Sideloaden übernimmt das verwendete Tool die Signierung.
