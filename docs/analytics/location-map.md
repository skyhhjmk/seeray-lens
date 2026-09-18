# Visitor country map

The Locations report includes an offline country choropleth. Shade intensity is based on session count for the selected date range and segment. Selecting a shaded country on the map or its row shows the matching visits and visitors. Country-level results remain available in the table for keyboard and screen-reader workflows.

Country boundaries are bundled from Natural Earth 1:110m Admin 0 country geometry and reduced to geometry plus ISO alpha-2 identifiers. The map makes no third-party tile or analytics request. Natural Earth publishes its vector data in the public domain: <https://www.naturalearthdata.com/about/terms-of-use/>. The asset is `admin/assets/maps/world-countries.json`.

The map visualizes the location dimensions already collected through the configured trusted edge proxy; it does not add IP collection or retain raw IP addresses. Natural Earth boundaries are generalized at world scale and should not be used for legal or cadastral purposes.
