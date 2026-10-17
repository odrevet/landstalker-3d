#!/usr/bin/env python3
"""Convert a Tiled TMX room into a Godot 3D tilemap scene.

The room's `heightmap` map property (hex coded cells) is parsed and turned
into stacked grid cells for the scene's GridMap:

  - hex digit 0 of each 4-digit value = walkable status (>= 4 means wall/void)
  - hex digit 1 = height (number of cube layers to stack on that column)

Cell encoding notes (verified against Godot 4.7 serialization): the GridMap
`cells` PackedInt32Array is a flat list of int triplets per column:
  (vertical_layer * 65536 + grid_x, grid_z, mesh_item)

The generated scene only contains the map; lights, hero camera and hero are
inherited from the shared scene `res://scenes/level.tscn` instanced by the
template.
"""

import argparse
import os
import re
import sys
import xml.etree.ElementTree as ET

MAP_SIZE = 65536       # 2^16, used by Godot to pack cell coords into one int
MESH_INDEX = 0         # single cube mesh in res://meshlib/cube.tres
WALKABLE_MAX = 4       # first hex digit >= 4 means wall/void

ROOM_NAME_TOKEN = "__ROOM_NAME__"
CELLS_TOKEN = "PackedInt32Array()"


class HeightmapCell:
    def __init__(self, height: int, walkable: int) -> None:
        self.height: int = height
        self.walkable: int = walkable

    def is_void(self) -> bool:
        """Walls without height are room borders: nothing is rendered there."""
        return self.height == 0 and self.walkable >= WALKABLE_MAX


class Heightmap:
    def __init__(self) -> None:
        self.left_offset: int = 0
        self.top_offset: int = 0
        self.cells: list[list[HeightmapCell]] = []

    @classmethod
    def from_tmx_file(cls, tmx_path: str) -> "Heightmap":
        root = ET.parse(tmx_path).getroot()
        properties = {
            prop.get("name"): prop.get("value")
            for prop in root.iter("property")
            if prop.get("name") and prop.get("value") is not None
        }
        heightmap = cls()
        heightmap._load_from_properties(properties)
        heightmap.room_name = root.get("class", "") or os.path.splitext(os.path.basename(tmx_path))[0]
        return heightmap

    def _load_from_properties(self, properties: dict) -> None:
        self.width: int = int(properties.get("hmwidth", 0))
        self.height: int = int(properties.get("hmheight", 0))
        self.left_offset: int = int(properties.get("hmleft", 0))
        self.top_offset: int = int(properties.get("hmtop", 0))

        hex_values = _parse_hex_values(properties.get("heightmap", ""))
        if len(hex_values) != self.width * self.height:
            print(
                f"Warning: expected {self.width * self.height} heightmap cells, got {len(hex_values)}",
                file=sys.stderr,
            )

        self.cells = []
        for y in range(self.height):
            row: list[HeightmapCell] = []
            for x in range(self.width):
                index = y * self.width + x
                if index < len(hex_values):
                    hex_str = hex_values[index].replace("0x", "").replace("0X", "")
                    # Index 0 = walkable status, index 1 = height, rest ignored.
                    walkable = int(hex_str[0], 16)
                    height_val = int(hex_str[1], 16)
                    row.append(HeightmapCell(height=height_val, walkable=walkable))
                else:
                    row.append(HeightmapCell(height=0, walkable=WALKABLE_MAX))
            self.cells.append(row)


def _parse_hex_values(heightmap_str: str) -> list[str]:
    values: list[str] = []
    for fragment in heightmap_str.replace("\n", ",").split(","):
        fragment = fragment.strip()
        if fragment:
            values.append(fragment)
    return values


def build_cells(heightmap: Heightmap) -> list[int]:
    """Build the GridMap cell triplets from the heightmap.

    Heightmap cell (x, y) maps to grid column (x, z=y), filled with one cube
    per ground layer up to the cell height inclusive.
    """
    triplets: list[int] = []
    for y, row in enumerate(heightmap.cells):
        for x, cell in enumerate(row):
            if cell.is_void():
                continue
            for layer in range(cell.height + 1):
                triplets.extend((x + layer * MAP_SIZE, y, MESH_INDEX))
    return triplets


def render_scene(template_path: str, room_name: str, cells: list[int], heightmap: Heightmap) -> str:
    with open(template_path, "r") as file:
        content = file.read()

    content = content.replace(ROOM_NAME_TOKEN, room_name)
    content = content.replace(CELLS_TOKEN, "PackedInt32Array(" + ", ".join(str(v) for v in cells) + ")")
    content = re.sub(
        r"metadata/hm_left = \d+", f"metadata/hm_left = {heightmap.left_offset}", content
    )
    content = re.sub(
        r"metadata/hm_top = \d+", f"metadata/hm_top = {heightmap.top_offset}", content
    )
    content = re.sub(
        r"metadata/hm_width = \d+", f"metadata/hm_width = {heightmap.width}", content
    )
    content = re.sub(
        r"metadata/hm_height = \d+", f"metadata/hm_height = {heightmap.height}", content
    )
    return content


def convert_tmx_to_tscn(tmx_path: str, template_path: str, output_path: str, room_name: str | None) -> str:
    heightmap = Heightmap.from_tmx_file(tmx_path)
    name = room_name or heightmap.room_name
    cells = build_cells(heightmap)
    scene = render_scene(template_path, name, cells, heightmap)

    os.makedirs(os.path.dirname(output_path) or ".", exist_ok=True)
    with open(output_path, "w") as file:
        file.write(scene)

    occupied = sum(1 for row in heightmap.cells for cell in row if not cell.is_void())
    print(
        f"{os.path.basename(tmx_path)} -> {output_path}: "
        f"{heightmap.width}x{heightmap.height} heightmap, {occupied} terrain columns, {len(cells) // 3} grid cells"
    )
    return output_path


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("tmx_file", help="path to the room TMX file")
    parser.add_argument("template_file", help="path to the scene template used as a base")
    parser.add_argument("output_file", help="path of the generated .tscn scene")
    parser.add_argument("--name", help="root node/room name (default: TMX class or file stem)")
    args = parser.parse_args()

    try:
        convert_tmx_to_tscn(args.tmx_file, args.template_file, args.output_file, args.name)
    except FileNotFoundError as e:
        print(f"Error: file not found - {e.filename}", file=sys.stderr)
        sys.exit(1)
    except ET.ParseError as e:
        print(f"Error: cannot parse TMX - {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
