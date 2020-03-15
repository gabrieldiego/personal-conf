sudo mkdir /var/lib/mod_tile
sudo chown renderaccount /var/lib/mod_tile

sudo mkdir /var/run/renderd
sudo chown renderaccount /var/run/renderd

sudo cat "LoadModule tile_module /usr/lib/apache2/modules/mod_tile.so" >> /etc/apache2/conf-available/mod_tile.conf

sudo a2enconf mod_tile

sudo vim /etc/apache2/sites-available/000-default.conf

#And add the following between the “ServerAdmin” and “DocumentRoot” lines:

#LoadTileConfigFile /usr/local/etc/renderd.conf
#ModTileRenderdSocketName /var/run/renderd/renderd.sock
## Timeout before giving up for a tile to be rendered
#ModTileRequestTimeout 0
## Timeout before giving up for a tile to be rendered that is otherwise missing
#ModTileMissingRequestTimeout 30

And reload apache twice:

sudo service apache2 reload
sudo service apache2 reload

