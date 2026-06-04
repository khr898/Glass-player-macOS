import os
import urllib.request
import xml.etree.ElementTree as ET
import subprocess

def main():
    print("Fetching libmpv ARM64 feed...")
    rss_url = 'https://sourceforge.net/projects/mpv-player-windows/rss?path=/libmpv'
    try:
        req = urllib.request.Request(
            rss_url, 
            headers={'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'}
        )
        xml_data = urllib.request.urlopen(req, timeout=30).read()
        root = ET.fromstring(xml_data)
        items = root.findall('.//item')
        urls = [i.find('link').text for i in items if 'mpv-dev-aarch64' in i.find('title').text]
        if not urls:
            raise Exception("No mpv-dev-aarch64 files found in RSS feed.")
        download_url = urls[0]
    except Exception as e:
        print(f"Error fetching RSS: {e}")
        # fallback link just in case
        download_url = "https://sourceforge.net/projects/mpv-player-windows/files/libmpv/mpv-dev-aarch64-20260531-git-13a3e3a.7z/download"

    print(f"Downloading from: {download_url}")
    target_archive = "mpv-dev-aarch64.7z"
    
    # Download file using curl.exe
    print("Downloading with curl.exe...")
    subprocess.run(["curl.exe", "-L", "-o", target_archive, download_url], check=True)
    print("Download completed.")


    # Create target directory
    target_dir = os.path.abspath("vendor/mpv-dev/arm64")
    os.makedirs(target_dir, exist_ok=True)

    # Extract using 7z
    import shutil
    seven_zip = "7z"
    if not shutil.which(seven_zip):
        default_path = r"C:\Program Files\7-Zip\7z.exe"
        if os.path.exists(default_path):
            seven_zip = default_path
        else:
            raise FileNotFoundError("7z executable not found in PATH or at C:\\Program Files\\7-Zip\\7z.exe")

    print(f"Extracting to {target_dir} using {seven_zip}...")
    subprocess.run([seven_zip, "x", target_archive, f"-o{target_dir}", "-y"], check=True)


    # Clean up archive
    if os.path.exists(target_archive):
        os.remove(target_archive)

    print("libmpv ARM64 setup complete.")

if __name__ == "__main__":
    main()
