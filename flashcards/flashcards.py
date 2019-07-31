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
        '我',
        '你',
        '他',
        '她',
        '们',
        '的',
]

verbs_fc = [
        '是',
        '有',
        '在',
        '要',
        '叫',
        '姓',
        '不',
        '没'
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
        '嘛'
]

#        ['', '', ''],

flashcards = pronoms_fc + verbs_fc + misc_fc


fclen = len(flashcards)
lastfc=0

print("c to flash a chinese character, p for pinyin or e for english word")
print("a for the answer")
print("Press q to quit")

while True:
    char = getch()
 
    if (char == "q"):
        print("Stop!")
        exit(0)
 
    if (char == "c"):
        lastfc=randint(0,fclen-1)
        print(flashcards[lastfc])
        time.sleep(button_delay)
 
    elif (char == "p"):
        lastfc=randint(0,fclen-1)
        print(pinyin.get(flashcards[lastfc]))
        time.sleep(button_delay)
 
    elif (char == "e"):
        lastfc=randint(0,fclen-1)
        print(pinyin.cedict.translate_word(flashcards[lastfc]))
        time.sleep(button_delay)
 
    elif (char == "a"):
        fc = flashcards[lastfc]
        print(fc + ': ' + pinyin.get(fc) + ': ' + ', '.join(pinyin.cedict.translate_word(fc)))
        time.sleep(button_delay)

