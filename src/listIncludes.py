#!/usr/bin/python3
"""Output #include directives for all filtered OCCT headers.

Used by setup-pch.sh to generate the master pch.h file.
Reuses the existing filter/filterIncludeFiles.py logic.
"""
import os
from filter.filterIncludeFiles import filterIncludeFile

OCCT_SRC = os.environ.get("OCCT_SRC", "/occt/src/")

for dirpath, _, filenames in os.walk(OCCT_SRC):
    for item in sorted(filenames):
        if item.endswith(".hxx") and filterIncludeFile(item):
            print(f"#include \"{os.path.join(dirpath, item)}\"")
