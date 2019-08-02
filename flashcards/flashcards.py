#!/usr/bin/python3
 
# adapted from https://github.com/recantha/EduKit3-RC-Keyboard/blob/master/rc_keyboard.py
 
import sys, termios, tty, os, time

# Ex: https://pypi.org/project/pinyin/
# wget -c https://files.pythonhosted.org/packages/32/95/d2969f1071b7bc0afff407d1d7b4b3f445e8e6b59df7921c9c09e35ee375/pinyin-0.4.0.tar.gz
import pinyin
import pinyin.cedict

from random import randint

## Flashcards

class Flashcard:
  def __init__(self, hanzi):
    self.hanzi = hanzi
    self.pinyin = pinyin.get(hanzi)
    self.translation = ', '.join(pinyin.cedict.translate_word(hanzi))

  def description(self):
    return self.hanzi + ": " + self.pinyin + ": " + self.translation

  def __str__(self):
    return self.description()

  def __repr__(self):
    return self.description()
  
  def set_pinyin(self, new_pinyin):
    self.pinyin = new_pinyin

  def set_translation(self, new_translation):
    self.translation = new_translation

  def get_hanzi(self):
    return self.hanzi

  def get_pinyin(self):
    return self.pinyin

  def get_translation(self):
    return self.translation

def load_flashcards_from_file(filename):
  flashcards=[]
  f=open(filename)

  for l in f.read().splitlines():
    ll = len(l)
    if(ll > 0):
      ls = l.split(':')
      lls = len(ls)
      hanzi=ls[0]
      fc=Flashcard(hanzi)
      if(lls > 1 and len(ls[1]) > 0):
        fc.set_pinyin(ls[1])

      if(lls > 2 and len(ls[2]) > 0):
        fc.set_translation(ls[2])

      flashcards.append(fc)

  f.close()

  return flashcards

def list_all_flashcards(flashcards):
  for fc in flashcards:
    print(fc.description())

flashcards=[]

for arg in sys.argv[1:]:
  flashcards += load_flashcards_from_file(arg)

def find_next_circular(l,val,cur_idx):
  rotated_l=l[cur_idx:]+l[:cur_idx]
  try:
    idx = rotated_l.index(val)
  except ValueError:
    return -1

  return (idx+cur_idx) % len(l)

lastfc=-1

def get_next_fc():
  global lastfc
  global fc

  if (memorization==True):
    lastfc+=1
    lastfc = find_next_circular(mistake,True,lastfc)
    fc = flashcards[lastfc].get_hanzi()
    if (memorization==True):
      mistake[lastfc]=False
  else:
    lastfc=randint(0,fclen-1)
    fc = flashcards[lastfc].get_hanzi()

memorization=False

fclen = len(flashcards)

memorization=False

## Main loop

button_delay = 0.2

def getch():
    fd = sys.stdin.fileno()
    old_settings = termios.tcgetattr(fd)
    try:
        tty.setraw(sys.stdin.fileno())
        ch = sys.stdin.read(1)
 
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, old_settings)
    return ch


print("c to flash a chinese character, p for pinyin or e for english word")
print("a for the answer, l for the link to the stroke order")
print("m for the memorization mode, use i to mark incorrect answers (answers are assumed correct)")
print("f to list all flashcards on the deck")
print("Press q to quit")

while True:
    char = getch()
 
    if (char == "q"):
        print("Stop!")
        exit(0)
 
    if (char == "c"):
        get_next_fc()
        print(flashcards[lastfc].get_hanzi())
        time.sleep(button_delay)
 
    elif (char == "p"):
        get_next_fc()
        print(flashcards[lastfc].get_pinyin())
        time.sleep(button_delay)
 
    elif (char == "e"):
        get_next_fc()
        print(flashcards[lastfc].get_translation())
        time.sleep(button_delay)
 
    elif (char == "a"):
        print(flashcards[lastfc].description())
        time.sleep(button_delay)

    elif (char == "l"):
        print("http://www.chinesehideout.com/tools/strokeorder.php?c="+flashcards[lastfc].get_hanzi())

    elif (char == "f"):
        list_all_flashcards(flashcards)

    elif (char == "m"):
        memorization=not memorization
        if(memorization):
            print("Memorization mode on")
            lastfc=-1
            mistake=[True for i in range(fclen)]
        else:
            print("Memorization mode off")

    elif (char == "i"):
        if (memorization==True):
            print(fc + " marked as a mistake")
            mistake[lastfc]=True
