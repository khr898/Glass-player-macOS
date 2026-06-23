import os
import sys
import argparse
import urllib.request
import xml.etree.ElementTree as ET
import subprocess
import shutil
import zipfile

def check_arch(val):
    val_lower = val.lower()
    if val_lower not in ["x64", "arm64"]:
        raise argparse.ArgumentTypeError(f"Invalid arch: '{val}'. Choose from 'x64', 'arm64'.")
    return val_lower

def download_file(url, target_path):
    print(f"Downloading {url} to {target_path}...")
    subprocess.run(["curl.exe", "-L", "-o", target_path, url], check=True)

def find_7z():
    seven_zip = "7z"
    if not shutil.which(seven_zip):
        default_path = r"C:\Program Files\7-Zip\7z.exe"
        if os.path.exists(default_path):
            seven_zip = default_path
        else:
            raise FileNotFoundError("7z executable not found in PATH or at C:\\Program Files\\7-Zip\\7z.exe")
    return seven_zip

def setup_mpv(arch):
    if arch == "x64":
        search_pattern = "mpv-dev-x86_64"
        exclude_pattern = "v3"
        dest_dir = "x64"
        fallback_url = "https://sourceforge.net/projects/mpv-player-windows/files/libmpv/mpv-dev-x86_64-20260531-git-13a3e3a.7z/download"
    else:  # arm64
        search_pattern = "mpv-dev-aarch64"
        exclude_pattern = None
        dest_dir = "arm64"
        fallback_url = "https://sourceforge.net/projects/mpv-player-windows/files/libmpv/mpv-dev-aarch64-20260531-git-13a3e3a.7z/download"

    print(f"Fetching libmpv Windows {arch} feed...")
    rss_url = 'https://sourceforge.net/projects/mpv-player-windows/rss?path=/libmpv'
    download_url = None

    try:
        req = urllib.request.Request(
            rss_url, 
            headers={'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'}
        )
        xml_data = urllib.request.urlopen(req, timeout=30).read()
        root = ET.fromstring(xml_data)
        items = root.findall('.//item')
        
        for item in items:
            title = item.find('title').text
            if search_pattern in title:
                if exclude_pattern and exclude_pattern in title:
                    continue
                download_url = item.find('link').text
                break
                
        if not download_url:
            raise Exception(f"No matching file found for {search_pattern}")
            
    except Exception as e:
        print(f"Error fetching RSS: {e}. Using hardcoded fallback...")
        download_url = fallback_url

    target_archive = f"mpv-dev-{arch}.7z"
    download_file(download_url, target_archive)

    target_dir = os.path.abspath(f"../vendor/mpv-dev/{dest_dir}")
    os.makedirs(target_dir, exist_ok=True)

    seven_zip = find_7z()
    print(f"Extracting mpv to {target_dir}...")
    subprocess.run([seven_zip, "x", target_archive, f"-o{target_dir}", "-y"], check=True)

    if os.path.exists(target_archive):
        os.remove(target_archive)

def setup_angle(arch):
    tag = "2026-06-06"
    dest_dir = "x64" if arch == "x64" else "arm64"
    filename = f"angle-{arch}-{tag}.zip"
    url = f"https://github.com/mmozeiko/build-angle/releases/download/{tag}/{filename}"

    target_archive = f"angle-{arch}.zip"
    download_file(url, target_archive)

    target_dir = os.path.abspath(f"../vendor/angle/{dest_dir}")
    os.makedirs(target_dir, exist_ok=True)

    print(f"Extracting ANGLE to {target_dir}...")
    with zipfile.ZipFile(target_archive, "r") as zip_ref:
        zip_ref.extractall("angle_temp")

    # The archive contains a folder named 'angle-x64' or similar. We copy its contents directly.
    src_folder = os.path.join("angle_temp", f"angle-{arch}")
    for item in os.listdir(src_folder):
        s = os.path.join(src_folder, item)
        d = os.path.join(target_dir, item)
        if os.path.isdir(s):
            if os.path.exists(d):
                shutil.rmtree(d)
            shutil.copytree(s, d)
        else:
            shutil.copy2(s, d)

    # Clean up temp
    shutil.rmtree("angle_temp")
    if os.path.exists(target_archive):
        os.remove(target_archive)

def main():
    parser = argparse.ArgumentParser(description="Download dependencies for WinUI 3 port.")
    parser.add_argument("--arch", required=True, type=check_arch, help="Target architecture (x64 or arm64)")
    args = parser.parse_args()

    # Move to the script's directory so paths are relative to it
    script_dir = os.path.dirname(os.path.abspath(__file__))
    os.chdir(script_dir)

    print(f"Setting up dependencies for {args.arch}...")
    setup_mpv(args.arch)
    setup_angle(args.arch)
    print("All dependencies set up successfully.")

if __name__ == "__main__":
    main()
