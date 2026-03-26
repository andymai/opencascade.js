#!/usr/bin/python3

import os
import subprocess
import json
import multiprocessing
from itertools import chain
import yaml
import shutil
from cerberus import Validator
from argparse import ArgumentParser
from Common import OCJS_ROOT, getFlatIncludePaths, PCH_FILE, WASM_EXCEPTION_FLAGS
from filter.filterPackages import filterPackages


def verifyBinding(binding, libraryBasePath) -> bool:
  for dirpath, dirnames, filenames in os.walk(libraryBasePath + "/bindings"):
    for item in filenames:
      if item.endswith(".cpp.o") and binding["symbol"] == item[:-6]:
        return True
  return False

def verifyBindings(bindings, libraryBasePath) -> bool:
  for binding in bindings:
    if not verifyBinding(binding, libraryBasePath):
      print("WARNING: binding " + binding["symbol"] + " not found, skipping")

def shouldProcessSymbol(symbol: str, bindings) -> bool:
  if len(bindings) == 0:
    return True
  entry = next((b for b in bindings if b["symbol"] == symbol), None)
  if not entry is None:
    return True
  return False

def runBuild(build, libraryBasePath):
  def getAdditionalBindCodeO():
    if "additionalBindCode" in build:
      os.makedirs(libraryBasePath + "/additionalBindCode", exist_ok=True)
      additionalBindCodeFileName = libraryBasePath + "/additionalBindCode/" + build["name"] + ".cpp"
      f = open(additionalBindCodeFileName, "w")
      f.write(build["additionalBindCode"])
      f.close()
      print("building " + additionalBindCodeFileName)
      OPT_LEVEL = os.environ.get("OCJS_OPT", "-O0")
      USE_LTO = os.environ.get("OCJS_LTO", "0") == "1"
      exception_flags = WASM_EXCEPTION_FLAGS
      command = [
        "emcc",
        "-std=c++17",
        *(["-flto"] if USE_LTO else []),
        *exception_flags,
        "-DIGNORE_NO_ATOMICS=1",
        "-DOCCT_NO_PLUGINS",
        "-frtti",
        "-DHAVE_RAPIDJSON",
        OPT_LEVEL,
        *(["-pthread"] if os.environ["threading"] == "multi-threaded" else []),
        *(["-include-pch", PCH_FILE] if os.path.exists(PCH_FILE) else []),
        *["-I" + p for p in getFlatIncludePaths()],
        "-c", additionalBindCodeFileName,
      ]
      subprocess.check_call([
        *command,
        "-o", additionalBindCodeFileName + ".o",
      ])
      return additionalBindCodeFileName + ".o"
    else:
      return None
  additionalBindCodeO = getAdditionalBindCodeO()
  print("Running build: " + build["name"], flush=True)
  bindingsO = []
  for dirpath, dirnames, filenames in os.walk(libraryBasePath + "/bindings"):
    rel_parts = dirpath.replace(libraryBasePath + "/bindings/", "").split("/")
    skip = any(not filterPackages(p) for p in rel_parts if p)
    if skip:
      dirnames.clear()
      continue
    for item in filenames:
      if item.endswith(".cpp.o") and shouldProcessSymbol(item[:-6], build["bindings"]):
        bindingsO.append(dirpath + "/" + item)
  sourcesO = []
  for dirpath, dirnames, filenames in os.walk(libraryBasePath + "/sources"):
    rel_parts = dirpath.replace(libraryBasePath + "/sources/", "").split("/")
    skip = any(not filterPackages(p) for p in rel_parts if p)
    if skip:
      dirnames.clear()
      continue
    for item in filenames:
      if item in [
        "XBRepMesh.o",
      ]:
        continue
      if item.endswith(".o"):
        sourcesO.append(dirpath + "/" + item)
  # Separate custom code bindings (myMain.h/) from standard OCCT bindings.
  # Custom bindings use EMSCRIPTEN_BINDINGS() constructors that LTO can strip.
  # Wrap them with --whole-archive to prevent this.
  customBindingsO = [o for o in bindingsO if "/myMain.h/" in o]
  standardBindingsO = [o for o in bindingsO if "/myMain.h/" not in o]

  patchDir = os.path.join(os.path.dirname(__file__), "patches")
  linkCmd = [
    "emcc", "-lembind",
    *([additionalBindCodeO] if additionalBindCodeO else []),
    *standardBindingsO,
    # Prevent LTO from stripping EMSCRIPTEN_BINDINGS() constructors in custom code
    *(["-Wl,--whole-archive"] + customBindingsO + ["-Wl,--no-whole-archive"] if customBindingsO else []),
    *sourcesO,
    "-o", os.getcwd() + "/" + build["name"],
    *(["-pthread"] if os.environ["threading"] == "multi-threaded" else []),
    "--post-js", os.path.join(patchDir, "symbol_dispose.js"),
    "--post-js", os.path.join(patchDir, "string_enums.js"),
    *build["emccFlags"],
  ]
  print(f"Linking {len(bindingsO)} bindings + {len(sourcesO)} sources ...", flush=True)
  subprocess.check_call(linkCmd)

  wasmFile = os.getcwd() + "/" + os.path.splitext(build["name"])[0] + ".wasm"
  emsdk = os.environ.get("EMSDK", "")
  wasmOptPath = shutil.which("wasm-opt") or (os.path.join(emsdk, "upstream", "bin", "wasm-opt") if emsdk else None)
  if os.path.exists(wasmFile) and wasmOptPath and os.path.exists(wasmOptPath):
    sizeBefore = os.path.getsize(wasmFile)
    print(f"Running wasm-opt on {wasmFile} ({sizeBefore / (1024*1024):.1f} MB)...", flush=True)
    wasmOptFlags = [wasmOptPath, "-O3", "--strip-debug", "--strip-producers", "--enable-mutable-globals", "--enable-bulk-memory", "--enable-sign-ext", "--enable-nontrapping-float-to-int", "--enable-exception-handling"]
    if os.environ.get("threading") == "multi-threaded":
      wasmOptFlags.append("--enable-threads")
    wasmOptFlags.extend([wasmFile, "-o", wasmFile])
    subprocess.check_call(wasmOptFlags)
    sizeAfter = os.path.getsize(wasmFile)
    reduction = (1 - sizeAfter / sizeBefore) * 100 if sizeBefore > 0 else 0
    print(f"wasm-opt: {sizeBefore / (1024*1024):.1f} MB -> {sizeAfter / (1024*1024):.1f} MB ({reduction:.1f}% reduction)", flush=True)

  print("Build finished", flush=True)


def main():
  from generateBindings import generateCustomCodeBindings
  from compileBindings import compileCustomCodeBindings

  parser = ArgumentParser()
  parser.add_argument(dest="filename", help="Custom build input file (.yml)", metavar="FILE.yml")
  args = parser.parse_args()
  libraryBasePath = OCJS_ROOT + "/build"

  buildConfig = yaml.safe_load(open(args.filename, "r"))
  from customBuildSchema import schema
  v = Validator(schema)
  if not v.validate(buildConfig, schema):
    raise Exception(v.errors)
  buildConfig = v.normalized(buildConfig)

  if os.path.isdir(libraryBasePath + "/bindings/myMain.h"):
    shutil.rmtree(libraryBasePath + "/bindings/myMain.h")

  print("Generating custom code bindings...", flush=True)
  generateCustomCodeBindings(buildConfig["additionalCppCode"])
  print("Compiling custom code bindings...", flush=True)
  compileCustomCodeBindings({
    "threading": os.environ['threading'],
  })
  print("Custom code bindings done.", flush=True)

  verifyBindings(buildConfig["mainBuild"]["bindings"], libraryBasePath)
  for extraBuild in buildConfig["extraBuilds"]:
    verifyBindings(extraBuild, libraryBasePath)
  print("All bindings verified.", flush=True)

  typescriptDefinitions = []
  allBindings = list(chain(buildConfig["mainBuild"]["bindings"], *list(map(lambda x: x["bindings"], buildConfig["extraBuilds"]))))
  for dirpath, dirnames, filenames in os.walk(libraryBasePath + "/bindings"):
    rel_parts = dirpath.replace(libraryBasePath + "/bindings/", "").split("/")
    skip = any(not filterPackages(p) for p in rel_parts if p)
    if skip:
      dirnames.clear()
      continue
    for item in filenames:
      if item.endswith(".d.ts.json") and shouldProcessSymbol(item[:-10], allBindings):
        f = open(dirpath + "/" + item, "r")
        typescriptDefinitions.append(json.loads(f.read()))

  runBuild(buildConfig["mainBuild"], libraryBasePath)
  for extraBuild in buildConfig["extraBuilds"]:
    runBuild(extraBuild, libraryBasePath)

  if buildConfig["generateTypescriptDefinitions"]:
    typescriptDefinitionOutput = ""
    typescriptExports = []
    for dts in typescriptDefinitions:
      typescriptDefinitionOutput += dts[".d.ts"]
      for export in dts["exports"]:
        typescriptExports.append({
          "export": export,
          "kind": dts["kind"],
        })

    fsTemplatePath = os.path.join(os.path.dirname(__file__), "emscripten_fs.d.ts.tmpl")
    with open(fsTemplatePath, "r") as f:
      typescriptDefinitionOutput += f.read()

    exportLines = ";\n  ".join(
      x["export"] + (": typeof " + x["export"] if x["kind"] == "class" else ": " + x["export"])
      for x in typescriptExports
    )
    typescriptDefinitionOutput += (
      "\nexport type OpenCascadeInstance = {FS: typeof FS} & {\n  "
      + exportLines + ";\n"
      + "};\n\n"
      + "declare function init(): Promise<OpenCascadeInstance>;\n\n"
      + "export default init;\n"
    )

    typescriptDefinitionsFile = open(os.getcwd() + "/" + os.path.splitext(buildConfig["mainBuild"]["name"])[0] + ".d.ts", "w")
    typescriptDefinitionsFile.write(typescriptDefinitionOutput)
    print("TypeScript definitions written.", flush=True)

if __name__ == "__main__":
  multiprocessing.set_start_method("fork")
  main()
