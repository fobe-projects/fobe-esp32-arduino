import os
import urllib.request
from multiprocessing import Pool
import zipfile
import re
from functools import partial

# Download a variant's bootloader
def download_variant(variant, version):

    # Download from bootloader release
    f_zip = f"tinyuf2-{variant}-{version}.zip"
    url_prefix = (
        f"https://github.com/fobe-projects/fobe-tinyuf2/releases/download/{version}/"
    )

    # remove existing bootloader files
    if os.path.exists(f"variants/{variant}/bootloader-tinyuf2.bin"):
        os.remove(f"variants/{variant}/bootloader-tinyuf2.bin")
    if os.path.exists(f"variants/{variant}/tinyuf2.uf2"):
        os.remove(f"variants/{variant}/tinyuf2.uf2")

    print(f"Downloading {f_zip}")
    urllib.request.urlretrieve(url_prefix + f_zip, f"variants/{variant}/{f_zip}")
    if os.path.exists(f"variants/{variant}/{f_zip}"):
        print(f"Downloaded {f_zip}")
        with zipfile.ZipFile(f"variants/{variant}/{f_zip}", "r") as zip_ref:
            for member in zip_ref.namelist():
                if member.endswith('tinyuf2.bin'):
                    # Extract and rename tinyuf2.bin
                    zip_ref.extract(member, f"variants/{variant}/")
                    extracted_path = f"variants/{variant}/{member}"
                    new_name = f"variants/{variant}/tinyuf2-{version}.bin"
                    os.rename(extracted_path, new_name)
                elif member.endswith('bootloader.bin'):
                    # Extract and rename bootloader.bin
                    zip_ref.extract(member, f"variants/{variant}/")
                    extracted_path = f"variants/{variant}/{member}"
                    new_name = f"variants/{variant}/bootloader-tinyuf2-{version}.bin"
                    os.rename(extracted_path, new_name)

        # Clean up the zip file
        os.remove(f"variants/{variant}/{f_zip}")
        print(f"Cleaned up {f_zip}")


if __name__ == "__main__":
    # Detect version from boards.txt
    version = ""
    with open("boards.txt") as pf:
        platform_txt = pf.read()
        match = re.search(r"bootloader-tinyuf2-(\d+\.\d+\.\d+)", platform_txt)
        if match:
            version = match.group(1)

    print(f"version {version}")

    # Get all variants
    all_variant = []
    for entry in os.scandir("variants"):
        if entry.is_dir():
            all_variant.append(entry.name)
    all_variant.sort()

    download_with_version = partial(download_variant, version=version)
    with Pool() as p:
        p.map(download_with_version, all_variant)
