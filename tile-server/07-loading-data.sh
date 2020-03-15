mkdir ~/data
cd ~/data

wget https://download.geofabrik.de/africa/guinea-bissau-latest.osm.pbf

sudo -u renderaccount osm2pgsql -d gis --create --slim  -G --hstore --tag-transform-script ~/src/openstreetmap-carto/openstreetmap-carto.lua -C 2500 --number-processes 1 -S ~/src/openstreetmap-carto/openstreetmap-carto.style ~/data/guinea-bissau-latest.osm.pbf
