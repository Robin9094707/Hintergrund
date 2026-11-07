# RJ Wallpaper Studio

Native iPhone-App für eigene Wallpaper. Ab iOS 26, mit SwiftUI und Apples Liquid Glass.

- Import aus Fotos oder Dateien, inklusive MP4, MOV, GIF, JPEG, HEIC und PNG.
- Sperrbildschirm-Vorschau, Pinch-Zoom, Verschieben, Filter, Abdunkeln und Studio-Presets.
- Video- und GIF-Ausschnitte mit eigener Startposition, Länge und Auswahl des Titelbilds.
- JPEG und lautlose HEVC-MP4 in 2160 × 3840. Live Photos in 1080 × 1920 mit bis zu drei Sekunden Bewegung.
- Export in Fotos, Teilen von JPEG und MP4. Die Medienverarbeitung findet auf dem iPhone statt.

Das [Live Photo in den iPhone-Einstellungen als Hintergrund auswählen](https://support.apple.com/de-de/120734).
Die Animation spielt bei einem geeigneten Live Photo beim Aufwecken des Sperrbildschirms.
Die 4K-Dateigröße bezeichnet die Ausgabeauflösung. Die sichtbaren Details hängen vom Original ab.

## Build

`RJWallpaper.xcodeproj` in Xcode 26 oder neuer öffnen und das Scheme `RJWallpaper` auswählen.
GitHub Actions baut mit Xcode 27 eine unsignierte IPA und startet einen Simulator-Build auf einem iPhone.
Beim Sideloaden übernimmt das verwendete Tool die Signierung.
