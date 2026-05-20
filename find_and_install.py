#!/usr/bin/env python3
"""
Helper script to find and install STM32CubeIDE on Windows
Automatically locates the installer file
"""

import os
import sys
import glob
from pathlib import Path

def find_installer():
    """Find STM32CubeIDE installer in common locations"""
    
    # Common download locations
    search_paths = [
        Path.home() / "Downloads",
        Path("C:/Downloads"),
        Path("C:/Users") / os.getlogin() / "Downloads",
        Path.cwd(),  # Current directory
    ]
    
    # Patterns to search for
    patterns = [
        "*stm32cubeide*.exe",
        "*STM32CubeIDE*.exe",
        "st-stm32cubeide*.exe",
    ]
    
    print("🔍 Searching for STM32CubeIDE installer...")
    print()
    
    found_installers = []
    
    for search_path in search_paths:
        if not search_path.exists():
            continue
            
        print(f"Checking: {search_path}")
        
        for pattern in patterns:
            full_pattern = str(search_path / pattern)
            matches = glob.glob(full_pattern)
            
            for match in matches:
                if match not in found_installers:
                    found_installers.append(match)
                    print(f"  ✓ Found: {match}")
    
    return found_installers

def main():
    installers = find_installer()
    
    if not installers:
        print("\n❌ No STM32CubeIDE installer found!")
        print("\nPlease:")
        print("1. Download from: https://www.st.com/en/development-tools/stm32cubeide.html")
        print("2. Save to Downloads folder")
        print("3. Run this script again")
        print("\nOr specify path manually:")
        print('   python stm32cubeide_installer.py --installer-path "C:\\path\\to\\installer.exe"')
        return
    
    print("\n" + "="*70)
    print("Found installer(s):")
    print("="*70)
    
    for i, installer in enumerate(installers, 1):
        file_size = os.path.getsize(installer) / (1024*1024)  # MB
        print(f"{i}. {installer}")
        print(f"   Size: {file_size:.1f} MB")
    
    print("\nTo install, run:")
    print(f'python stm32cubeide_installer.py --installer-path "{installers[0]}"')
    
    # Ask if user wants to install now
    print("\n" + "="*70)
    response = input("Install now? (y/n): ").strip().lower()
    
    if response == 'y':
        print("\n🚀 Starting installation...")
        import subprocess
        
        # Run the installer script
        cmd = [
            sys.executable,
            "stm32cubeide_installer.py",
            "--installer-path",
            installers[0]
        ]
        
        subprocess.run(cmd)
    else:
        print("\nInstallation cancelled. Run the command above when ready.")

if __name__ == "__main__":
    main()
