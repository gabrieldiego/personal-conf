#!/usr/bin/python3
 
# adapted from https://github.com/recantha/EduKit3-RC-Keyboard/blob/master/rc_keyboard.py
 
import sys, termios, tty, os, time

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
        ['我', 'wǒ', 'I'],
        ['你', 'nǐ', 'you'],
        ['他', 'tā', 'he'],
        ['她', 'tā', 'she'],
        ['们', 'men', 'pronom plural (we, you, they)'],
        ['的', 'de','possessive (my, your)'],
]

verbs_fc = [
        ['是', 'shì', 'to be'],
        ['要', 'yào', 'to want'],
        ['叫', 'jiào', 'to be called (name)'],
        ['有', 'yǒu', 'to have'],
        ['没有', 'méiyǒu', 'to not have'],
]

misc_fc = [
        ['不', 'bù', 'not'],
        ['好', 'hǎo', 'good'],
        ['喂', 'wèi', 'hello'],
        ['什么', 'shénme', 'what'],
        ['~在哪', 'zài nǎ', 'where is ~'],
        ['也', 'yě', 'also'],
        ['很', 'hěn', 'very'],
        ['你在干嘛', 'Nǐ zài gàn ma', 'What are you doing?'],
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
        print(flashcards[lastfc][0])
        time.sleep(button_delay)
 
    elif (char == "p"):
        lastfc=randint(0,fclen-1)
        print(flashcards[lastfc][1])
        time.sleep(button_delay)
 
    elif (char == "e"):
        lastfc=randint(0,fclen-1)
        print(flashcards[lastfc][2])
        time.sleep(button_delay)
 
    elif (char == "a"):
        print(flashcards[lastfc])
        time.sleep(button_delay)
