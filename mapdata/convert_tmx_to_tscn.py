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
NO_DESTINATION = 65535 # "no warp destination" sentinel used by the source data

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


class RoomData:
    """Everything we need from a room TMX: heightmap, naming and warps."""

    def __init__(self) -> None:
        self.heightmap: Heightmap = Heightmap()
        self.room_name: str = ""
        self.room_label: str = ""
        self.room_number: int = -1
        self.room_map: str = ""
        self.warp_fall_dest: int = -1
        self.warp_climb_dest: int = -1
        self.warps: list[dict] = []
        self.entities: list[dict] = []

    @classmethod
    def from_tmx_file(cls, tmx_path: str) -> "RoomData":
        root = ET.parse(tmx_path).getroot()
        properties = _load_map_properties(root)

        data = cls()
        data.heightmap._load_from_properties(properties)

        label = properties.get("RoomLabel", "")
        data.room_label = label or root.get("class", "") or _file_stem(tmx_path)
        data.room_name = properties.get("RoomName", "") or data.room_label
        data.room_number = int(properties.get("RoomNumber", data.room_number))
        data.room_map = properties.get("RoomMap", "")
        data.warp_fall_dest = _destination_or_none(properties.get("WarpFallDestination"))
        data.warp_climb_dest = _destination_or_none(properties.get("WarpClimbDestination"))
        data.warps = _load_warps(root)
        data.entities = _load_entities(root)
        return data


def _load_map_properties(root: ET.Element) -> dict:
    """Map-level properties only (ignore per-object properties)."""
    return {
        prop.get("name"): prop.get("value")
        for prop in root.findall("properties/property")
        if prop.get("name")
    }


def _load_warps(root: ET.Element) -> list[dict]:
    """Parse the `Warps` objectgroup: one warp zone per object."""
    warps: list[dict] = []
    for group in root.findall("objectgroup"):
        if group.get("name") != "Warps":
            continue
        for obj in group.findall("object"):
            properties = {
                prop.get("name"): prop.get("value")
                for prop in obj.findall("properties/property")
            }
            if "room1" not in properties:
                continue
            warps.append(
                {
                    # Tile where this warp zone sits in this room...
                    "room1": int(properties.get("room1", -1)),
                    "x": int(obj.get("x", "0")),
                    "y": int(obj.get("y", "0")),
                    "width": int(obj.get("width", "1")),
                    "height": int(obj.get("height", "1")),
                    # ...and the arrival point in the destination room.
                    "room2": int(properties.get("room2", -1)),
                    "x2": int(properties.get("x2", 0)),
                    "y2": int(properties.get("y2", 0)),
                    "type": properties.get("warpType", "NORMAL"),
                }
            )
    return warps


def _load_entities(root: ET.Element) -> list[dict]:
    """Parse the `Entities` objectgroup: one entity per object.

    Entity properties mix ints, floats, bools and strings (TMX serializes
    everything as text) so each value is converted to a native GDScript
    type when building the dictionary.
    """
    entities: list[dict] = []
    for group in root.findall("objectgroup"):
        if group.get("name") != "Entities":
            continue
        for obj in group.findall("object"):
            entity: dict = {
                "name": obj.get("name", ""),
                "tile_class": obj.get("class", ""),
            }
            for prop in obj.findall("properties/property"):
                name = prop.get("name", "")
                if not name:
                    continue
                key = name[0].lower() + name[1:]
                value = _parse_tmx_value(prop.get("value", ""))
                # Coordinates are floats so all 3D positions share one type.
                if key in ("x", "y", "z") and value is not None:
                    value = float(value)
                entity[key] = value
            entities.append(entity)
    return entities


def _parse_tmx_value(value: str):
    if value == "true":
        return True
    if value == "false":
        return False
    if re.fullmatch(r"[+-]?\d+", value):
        return int(value)
    try:
        return float(value)
    except ValueError:
        return value


def _destination_or_none(value: str | None) -> int:
    """Map the source `65535` sentinel (no destination) to -1."""
    if value is None:
        return -1
    parsed = int(value)
    return -1 if parsed == NO_DESTINATION else parsed


def _file_stem(path: str) -> str:
    return os.path.splitext(os.path.basename(path))[0]


def _escape_tscn_string(value: str) -> str:
    return value.replace("\\", "\\\\").replace('"', '\\"')


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


def render_scene(template_path: str, room: RoomData, cells: list[int]) -> str:
    with open(template_path, "r") as file:
        content = file.read()

    content = _replace_string_metadata(
        content,
        {
            "room_name": room.room_name,
            "room_label": room.room_label,
            "room_map": room.room_map,
        },
    )
    content = _replace_int_metadata(
        content,
        {
            "room_number": room.room_number,
            "warp_fall_dest": room.warp_fall_dest,
            "warp_climb_dest": room.warp_climb_dest,
        },
    )
    content = _replace_variant_metadata(content, "warps", room.warps)
    content = _replace_variant_metadata(content, "entities", room.entities)
    content = re.sub(
        r"metadata/hm_left = \d+", f"metadata/hm_left = {room.heightmap.left_offset}", content
    )
    content = re.sub(
        r"metadata/hm_top = \d+", f"metadata/hm_top = {room.heightmap.top_offset}", content
    )
    content = re.sub(
        r"metadata/hm_width = \d+", f"metadata/hm_width = {room.heightmap.width}", content
    )
    content = re.sub(
        r"metadata/hm_height = \d+", f"metadata/hm_height = {room.heightmap.height}", content
    )
    content = content.replace(ROOM_NAME_TOKEN, room.room_label)
    content = content.replace(CELLS_TOKEN, "PackedInt32Array(" + ", ".join(str(v) for v in cells) + ")")
    return content


def _replace_string_metadata(content: str, values: dict[str, str]) -> str:
    for name, value in values.items():
        content = re.sub(
            rf'metadata/{name} = "[^"]*"',
            f'metadata/{name} = "{_escape_tscn_string(value)}"',
            content,
        )
    return content


def _replace_int_metadata(content: str, values: dict[str, int]) -> str:
    for name, value in values.items():
        content = re.sub(
            rf"metadata/{name} = -?\d+", f"metadata/{name} = {value}", content
        )
    return content


# The template stores native Variant placeholders (empty arrays) which the
# serializer replaces by multi-line GDScript array/dictionary literals, so
# scenes can read them with `get_meta()` without any JSON round-trip.
def _replace_variant_metadata(content: str, name: str, value) -> str:
    return re.sub(
        rf"metadata/{name} = \[.*",
        lambda match: f"metadata/{name} = {_format_gd_variant(value, 0)}",
        content,
        count=1,
    )


def _format_gd_variant(value, indent: int = 0) -> str:
    """Serialize a python value the way Godot stores Variants in .tscn files."""
    pad = "\t" * indent
    inner_pad = "\t" * (indent + 1)
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return repr(value)
    if isinstance(value, str):
        return '"' + _escape_tscn_string(value) + '"'
    if isinstance(value, list):
        if not value:
            return "[]"
        items = ",\n".join(
            f"{inner_pad}{_format_gd_variant(item, indent + 1)}" for item in value
        )
        return f"[\n{items},\n{pad}]"
    if isinstance(value, dict):
        if not value:
            return "{}"
        rows = ",\n".join(
            f'{inner_pad}"{key}": {_format_gd_variant(item, indent + 1)}'
            for key, item in sorted(value.items())
        )
        return f"{{\n{rows},\n{pad}}}"
    raise TypeError(f"unserializable type: {type(value)}")


def convert_tmx_to_tscn(tmx_path: str, template_path: str, output_path: str, room_name: str | None) -> str:
    room = RoomData.from_tmx_file(tmx_path)
    if room_name:
        room.room_label = room_name
    cells = build_cells(room.heightmap)
    scene = render_scene(template_path, room, cells)

    os.makedirs(os.path.dirname(output_path) or ".", exist_ok=True)
    with open(output_path, "w") as file:
        file.write(scene)

    occupied = sum(1 for row in room.heightmap.cells for cell in row if not cell.is_void())
    print(
        f"{os.path.basename(tmx_path)} -> {output_path}: "
        f"{room.room_name!r}, {len(room.warps)} warps, "
        f"{room.heightmap.width}x{room.heightmap.height} heightmap, "
        f"{occupied} terrain columns, {len(cells) // 3} grid cells"
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
