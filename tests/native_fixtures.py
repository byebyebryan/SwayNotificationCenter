"""Resources owned by private native fixtures, independent of installed SwayNC."""

from pathlib import Path
import shutil
import subprocess


def prepare_schema(root):
    directory = Path(root) / "schemas"
    directory.mkdir()
    source = Path(__file__).resolve().parent.parent / "data/org.erikreider.swaync.gschema.xml"
    shutil.copy2(source, directory / source.name)
    subprocess.run(["glib-compile-schemas", "--strict", str(directory)], check=True)
    return str(directory)
