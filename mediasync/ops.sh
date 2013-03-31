#!/bin/bash

# Look for unknown/undesired file types
case "$1" in
  find-files)
    echo "Looking for files without any known extension for the Music folder" ;
    find ../ -type f -not \( \
      -iname "*.mp2" -or -iname "*.mp3" -or -iname "*.aac" -or -iname "*.m4a" -or -iname "*.wma" -or -iname "*.asf" -or -iname "*.ra" -or -iname "*.ogg" -or -iname "*.flac" -or -iname "*.ape" \
  -or -iname "*.mid" -or -iname "*.wav" \
  -or -iname "*.m3u" -or -iname "*.wpl" -or -iname "*.jpg" -or -iname "*.jpeg" -or -iname "*.png" -or -iname "*.gif" -or -iname "*.bmp" \
  -or -iname "*.mp4" -or -iname "*.flv" -or -iname "*.ram" -or -iname "*.rmvb" -or -iname "*.avi" -or -iname "*.mpg" \
  -or -iname "*.txt" -or -iname "*.nfo" -or -iname "*.sfv" -or -iname "*.torrent" -or -iname "*.sh" \
  -or -iname "*.pdf" -or -iname "*.doc" -or -iname "*.html" -or -iname "*.htm" -or -iname "*.js" -or -iname "*.css" \
  -or -iname "*.zip" -or -iname "*.7z"  -or -iname "*.rar" -or -iname "*.par2" \
     \) ;
    echo "Finished" ;;
  remove-trash)
    #Remove all the annoying Thumbs.db and desktop.ini files 
    echo "Removing all Thumbs.db and desktop.ini" ;
    find . -name "Thumbs.db" -name "desktop.ini" -exec rm -f {} \; ;
    echo "Finished" ;;
  echo) echo "echo";;
esac

ALBUMS="-ipath ./Naruto/* "
#ALBUMS=$ALBUMS" -or -ipath \"./Naruto*\" "

echo $ALBUMS

#echo find . \( -iname "*mp3" -or -iname "*aac" \) -and \( "$ALBUMS" \)
#find . \( -iname "*mp3" -or -iname "*aac" \) -and \( -ipath "./Naruto/*" \)
find .. \( -ipath "../Naruto/*" \) -exec bash ops2.sh {} \;

exit

#find . -iname "*mp3" -or -iname "*aac"
#find . -not \( -iname "*mp3" -or -iname "*aac" -or -ipath "./Music American/*" \)
#find . \(-name "*mp3" -o -name "*aac" \) -prune -o -ipath .
#find   \( -path  ./mp3/David_Gray/Flesh\* -o -path "./mp3/David_Gray/Lost Songs" \* \) -prune -o -ipath \*david\ gray\*

