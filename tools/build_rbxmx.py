#!/usr/bin/env python3
"""Bangun file .rbxmx (bisa di-Insert from File di Roblox Studio) dari folder roblox/server dan roblox/client.
Pemakaian: python3 tools/build_rbxmx.py
  roblox/server -> roblox/SmartAC_Server.rbxmx  (taruh di ServerScriptService)
  roblox/client -> roblox/SmartAC_Client.rbxmx  (taruh di StarterPlayer > StarterPlayerScripts)
Aturan nama: X.server.lua = Script, X.client.lua = LocalScript, X.lua = ModuleScript, folder = Folder.
"""
import os, sys
from xml.sax.saxutils import escape

counter = 0
def ref():
    global counter
    counter += 1
    return f"RBX{counter:04d}"

def cdata(src: str) -> str:
    return "<![CDATA[" + src.replace("]]>", "]]]]><![CDATA[>") + "]]>"

def script_item(name, cls, src, indent):
    pad = "  " * indent
    return (f'{pad}<Item class="{cls}" referent="{ref()}">\n{pad}  <Properties>\n'
            f'{pad}    <string name="Name">{escape(name)}</string>\n'
            f'{pad}    <ProtectedString name="Source">{cdata(src)}</ProtectedString>\n'
            f'{pad}  </Properties>\n{pad}</Item>\n')

def folder_item(path, name, indent):
    pad = "  " * indent
    out = (f'{pad}<Item class="Folder" referent="{ref()}">\n{pad}  <Properties>\n'
           f'{pad}    <string name="Name">{escape(name)}</string>\n{pad}  </Properties>\n')
    for entry in sorted(os.listdir(path), key=lambda e: (not os.path.isdir(os.path.join(path, e)), e)):
        full = os.path.join(path, entry)
        if os.path.isdir(full):
            out += folder_item(full, entry, indent + 1)
        elif entry.endswith(".lua"):
            src = open(full, encoding="utf-8").read()
            if entry.endswith(".server.lua"):
                out += script_item(entry[:-len(".server.lua")], "Script", src, indent + 1)
            elif entry.endswith(".client.lua"):
                out += script_item(entry[:-len(".client.lua")], "LocalScript", src, indent + 1)
            else:
                out += script_item(entry[:-len(".lua")], "ModuleScript", src, indent + 1)
    out += f"{pad}</Item>\n"
    return out

def build(src_dir, root_name, out_file):
    xml = '<roblox version="4">\n' + folder_item(src_dir, root_name, 1) + "</roblox>\n"
    with open(out_file, "w", encoding="utf-8") as f:
        f.write(xml)
    print("OK ->", out_file)

if __name__ == "__main__":
    base = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "roblox")
    build(os.path.join(base, "server"), "SmartAC", os.path.join(base, "SmartAC_Server.rbxmx"))
    build(os.path.join(base, "client"), "SmartACClient", os.path.join(base, "SmartAC_Client.rbxmx"))
