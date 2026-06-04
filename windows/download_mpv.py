import os
import sys
import argparse
import urllib.request
import xml.etree.ElementTree as ET
import subprocess
import shutil

def main():
    parser = argparse.ArgumentParser(description="Download and extract libmpv binaries for Windows.")
    parser.add_argument("--arch", required=True, choices=["x64", "arm64"], help="Target architecture (x64 or arm64)")
    args = parser.parse_args()

    arch_lower = args.arch.lower()
    if arch_lower == "x64":
        search_pattern = "mpv-dev-x86_64"
        exclude_pattern = "v3"
        dest_dir = "x64"
        fallback_url = "https://sourceforge.net/projects/mpv-player-windows/files/libmpv/mpv-dev-x86_64-20260531-git-13a3e3a.7z/download"
    else:  # arm64
        search_pattern = "mpv-dev-aarch64"
        exclude_pattern = None
        dest_dir = "arm64"
        fallback_url = "https://sourceforge.net/projects/mpv-player-windows/files/libmpv/mpv-dev-aarch64-20260531-git-13a3e3a.7z/download"

    print(f"Fetching libmpv Windows {args.arch} feed...")
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
        print(f"Error fetching RSS: {e}")
        print(f"Using hardcoded fallback URL...")
        download_url = fallback_url

    print(f"Downloading from: {download_url}")
    target_archive = f"mpv-dev-{arch_lower}.7z"
    
    # Download file using curl.exe
    print("Downloading with curl.exe...")
    subprocess.run(["curl.exe", "-L", "-o", target_archive, download_url], check=True)
    print("Download completed.")

    # Create target directory
    target_dir = os.path.abspath(f"vendor/mpv-dev/{dest_dir}")
    os.makedirs(target_dir, exist_ok=True)

    # Find 7z executable
    seven_zip = "7z"
    if not shutil.which(seven_zip):
        default_path = r"C:\Program Files\7-Zip\7z.exe"
        if os.path.exists(default_path):
            seven_zip = default_path
        else:
            raise FileNotFoundError("7z executable not found in PATH or at C:\\Program Files\\7-Zip\\7z.exe")

    # Extract using 7z
    print(f"Extracting to {target_dir} using {seven_zip}...")
    subprocess.run([seven_zip, "x", target_archive, f"-o{target_dir}", "-y"], check=True)

    # Clean up archive
    if os.path.exists(target_archive):
        os.remove(target_archive)

    print(f"libmpv {args.arch} setup complete.")

if __name__ == "__main__":
    main()
