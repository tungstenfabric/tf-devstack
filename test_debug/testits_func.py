import os
import os.path


def read(fname):
    inf = open(os.path.join(os.path.dirname(__file__), fname))
    out = "\n" + inf.read().replace("\r\n", "\n")
    inf.close()
    return out


ex = "nothing here dude"
try:
    print('='*30)
    print(read("appdirs.py"))
    print('='*30)
except Exception as ex:
    print("Oh my God !! This is Error !!")
    print(ex)
    print('='*30)
