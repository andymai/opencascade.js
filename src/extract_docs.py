#!/usr/bin/env python3
"""Parse Doxygen XML output from OCCT headers into a JSON lookup table."""

import json
import os
import subprocess
import xml.etree.ElementTree as ET
from pathlib import Path

OCCT_ROOT = os.environ.get("OCCT_ROOT", "/occt")
BUILD_DIR = os.path.join(os.path.dirname(__file__), "..", "build")
DOCS_JSON = os.path.join(BUILD_DIR, "occt-docs.json")
DOXYGEN_XML = os.path.join(BUILD_DIR, "doxygen-xml")


def run_doxygen():
    """Run Doxygen on OCCT source to produce XML output."""
    doxyfile = os.path.join(BUILD_DIR, "Doxyfile.auto")
    os.makedirs(BUILD_DIR, exist_ok=True)
    with open(doxyfile, "w") as f:
        f.write(f"""
PROJECT_NAME = OCCT
INPUT = {OCCT_ROOT}/src
RECURSIVE = YES
GENERATE_XML = YES
XML_OUTPUT = {DOXYGEN_XML}/xml
GENERATE_HTML = NO
GENERATE_LATEX = NO
EXTRACT_ALL = YES
FILE_PATTERNS = *.hxx *.h
QUIET = YES
""")
    subprocess.run(["doxygen", doxyfile], check=True)


def parse_xml():
    """Parse Doxygen XML into {ClassName: {doc, members: {name: {doc, params}}}}."""
    docs = {}
    xml_dir = os.path.join(DOXYGEN_XML, "xml")
    if not os.path.isdir(xml_dir):
        return docs

    for xml_file in Path(xml_dir).glob("class*.xml"):
        try:
            tree = ET.parse(xml_file)
        except ET.ParseError:
            continue

        root = tree.getroot()
        for compounddef in root.findall(".//compounddef[@kind='class']"):
            class_name = compounddef.findtext("compoundname", "").replace("::", "_")
            if not class_name:
                continue

            class_doc = _text(compounddef.find("briefdescription"))
            members = {}

            for memberdef in compounddef.findall(".//memberdef[@kind='function']"):
                name = memberdef.findtext("name", "")
                if not name:
                    continue
                brief = _text(memberdef.find("briefdescription"))
                detailed = _text(memberdef.find("detaileddescription"))
                params = []
                for param in memberdef.findall("param"):
                    pname = param.findtext("declname", "")
                    ptype = _type_text(param.find("type"))
                    params.append({"name": pname, "type": ptype})

                entry = {"doc": brief or detailed, "params": params}
                if name in members:
                    if "overloads" not in members[name]:
                        members[name] = {"doc": members[name].get("doc", ""), "params": members[name].get("params", []), "overloads": [members[name]]}
                    members[name]["overloads"].append(entry)
                else:
                    members[name] = entry

            if class_doc or members:
                docs[class_name] = {"doc": class_doc, "members": members}

    return docs


def _text(element):
    """Extract normalised plain text from a Doxygen XML element."""
    if element is None:
        return ""
    return " ".join("".join(element.itertext()).split()).strip()


_type_text = _text


def main():
    print("Extracting OCCT Doxygen documentation...")
    run_doxygen()
    docs = parse_xml()
    os.makedirs(os.path.dirname(DOCS_JSON), exist_ok=True)
    with open(DOCS_JSON, "w") as f:
        json.dump(docs, f, indent=2)
    print(f"Wrote {len(docs)} class docs to {DOCS_JSON}")


if __name__ == "__main__":
    main()
