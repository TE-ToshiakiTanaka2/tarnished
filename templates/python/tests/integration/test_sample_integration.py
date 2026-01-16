"""Sample integration tests demonstrating multi-module interaction."""

import json
from pathlib import Path
from tempfile import TemporaryDirectory


def read_json_file(file_path: Path) -> dict:
    """Read and parse a JSON file."""
    with open(file_path) as f:
        return json.load(f)


def write_json_file(file_path: Path, data: dict) -> None:
    """Write data to a JSON file."""
    with open(file_path, "w") as f:
        json.dump(data, f, indent=2)


class TestJsonFileOperations:
    """Integration tests for JSON file operations."""

    def test_write_and_read_json(self) -> None:
        """Test writing and reading JSON data."""
        with TemporaryDirectory() as tmpdir:
            file_path = Path(tmpdir) / "test.json"
            test_data = {"name": "test", "value": 42, "items": [1, 2, 3]}

            write_json_file(file_path, test_data)
            result = read_json_file(file_path)

            assert result == test_data

    def test_nested_json_structure(self) -> None:
        """Test handling nested JSON structures."""
        with TemporaryDirectory() as tmpdir:
            file_path = Path(tmpdir) / "nested.json"
            test_data = {
                "level1": {
                    "level2": {
                        "level3": {"value": "deep"}
                    }
                }
            }

            write_json_file(file_path, test_data)
            result = read_json_file(file_path)

            assert result["level1"]["level2"]["level3"]["value"] == "deep"
