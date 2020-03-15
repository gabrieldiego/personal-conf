cd ~/src
git clone -b switch2osm git://github.com/SomeoneElseOSM/mod_tile.git
cd mod_tile
./autogen.sh

./configure

make

sudo make install

sudo make install-mod_tile

sudo ldconfig
