sudo apt-get install postgresql postgresql-contrib postgis postgresql-12-postgis-3 postgresql-12-postgis-3-scripts

sudo -u postgres createuser renderaccount # answer yes for superuser (although this isn't strictly necessary)
sudo -u postgres createdb -E UTF8 -O renderaccount gis

sudo -u postgres psql -f 2-psql-commands.sql

sudo useradd -m renderaccount
sudo passwd renderaccount << EOF
root1234
root1234
EOF

sudo usermod -aG sudo renderaccount

