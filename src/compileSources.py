#!/usr/bin/python3

import os
import subprocess
import multiprocessing

from filter.filterSourceFiles import filterSourceFile
from filter.filterPackages import filterPackages

from argparse import ArgumentParser

libraryBasePath = "/opencascade.js/build/sources"

# Potentially problematic packages, when used with dynamic linking
# These files contain function pointer definitions and header files and are therefore likely to cause problems.
# https://github.com/emscripten-core/emscripten/issues/13241
# "AdvApp2Var"
# "BRepGProp"
# "BRepMesh"
# "BSplSLib"
# "CPnts"
# "DDF"
# "Draw"
# "Graphic3d"
# "IFSelect"
# "Interface"
# "MoniTool"
# "NCollection"
# "OpenGl"
# "OSD"
# "ShapeProcess"
# "Standard"
# "StdObjMgt"
# "TDF

sourceBasePath = "/occt/src/"

includePaths = []
includePaths.extend([
  "/rapidjson/include",
  "/freetype/include/freetype",
  "/freetype/include",
])
for dirpath, dirnames, filenames in os.walk(os.path.join(sourceBasePath)):
  includePaths.append(dirpath)

def buildObjectFiles(file, args):
  relativeFile = file.replace(sourceBasePath, "")
  try:
    os.makedirs(libraryBasePath + "/" + os.path.dirname(relativeFile))
  except Exception:
    pass
  command = [
    "emcc",
    "-fwasm-exceptions",
    "-DIGNORE_NO_ATOMICS=1",
    "-DOCCT_NO_PLUGINS",
    "-frtti",
    "-DHAVE_RAPIDJSON", 
    "-Os",
    # "-g3",
    # "-gsource-map",
    # "--source-map-base=http://localhost:8080",
    # "-fPIC",
    *(["-pthread"] if args["threading"] == "multi-threaded" else []),
    *list(map(lambda x: "-I" + x, includePaths)),
    "-c",
    file,
  ]

  if not os.path.exists(libraryBasePath + "/" + relativeFile + ".o"):
    print("Building " + relativeFile)
    result = subprocess.call([
      *command,
      "-o", libraryBasePath + "/" + relativeFile + ".o",
      ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if result != 0:
      pass  # Skip failed sources silently - custom builds will recompile what they need
  else:
    print(relativeFile + ".o already exists, skipping")

import re

def parseCmakeList(filepath):
  """Parse a CMake set() command and return the list of values."""
  with open(filepath, "r") as f:
    content = f.read()
  # Match: set(VARNAME val1 val2 ...) across multiple lines
  match = re.search(r'set\(\s*\w+\s+(.*?)\)', content, re.DOTALL)
  if not match:
    return []
  return [v.strip() for v in match.group(1).split() if v.strip()]

# Build toolkit→packages mapping from PACKAGES.cmake files (V8 structure)
# V8 layout: src/Module/Toolkit/PACKAGES.cmake → lists packages
# V8 layout: src/Module/Toolkit/Package/ → contains source files
allToolkits = {}
for dirpath, dirnames, filenames in os.walk(sourceBasePath):
  if "PACKAGES.cmake" in filenames:
    toolkitName = os.path.basename(dirpath)
    allToolkits[toolkitName] = parseCmakeList(os.path.join(dirpath, "PACKAGES.cmake"))

def getToolkitByPackageName(inputPackageName):
  for toolkitName, packages in allToolkits.items():
    if inputPackageName in packages:
      return toolkitName
  return ""

filesToBuild = []
for dirpath, dirnames, filenames in os.walk(sourceBasePath):
  # In V8, package dirs are at: src/Module/Toolkit/Package/
  # The package name is the last component of the path
  packageName = os.path.basename(dirpath)
  toolkitName = getToolkitByPackageName(packageName)
  for item in filenames:
    if not filterPackages(packageName) or not filterPackages(toolkitName):
      continue
    if filterSourceFile(dirpath + "/" + item):
      filesToBuild.append(dirpath + "/" + item)

if __name__ == "__main__":
  parser = ArgumentParser()
  parser.add_argument(dest="threading", choices=["single-threaded", "multi-threaded"], help="Build in single vs. multi-threaded mode")
  args = parser.parse_args()

  try:
    os.makedirs(libraryBasePath)
  except Exception:
    pass

  def myBuildFunction(x):
    buildObjectFiles(x, {
      "threading": args.threading,
    })

  with multiprocessing.Pool(processes=multiprocessing.cpu_count()) as p:
    p.map(myBuildFunction, filesToBuild)
