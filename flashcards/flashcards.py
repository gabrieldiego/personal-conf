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

def get_new_fc():
    global lastfc
    global fc
    lastfc=randint(0,fclen-1)
    fc = flashcards[lastfc]

fclen = len(flashcards)
get_new_fc()

print("c to flash a chinese character, p for pinyin or e for english word")
print("a for the answer, l for the link to the stroke order")
print("Press q to quit")

while True:
    char = getch()
 
    if (char == "q"):
        print("Stop!")
        exit(0)
 
    if (char == "c"):
        get_new_fc()
        print(flashcards[lastfc])
        time.sleep(button_delay)
 
    elif (char == "p"):
        get_new_fc()
        print(pinyin.get(fc))
        time.sleep(button_delay)
 
    elif (char == "e"):
        get_new_fc()
        print(pinyin.cedict.translate_word(fc))
        time.sleep(button_delay)
 
    elif (char == "a"):
        print(fc + ': ' + pinyin.get(fc) + ': ' + ', '.join(pinyin.cedict.translate_word(fc)))
        time.sleep(button_delay)

    elif (char == "l"):
        print("http://www.chinesehideout.com/tools/strokeorder.php?c="+fc)

