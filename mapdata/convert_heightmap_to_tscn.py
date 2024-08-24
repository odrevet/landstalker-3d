import csv
import sys
import re

MAP_SIZE = 65536
MESH_INDEX = 41

def read_csv_to_array(file_path):
    array_2d = []

    with open(file_path, 'r') as file:
        csv_reader = csv.reader(file)
        next(csv_reader)  # Skip the header line

        for row in csv_reader:
            array_2d.append(row)

    return array_2d

def process_csv_data(csv_data):
    processed_data = []
    for y, row in enumerate(csv_data):
        for x, value in enumerate(row):
            z = int(value)
            if z < 4000:
                z /= 100

                # flatten height as warp indicator
                if z >= 20:
                    z = 0

                print(z)
                for i in range(int(z) + 1):
                    processed_data.append(f"{x + i * MAP_SIZE}, {y}, {MESH_INDEX}")
    return processed_data

def insert_csv_into_file(processed_data, input_file, output_file):
    with open(input_file, 'r') as file:
        content = file.read()

    pattern = r'PackedInt32Array\(\)'
    data_string = ', '.join(processed_data)

    replaced_content = content.replace("PackedInt32Array(", f"PackedInt32Array({data_string}", 1)

    with open(output_file, 'w') as file:
        file.write(replaced_content)

if __name__ == "__main__":
    if len(sys.argv) != 4:
        print("Usage: python script.py <path_to_csv_file> <path_to_input_file> <path_to_output_file>")
        sys.exit(1)

    csv_file_path = sys.argv[1]
    input_file_path = sys.argv[2]
    output_file_path = sys.argv[3]

    try:
        csv_data = read_csv_to_array(csv_file_path)
        processed_data = process_csv_data(csv_data)
        insert_csv_into_file(processed_data, input_file_path, output_file_path)

        print(f"Processed CSV data successfully inserted into {output_file_path}")

    except FileNotFoundError as e:
        print(f"Error: File not found - {str(e)}")
    except Exception as e:
        print(f"An error occurred: {str(e)}")
