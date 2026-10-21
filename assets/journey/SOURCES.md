# Okeyix Yolculuk — data, models and licensing

Downloaded 2026-10-21. All runtime assets are bundled; no remote map, telemetry,
API token, OSM tile server or user data is used by the scene.

## Geography (redistributable derived data)

- **Natural Earth, 1:10m Admin-0 Countries**, public domain.
  Source: https://github.com/nvkelso/natural-earth-vector/blob/master/geojson/ne_10m_admin_0_countries.geojson
  Terms: https://www.naturalearthdata.com/about/terms-of-use/
  Source SHA256: `239eec57ac17f100a11e2536cffc56752c318b50ae765b0918ff7aab4ce8f255`.
  Turkey's supplied six polygon parts and holes are retained.
  Nine neighbouring-country land outlines are clipped and shown neutrally so
  Turkey's land borders are not falsely surrounded by sea. Neighbouring land
  is deliberately flat, with no invented elevation.
  Istanbul is a
  clipped derivative, NOT a high-resolution cadastral coastline. Political
  boundaries inherit Natural Earth's representation and date.
- **Mapzen/Terrarium elevation tiles** from the public AWS elevation collection:
  https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png
  Decoder: metres = R×256 + G + B/256 − 32768. Country source zoom 5,
  resampled to 241×101; Istanbul zoom 11, resampled to 121×121. Height is
  bilinearly interpolated at runtime. No synthetic mountain heights.
  Display exaggeration: Turkey **12×**, Istanbul **1.5×**. Elevation colors are
  illustrative, not land-cover classification. Low-resolution sampling misses
  summits and fine valleys; this is not a navigation or surveying product.
  Attribution: **Mapzen; USGS SRTM / GMTED2010; NOAA ETOPO1; Produced using
  Copernicus data and information funded by the European Union — EU-DEM layers.**
  Upstream attribution and individual source terms are retained in
  `TERRAIN-ATTRIBUTION.txt`:
  https://github.com/tilezen/joerd/blob/master/docs/attribution.md
  https://github.com/tilezen/joerd/blob/master/docs/data-sources.md
- **Open Admin Data — Turkey administrative divisions**, CC BY 4.0, ©2026
  jakkrapongt. Source:
  https://github.com/open-admin-data/turkey-administrative-divisions
  License: https://creativecommons.org/licenses/by/4.0/
  Full source license: `PROVINCES-LICENSE.txt`.
  Source SHA256: `cee5cb4a29308ebea950400d3667d061096a6ff3f35ec0ec47d3231c4fd2c949`.
  Changes: retain province IDs/centroid coordinates; normalize Turkish names,
  drop administrative metadata, use an Istanbul historic-city entry anchor.
  These are province label anchors, not all downtown GPS coordinates.

**Explicit approximation:** Natural Earth omits the Golden Horn inlet at this
scale. The inset coastline contains a hand-simplified Golden Horn indentation
in `build_journey_geography.cjs`, identified in the in-app source panel.
It is not OSM, surveyed or DEM-derived coastline. Global OSM endpoints could
not supply data during preparation; no empty response is used as geography.
Natural Earth's coarse shoreline also differs locally around actual quays;
the place foundations are local illustrative geometry.

The source panel is accessible on every scene via “Veri kaynakları”. Derived
data are distributed in `geography.js`; the underlying source licenses remain
applicable. The only installed 3D library is Three.js r160, MIT, retained from
the first prototype (`vendor/THREE-LICENSE.txt`).

## Architecture

All six models and all textures are original procedural code. No purchased,
unlicensed, photographic facade or third-party model is included. PBR means
roughness/metalness, generated stone/wood color+bump maps, procedural sky IBL,
and directional shadow lighting; it does not mean photogrammetric accuracy.

Geographic anchors (longitude/latitude, approximate):

| Place | Longitude | Latitude | Model status |
|---|---:|---:|---|
| Kız Kulesi | 29.0041 | 41.0211 | Detailed architectural interpretation; island, defensive parapets, square tower, octagonal lantern, bell-shaped lead cap, gallery, flag, quay and jetty. Separate close-detail geometry. Not a measured restoration model. |
| Galata | 28.9741 | 41.0256 | Lightweight approximation: cylindrical masonry, balcony and conical roof. |
| Ortaköy | 29.0271 | 41.0473 | Lightweight approximation: mosque, dome, two minarets, seafront base. |
| Pierre Loti | 28.9338 | 41.0548 | Illustrative elevated terrace, cafe, railings, trees; no surveyed site model. |
| Haydarpaşa | 29.0186 | 40.9969 | Lightweight approximation: long facade, wings, corner towers and steep roof. |
| Rumeli Hisarı | 29.0562 | 41.0848 | Lightweight approximation: connecting defensive walls and towers. |

Architectural reference information, not downloaded art:
https://kizkulesi.gov.tr/tarihce
https://kizkulesi.gov.tr/restorasyon-kapsami
https://www.muze.gov.tr/muze-detay?DistId=MRK&SectionId=GLT04
https://www.kadikoy.gov.tr/haydarpasa-gari-ilcemiz

Ordinary city buildings are instanced representative urban grain constrained
to land; they are not real building footprints. Landmark positions use one
shared geographic projection. For overview legibility landmarks grow smoothly
up to **12×** their close-view scale with camera distance; close views retain
their approximate real metre dimensions. This is an interpretive city world,
not a full-scale digital twin. Bridges use approximate coastal anchors.

## Rebuild

`node tool/download_journey_geography.mjs` downloads source data only for the
asset build. Then `node tool/build_journey_geography.cjs` produces the small
bundled `geography.js` and license files. Raw downloads remain in ignored
`.dart_tool/journey_sources/`; they are not included in APK/IPA assets.
