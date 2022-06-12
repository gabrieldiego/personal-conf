#!/usr/bin/python

import re
from datetime import datetime

row_list=[]

#EVGo loop
line_list = []

line_number = 0
line_list.append([])

with open("evgo.txt") as file:
	for line in file:
		if(re.match(".*Date.*", line)):
			line_number+=1
			line_list.append([])
		line_list[line_number].append(line)

line_list.pop(0)

for entry in line_list:
	date_str = entry[1][:10]

	i=0
	for s in entry:
		if(re.match(".*\$.*", s)):
			break
		i+=1

	if(len(entry)==i):
		continue

	cost_energy_str = entry[i]

#	print date_str, cost_energy_str

	date = datetime.strptime(date_str,'%m/%d/%Y')

	date_f = date.strftime('%Y-%m-%d')

	cost_str = cost_energy_str.split(' ')[0][1:]
	energy_str = cost_energy_str.split(' ')[1][1:]

#	print cost_str
#	print energy_str

	row_list.append([date_f, energy_str, cost_str])

#	print date_f, "\t\t", energy_str, "\t", cost_str



def sort_key(e):
	return e[0]

row_list.sort(key=sort_key)

i=0
while(i<len(row_list)):
	if(i>=1 and row_list[i][0] == row_list[i-1][0]):
		row_list[i-1][1] += " + " + row_list[i][1]
		row_list[i-1][2] += " + " + row_list[i][2]
		del row_list[i]
	else:
		i+=1


for row in row_list:
	print row[0], "\t\t=", row[1], "\t=", row[2]

