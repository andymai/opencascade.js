from filter.filterIncludeFiles import filterIncludeFile
from typing import Set
import os

occtBasePath = "/occt/src/"

def getGlobalIncludes() -> Set[str]:
  includeFiles = list()
  additionalIncludePaths = list()
  # Exclude GTests directories from include paths (not needed for binding/compilation)
  excludeDirs = {"GTests"}
  for dirpath, dirnames, filenames in os.walk(occtBasePath):
    dirnames[:] = [d for d in dirnames if d not in excludeDirs]
    additionalIncludePaths.append(str(dirpath))
    for item in filenames:
      if filterIncludeFile(item):
        includeFiles.append(str(os.path.join(dirpath, item)))
  return [includeFiles, additionalIncludePaths]

[ocIncludeFiles, ocIncludePaths] = getGlobalIncludes()

additionalIncludePaths = [
  "/rapidjson/include",
  "/freetype/include/freetype",
  "/freetype/include",
]

includePathArgs = \
  list(dict.fromkeys(map(lambda x: "-I" + x, ocIncludePaths))) + \
  list(map(lambda x: "-I" + x, [
    "/emsdk/upstream/emscripten/system/include/",
    "/usr/lib/gcc/x86_64-linux-gnu/" + sorted(next(os.walk('/usr/lib/gcc/x86_64-linux-gnu/'))[1])[-1] + "/include-fixed/",
    "/emsdk/upstream/emscripten/system/lib/libcxx/include/",
    "/emsdk/upstream/lib/clang/" + next(os.walk('/emsdk/upstream/lib/clang/'))[1][0] + "/include/",
    "/emsdk/upstream/emscripten/system/lib/libcxx/include/__support/newlib/"
  ])) + \
  list(map(lambda x: "-I" + x, ocIncludePaths + additionalIncludePaths))
  