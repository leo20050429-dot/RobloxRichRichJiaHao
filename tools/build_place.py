"""把 src/ 打包成 Roblox Studio 可以直接開啟的 .rbxlx 檔。

用法：python tools/build_place.py
輸出：build/StardustPawn.rbxlx

規則和 Rojo 一樣（讀 default.project.json）：
  X.server.luau → Script
  X.client.luau → LocalScript
  X.luau        → ModuleScript
  資料夾         → Folder
之後裝了 Rojo 也可以直接用 `rojo serve` / `rojo build`，不需要這個腳本。
"""

import json
import sys
from pathlib import Path
from xml.sax.saxutils import escape

ROOT = Path(__file__).resolve().parent.parent

SERVICE_CHILD_CLASSES = {
    "StarterPlayerScripts": "StarterPlayerScripts",
    "StarterCharacterScripts": "StarterCharacterScripts",
}

# 一律寫出的服務（Studio 開檔時才找得到這些容器）
BASE_SERVICES = [
    "Workspace",
    "Players",
    "Lighting",
    "ReplicatedStorage",
    "ServerScriptService",
    "ServerStorage",
    "StarterGui",
    "StarterPack",
    "StarterPlayer",
    "SoundService",
    "Chat",
]


class Builder:
    def __init__(self):
        self.next_ref = 0

    def ref(self):
        self.next_ref += 1
        return f"RBX{self.next_ref:08X}"

    def item(self, class_name, name, children, source=None, indent=1):
        pad = "  " * indent
        lines = [f'{pad}<Item class="{class_name}" referent="{self.ref()}">', f"{pad}  <Properties>"]
        lines.append(f'{pad}    <string name="Name">{escape(name)}</string>')
        if source is not None:
            safe = source.replace("]]>", "]]]]><![CDATA[>")
            lines.append(f'{pad}    <ProtectedString name="Source"><![CDATA[{safe}]]></ProtectedString>')
        lines.append(f"{pad}  </Properties>")
        for child in children:
            lines.append(child(indent + 1))
        lines.append(f"{pad}</Item>")
        return "\n".join(lines)


def script_node(builder, path: Path):
    name = path.name
    for suffix, cls in ((".server.luau", "Script"), (".client.luau", "LocalScript"), (".luau", "ModuleScript")):
        if name.endswith(suffix):
            inst_name = name[: -len(suffix)]
            source = path.read_text(encoding="utf-8")
            return lambda indent: builder.item(cls, inst_name, [], source, indent)
    return None


def folder_children(builder, directory: Path):
    nodes = []
    for entry in sorted(directory.iterdir(), key=lambda p: p.name):
        if entry.is_dir():
            nodes.append(dir_node(builder, entry, entry.name))
        else:
            node = script_node(builder, entry)
            if node:
                nodes.append(node)
    return nodes


def dir_node(builder, directory: Path, name: str):
    children = folder_children(builder, directory)
    return lambda indent: builder.item("Folder", name, children, None, indent)


def tree_node(builder, name, spec, class_name=None):
    """把 project.json 裡的一個節點轉成 XML。"""
    if "$path" in spec:
        path = ROOT / spec["$path"]
        if path.is_dir():
            children = folder_children(builder, path)
            cls = class_name or "Folder"
            return lambda indent: builder.item(cls, name, children, None, indent)
        node = script_node(builder, path)
        if node is None:
            raise SystemExit(f"不認得的檔案：{path}")
        return node
    children = [
        tree_node(builder, child, child_spec, SERVICE_CHILD_CLASSES.get(child))
        for child, child_spec in spec.items()
        if not child.startswith("$")
    ]
    cls = spec.get("$className") or class_name or name
    return lambda indent: builder.item(cls, name, children, None, indent)


def main():
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    project = json.loads((ROOT / "default.project.json").read_text(encoding="utf-8"))
    tree = project["tree"]
    builder = Builder()

    service_names = [k for k in tree if not k.startswith("$")]
    nodes = []
    for service in BASE_SERVICES:
        if service not in service_names:
            nodes.append(tree_node(builder, service, {}))
    for service in service_names:
        nodes.append(tree_node(builder, service, tree[service]))

    body = "\n".join(node(1) for node in nodes)
    xml = f'<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" version="4">\n{body}\n</roblox>\n'

    out_dir = ROOT / "build"
    out_dir.mkdir(exist_ok=True)
    out = out_dir / f"{project['name']}.rbxlx"
    out.write_text(xml, encoding="utf-8")
    print(f"已輸出 {out.relative_to(ROOT)}（{len(xml.encode('utf-8')):,} bytes）")


if __name__ == "__main__":
    sys.exit(main())
