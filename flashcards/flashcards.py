#!/usr/bin/python3
 
# adapted from https://github.com/recantha/EduKit3-RC-Keyboard/blob/master/rc_keyboard.py
 
import sys, termios, tty, os, time

# Ex: https://pypi.org/project/pinyin/
# wget -c https://files.pythonhosted.org/packages/32/95/d2969f1071b7bc0afff407d1d7b4b3f445e8e6b59df7921c9c09e35ee375/pinyin-0.4.0.tar.gz
import pinyin
import pinyin.cedict

from random import randint

def getch():
    fd = sys.stdin.fileno()
    old_settings = termios.tcgetattr(fd)
    try:
        tty.setraw(sys.stdin.fileno())
        ch = sys.stdin.read(1)
 
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, old_settings)
    return ch

button_delay = 0.2

pronoms_fc = [
    '我', '你',
    '他', '她',
    '们', '的',
]

verbs_fc = [
    '是', '有',
    '在', '去',
    '叫', '姓',
    '来', '要',
    '吃', '喝',
    '不', '没',
]

nouns_fc = [
    '饭', '面',
    '茶', '水',
]

misc_fc = [
    '好',
    '喂',
    '什',
    '么',
    '哪',
    '也',
    '很',
    '干',
]

flashcards = pronoms_fc + verbs_fc + nouns_fc + misc_fc

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
    fc = flashcards[lastfc]
    if (memorization==True):
      mistake[lastfc]=False
  else:
    lastfc=randint(0,fclen-1)
    fc = flashcards[lastfc]

memorization=False

fclen = len(flashcards)

memorization=False

print("c to flash a chinese character, p for pinyin or e for english word")
print("a for the answer, l for the link to the stroke order")
print("m for the memorization mode, use i to mark incorrect answers (answers are assumed correct)")
print("Press q to quit")

while True:
    char = getch()
 
    if (char == "q"):
        print("Stop!")
        exit(0)
 
    if (char == "c"):
        get_next_fc()
        print(flashcards[lastfc])
        time.sleep(button_delay)
 
    elif (char == "p"):
        get_next_fc()
        print(pinyin.get(fc))
        time.sleep(button_delay)
 
    elif (char == "e"):
        get_next_fc()
        print(pinyin.cedict.translate_word(fc))
        time.sleep(button_delay)
 
    elif (char == "a"):
        print(fc + ': ' + pinyin.get(fc) + ': ' + ', '.join(pinyin.cedict.translate_word(fc)))
        time.sleep(button_delay)

    elif (char == "l"):
        print("http://www.chinesehideout.com/tools/strokeorder.php?c="+fc)

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
