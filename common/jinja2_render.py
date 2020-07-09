#!/usr/bin/env python3

import jinja2
import os
import sys

template = jinja2.Template(sys.stdin.read())
print(template.render(**os.environ))
