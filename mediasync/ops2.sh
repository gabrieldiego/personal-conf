#/bin/bash

if [ -d "$1" ]; then
  echo dir $1 ;
  echo ${$1:3}
  pwd
fi
