cd ~/src
git clone git://github.com/gravitystorm/openstreetmap-carto.git
cd openstreetmap-carto

sudo apt install npm nodejs
sudo npm install -g carto
carto -v

carto project.mml > mapnik.xml

