#!/usr/bin/python
# -*- coding: utf-8 -*-

import pinyin
from sys import argv

if len(argv) == 2:
  print pinyin.get(argv[1])
else:
  print "Usage: " +argv[0] + " <hanzi>"

