import sys
import os
import re

def walk_subdirs(dir):
	sub_dirs = os.walk(dir).next()[1]
	for subdir in sub_dirs:
		print dir+subdir+'/'
		walk_subdirs(dir+subdir+'/')

def empty_tree(dir):
	empty=1
	sub_dirs = os.walk(dir).next()

	for subdir in sub_dirs[1]:
		if empty_tree(dir+subdir+'/') == 0:
			empty = 0
#		print dir+subdir+'/'

	if len(sub_dirs[2]) == 0 and empty != 0: # This test must be improved to councern only songs
		print "EMPTY " + dir
		return 1
	else:
		return 0

def tree_empty_of_songs(dir):
	empty=1
	sub_dirs = os.walk(dir).next()

	for subdir in sub_dirs[1]:
		if tree_empty_of_songs(dir+subdir+'/') == 0:
			empty = 0
			return 0

	for eachfile in sub_dirs[2]:
	        musics_present = re.match(r'(.*)(mp2|mp3|m4a|wma|asf|ra|ogg|flac|ape)',eachfile)
		if musics_present:
#			print "Song " + eachfile + " present @ " + dir
			empty = 0
			return 0
#		else:
#			print "File " + eachfile + " not recognized as a song in the dir " + dir

	if empty != 0:
#		print "No Songs @ " + dir
		return 1
	else:
		return 0 # Should not get up to here

def convert_all_songs(dir, target):
	if dir[-1:] != '/':
		dir = dir + '/'

	if target[-1:] != '/':
		target = target + '/'

	sub_dirs = os.walk(dir).next()

	if tree_empty_of_songs(dir) == 0:
		# Remove leading ../
		dir_target = target
                if os.path.isdir(dir_target):
                        print "# Dir " + dir_target + " already exists"
                else:
                        print "mkdir \"" + dir_target + "\""
	else:
		print "# Folder " + dir + " is empty"
		return

	for subdir in sub_dirs[1]:
		if dir_target != './': # Do not walk into subdirectories for .
                        target_subdir = target+subdir+'/'
                        src_subdir = dir+subdir+'/'
			convert_all_songs(src_subdir, target_subdir)

	for song in sub_dirs[2]:
#TODO: Instead of just for MP3, test case insensitive for all
	        song_match = re.match(r'(.*)(\.mp2|\.mp3|\.MP3|\.m4a|\.wma|\.asf|\.ra|\.ogg|\.flac|\.ape)',song)
		if song_match:
			if (re.match(r'(.*)(\.ogg)',song)) :
				print "# No need to convert " + song
				song_ogg = dir_target + song
                                if os.path.isfile(song_ogg):
                                        print "# File " + song_ogg + " already exists"
                                else:
                                        print "cp \"" + dir + song + "\" \"" + song_ogg + "\""
			else:
#				print "Must convert " + song + " to " + (song_match.group(1)) + "ogg"
				song_ogg = dir_target + song_match.group(1) + ".ogg"
                                if os.path.isfile(song_ogg) :
                                        print "# File " + song_ogg + "already exists"
                                else:
                                        if os.path.isfile(dir_target + song) and re.match(r'(.*)(\.mp3|\.MP3\.ogg)',song):
                                                print "# Non converted song " + dir_target + song + " already exists"
                                        else:
                                                print "avconv -y -i \"" + dir + song + "\" -ab 128k -acodec libvorbis \"" + song_ogg + "\""
		else:
			print "# File " + song + " not recognized as a song in the dir " + dir
#		print dir+subdir+'/'


# open the input file with the list of input directories
input_file = open(sys.argv[1],'r')

target = sys.argv[2]

if target[-1:] != '/':
        target = target + '/'

for dir in input_file:
	dir = dir[:-1] # Remove last \n
	if len(dir) > 0: # Ignore empty lines (no comments accepted here)
		convert_all_songs(dir,target+dir)

#ls --group-directories-first ../ > dir

#TODO: Use the computers from enst to offload some tasks (Yes, that will be badly needed. 16gb of music may take more than 6 hours to transcode in a Core Duo)
#TODO: Sync also playlists (though not all)
#TODO: Determine folders that I just want to copy, not transcode, or determine by bitrate.
#TODO: Make a more inteligent way to determine the source and destination folders
#TODO: Calculate the best split of tasks among the cores
#TODO: Deal correctly with early termination of the script and other changes on the fly.
#TODO: Remux or transcode videos too.
#TODO: Assert when ffmpeg fails to transcode (tip: find -type f -size 0)
#TODO: Do not reencode already encoded files
#TODO: Do this directly from the tablet (transfer using the internet?)
#TODO: Keep track of files kept just for storage purposes (Code Geass), so that they don't need to be transcoded.
#TODO: Deal with folders that I don't want to walk into

