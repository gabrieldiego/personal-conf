#!/bin/bash

#This script extracts musics from a long song with all songs (like a Youtube
# Video) and a list in the format:
# 00:00 Lua branca
# 02:32 A dama de ouros
# Commented out is the support for the following format:
# 01）风小筝-别丢下我不管 Fēng Xiǎozhēng-Don't leave me alone (00:00)
# 02）刘增瞳-我是真的爱过你 Liú Zēngtóng-I really loved you (04:33)

#TODO: Adapt to other list formats

#Usage: ./extract.sh list.txt input.mp3 album genre

list=$1
input=$2
album=$3
genre=$4
artist=$5

prepend_track_number_title=0

previous_n_seconds=0

counter=0

while IFS= read -r line
do
#  stime=`echo $line | cut -d "(" -f2 | cut -d ")" -f1`
  stime=`echo $line | cut -c -5`

  n_comma=`echo "$stime" | sed 's/[^:]//g' | awk '{ print length }'`
  n_comma=`echo "$stime" | sed 's/[^:]//g' | awk '{ print length }'`

  if [ $n_comma == 1 ]
  then
    n_seconds=`echo "$stime" | awk -F: '{ print ($1 * 60) + $2 }'`
  else
    n_seconds=`echo "$stime" | awk -F: '{ print ($1 * 3600) + ($2 * 60) + $3 }'`
  fi

  total_time=$(( n_seconds - previous_n_seconds ))

  list_time[$counter]=$n_seconds
  if [ $counter != 0 ]
  then
    list_duration[$counter-1]=$total_time
  fi

#  artist_name=`echo "$line" | cut -c 6- |  cut -d "-" -f1`
#  song_name=`echo "$line" | cut -c 6- |  cut -d "-" -f2 | cut -d " " -f1`
  artist_name=$artist
  song_name=`echo "$line" | cut -c 7- |  cut -d "-" -f1`

  list_artist[$counter]=$artist_name
  list_song[$counter]=$song_name

  previous_n_seconds=$n_seconds

  counter=$(( counter+1 ))

done < "$list"

list_time[$(( counter-1 ))]=2147483647

for ((i=0;i<$counter;i++))
do
  zi=`printf "%02d" $(( i+1 ))`

  output_filename="$zi - ${list_artist[$i]}-${list_song[$i]}.mp3"

  if [ -z "${list_duration[$i]}" ]
  then
    duration=""
  else
    duration="-t ${list_duration[$i]}"
  fi

  if [ "$prepend_track_number_title" == 0 ]
  then
    title="${list_song[$i]}"
  else
    title="$zi - ${list_song[$i]}"
  fi

  echo ffmpeg -y -i \"$input\" -metadata title=\"$title\" -metadata artist=\"${list_artist[$i]}\" -metadata album=\"$album\" -metadata genre=\"$genre\" -metadata track=$zi -ss ${list_time[$i]} -t ${list_duration[$i]} -c copy \"$output_filename\"
done

