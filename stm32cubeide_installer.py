#!/usr/bin/env python3
"""
STM32CubeIDE Automated Installer and Bare Metal Configurator
Automates the download, installation, and configuration of STM32CubeIDE for bare metal development
"""

import os
import sys
import subprocess
import platform
import urllib.request
import shutil
import argparse
from pathlib import Path
import zipfile
import tarfile
import tempfile
import json
import time


class STM32CubeIDEInstaller:
    def __init__(self, install_dir=None, workspace_dir=None, download_only=False):
        self.system = platform.system()
        self.machine = platform.machine()
        self.install_dir = install_dir or self.get_default_install_dir()
        self.workspace_dir = workspace_dir or Path.home() / "STM32CubeIDE" / "workspace_bare_metal"
        self.temp_dir = Path(tempfile.gettempdir()) / "stm32cube_install"
        self.download_only = download_only
        
        # NOTE: ST requires login to download CubeIDE. These are direct links that may expire.
        # Users may need to manually download from: https://www.st.com/en/development-tools/stm32cubeide.html
        
    def get_default_install_dir(self):
        """Get default installation directory based on OS"""
        if self.system == 'Linux':
            return Path.home() / 'STM32CubeIDE'
        elif self.system == 'Windows':
            return Path('C:/ST/STM32CubeIDE')
        elif self.system == 'Darwin':
            return Path('/Applications/STM32CubeIDE.app')
        return Path.home() / 'STM32CubeIDE'
    
    def check_prerequisites(self):
        """Check system prerequisites"""
        print("🔍 Checking prerequisites...")
        
        missing = []
        
        if self.system == 'Linux':
            # Check for required packages
            required_packages = ['wget', 'unzip', 'dpkg']
            for pkg in required_packages:
                if shutil.which(pkg) is None:
                    missing.append(pkg)
            
            if missing:
                print(f"❌ Missing packages: {', '.join(missing)}")
                print(f"   Install with: sudo apt-get install {' '.join(missing)}")
                return False
                
        elif self.system == 'Windows':
            print("✓ Windows detected")
            
        elif self.system == 'Darwin':
            print("✓ macOS detected")
        
        print("✓ Prerequisites OK")
        return True
    
    def download_cubeide_manually(self):
        """Provide instructions for manual download"""
        print("\n" + "="*70)
        print("MANUAL DOWNLOAD REQUIRED")
        print("="*70)
        print("\nSTM32CubeIDE requires ST account login to download.")
        print("\nPlease follow these steps:")
        print("\n1. Go to: https://www.st.com/en/development-tools/stm32cubeide.html")
        print("2. Click 'Get Software'")
        print("3. Login or create ST account (free)")
        print("4. Download the appropriate version for your OS:")
        
        if self.system == 'Linux':
            print("   - Select: Generic Linux Installer (.sh or .deb)")
        elif self.system == 'Windows':
            print("   - Select: Windows installer (.exe)")
        elif self.system == 'Darwin':
            print("   - Select: macOS installer (.dmg)")
        
        print(f"\n5. Save the file to: {self.temp_dir}")
        print("\n6. Run this script again with the --installer-path option")
        print(f"   Example: python3 {sys.argv[0]} --installer-path /path/to/installer")
        print("\n" + "="*70)
        
        # Create temp directory
        self.temp_dir.mkdir(parents=True, exist_ok=True)
        print(f"\n✓ Created download directory: {self.temp_dir}")
        
        return None
    
    def install_cubeide_linux(self, installer_path):
        """Install STM32CubeIDE on Linux"""
        print("\n📦 Installing STM32CubeIDE on Linux...")
        
        installer = Path(installer_path)
        
        if not installer.exists():
            print(f"❌ Installer not found: {installer}")
            return False
        
        # Check if it's .sh or .deb
        if installer.suffix == '.sh':
            print(f"   Running shell installer: {installer}")
            # Make executable
            os.chmod(installer, 0o755)
            
            # Run installer
            try:
                result = subprocess.run(
                    ['sudo', str(installer), '--', '-dir', str(self.install_dir)],
                    check=True
                )
                print("✓ Installation completed")
                return True
            except subprocess.CalledProcessError as e:
                print(f"❌ Installation failed: {e}")
                return False
                
        elif installer.suffix == '.deb' or '.deb' in installer.suffixes:
            print(f"   Installing .deb package: {installer}")
            try:
                subprocess.run(['sudo', 'dpkg', '-i', str(installer)], check=True)
                print("✓ Installation completed")
                return True
            except subprocess.CalledProcessError as e:
                print(f"❌ Installation failed: {e}")
                return False
        
        else:
            print(f"❌ Unknown installer format: {installer.suffix}")
            return False
    
    def install_cubeide_windows(self, installer_path):
        """Install STM32CubeIDE on Windows"""
        print("\n📦 Installing STM32CubeIDE on Windows...")
        
        installer = Path(installer_path)
        
        if not installer.exists():
            print(f"❌ Installer not found: {installer}")
            return False
        
        print(f"   Running installer: {installer}")
        print("   Please follow the installation wizard...")
        
        try:
            # Run installer with silent mode if possible
            subprocess.run([str(installer), '/SILENT'], check=False)
            print("✓ Installation initiated")
            return True
        except Exception as e:
            print(f"⚠ Note: {e}")
            print("   Please complete installation manually if the wizard appeared")
            return True
    
    def install_cubeide_macos(self, installer_path):
        """Install STM32CubeIDE on macOS"""
        print("\n📦 Installing STM32CubeIDE on macOS...")
        
        installer = Path(installer_path)
        
        if not installer.exists():
            print(f"❌ Installer not found: {installer}")
            return False
        
        if installer.suffix == '.dmg':
            print(f"   Mounting DMG: {installer}")
            try:
                # Mount DMG
                result = subprocess.run(
                    ['hdiutil', 'attach', str(installer)],
                    capture_output=True, text=True
                )
                
                # Find mounted volume
                # Copy app to Applications
                print("   Please drag STM32CubeIDE to Applications folder")
                print("   Press Enter when done...")
                input()
                
                return True
            except subprocess.CalledProcessError as e:
                print(f"❌ Installation failed: {e}")
                return False
        
        return False
    
    def install_cubeide(self, installer_path):
        """Install STM32CubeIDE based on platform"""
        if self.system == 'Linux':
            return self.install_cubeide_linux(installer_path)
        elif self.system == 'Windows':
            return self.install_cubeide_windows(installer_path)
        elif self.system == 'Darwin':
            return self.install_cubeide_macos(installer_path)
        else:
            print(f"❌ Unsupported platform: {self.system}")
            return False
    
    def create_workspace(self):
        """Create and configure workspace for bare metal development"""
        print(f"\n📁 Creating workspace: {self.workspace_dir}")
        
        # Create workspace directory
        self.workspace_dir.mkdir(parents=True, exist_ok=True)
        
        # Create .metadata directory
        metadata_dir = self.workspace_dir / ".metadata"
        metadata_dir.mkdir(exist_ok=True)
        
        # Create workspace preferences for bare metal
        self.configure_workspace_preferences()
        
        print(f"✓ Workspace created: {self.workspace_dir}")
    
    def configure_workspace_preferences(self):
        """Configure workspace preferences for bare metal development"""
        print("⚙️  Configuring workspace preferences...")
        
        # Create .metadata/.plugins directory structure
        plugins_dir = self.workspace_dir / ".metadata" / ".plugins"
        plugins_dir.mkdir(parents=True, exist_ok=True)
        
        # Configure build settings
        prefs_dir = plugins_dir / "org.eclipse.core.runtime" / ".settings"
        prefs_dir.mkdir(parents=True, exist_ok=True)
        
        # Disable HAL by default in preferences
        self.write_preference_file(
            prefs_dir / "com.st.stm32cube.ide.mcu.rtos.prefs",
            {
                "eclipse.preferences.version": "1",
                "use_hal_driver": "false",
                "use_ll_driver": "false"
            }
        )
        
        print("✓ Workspace configured for bare metal")
    
    def write_preference_file(self, filepath, preferences):
        """Write Eclipse preference file"""
        with open(filepath, 'w') as f:
            for key, value in preferences.items():
                f.write(f"{key}={value}\n")
    
    def create_bare_metal_project_template(self, project_name, mcu_model="STM32F407VGTx"):
        """Create a bare metal project template in the workspace"""
        print(f"\n🔨 Creating bare metal project template: {project_name}")
        
        project_dir = self.workspace_dir / project_name
        project_dir.mkdir(exist_ok=True)
        
        # Create project structure
        (project_dir / "Core" / "Src").mkdir(parents=True, exist_ok=True)
        (project_dir / "Core" / "Inc").mkdir(parents=True, exist_ok=True)
        (project_dir / "Drivers" / "CMSIS" / "Include").mkdir(parents=True, exist_ok=True)
        (project_dir / "Startup").mkdir(parents=True, exist_ok=True)
        
        # Create .project file
        self.create_eclipse_project_file(project_dir, project_name)
        
        # Create .cproject file
        self.create_cproject_file(project_dir, project_name, mcu_model)
        
        # Create basic main.c
        self.create_main_c(project_dir)
        
        # Create linker script
        self.create_linker_script(project_dir, mcu_model)
        
        # Create startup file
        self.create_startup_file(project_dir, mcu_model)
        
        print(f"✓ Project template created: {project_dir}")
    
    def create_eclipse_project_file(self, project_dir, project_name):
        """Create Eclipse .project file"""
        project_xml = f"""<?xml version="1.0" encoding="UTF-8"?>
<projectDescription>
    <name>{project_name}</name>
    <comment></comment>
    <projects>
    </projects>
    <buildSpec>
        <buildCommand>
            <name>org.eclipse.cdt.managedbuilder.core.genmakebuilder</name>
            <triggers>clean,full,incremental,</triggers>
            <arguments>
            </arguments>
        </buildCommand>
        <buildCommand>
            <name>org.eclipse.cdt.managedbuilder.core.ScannerConfigBuilder</name>
            <triggers>full,incremental,</triggers>
            <arguments>
            </arguments>
        </buildCommand>
    </buildSpec>
    <natures>
        <nature>org.eclipse.cdt.core.cnature</nature>
        <nature>org.eclipse.cdt.managedbuilder.core.managedBuildNature</nature>
        <nature>org.eclipse.cdt.managedbuilder.core.ScannerConfigNature</nature>
        <nature>com.st.stm32cube.ide.mcu.MCUProjectNature</nature>
    </natures>
    <linkedResources>
    </linkedResources>
</projectDescription>
"""
        with open(project_dir / ".project", 'w') as f:
            f.write(project_xml)
    
    def create_cproject_file(self, project_dir, project_name, mcu_model):
        """Create Eclipse .cproject file for bare metal"""
        # This is a simplified version - full .cproject is very complex
        cproject_xml = f"""<?xml version="1.0" encoding="UTF-8" standalone="no"?>
<?fileVersion 4.0.0?><cproject storage_type_id="org.eclipse.cdt.core.XmlProjectDescriptionStorage">
    <storageModule moduleId="org.eclipse.cdt.core.settings">
        <cconfiguration id="com.st.stm32cube.ide.mcu.gnu.managedbuild.config.exe.debug">
            <storageModule buildSystemId="org.eclipse.cdt.managedbuilder.core.configurationDataProvider" id="com.st.stm32cube.ide.mcu.gnu.managedbuild.config.exe.debug" moduleId="org.eclipse.cdt.core.settings" name="Debug">
                <externalSettings/>
                <extensions>
                    <extension id="org.eclipse.cdt.core.ELF" point="org.eclipse.cdt.core.BinaryParser"/>
                    <extension id="org.eclipse.cdt.core.GASErrorParser" point="org.eclipse.cdt.core.ErrorParser"/>
                    <extension id="org.eclipse.cdt.core.GmakeErrorParser" point="org.eclipse.cdt.core.ErrorParser"/>
                    <extension id="org.eclipse.cdt.core.GLDErrorParser" point="org.eclipse.cdt.core.ErrorParser"/>
                    <extension id="org.eclipse.cdt.core.CWDLocator" point="org.eclipse.cdt.core.ErrorParser"/>
                    <extension id="org.eclipse.cdt.core.GCCErrorParser" point="org.eclipse.cdt.core.ErrorParser"/>
                </extensions>
            </storageModule>
            <storageModule moduleId="cdtBuildSystem" version="4.0.0">
                <configuration artifactExtension="elf" artifactName="${{ProjName}}" buildArtefactType="org.eclipse.cdt.build.core.buildArtefactType.exe" buildProperties="org.eclipse.cdt.build.core.buildArtefactType=org.eclipse.cdt.build.core.buildArtefactType.exe" cleanCommand="rm -rf" description="" id="com.st.stm32cube.ide.mcu.gnu.managedbuild.config.exe.debug" name="Debug" parent="com.st.stm32cube.ide.mcu.gnu.managedbuild.config.exe.debug">
                </configuration>
            </storageModule>
        </cconfiguration>
    </storageModule>
</cproject>
"""
        with open(project_dir / ".cproject", 'w') as f:
            f.write(cproject_xml)
    
    def create_main_c(self, project_dir):
        """Create basic main.c for bare metal"""
        main_c = """/**
  ******************************************************************************
  * @file           : main.c
  * @brief          : Bare Metal Main program
  ******************************************************************************
  */

#include <stdint.h>

/* STM32F4xx register definitions - update for your MCU */
#define RCC_BASE            0x40023800
#define RCC_AHB1ENR         (*(volatile uint32_t *)(RCC_BASE + 0x30))
#define RCC_AHB1ENR_GPIODEN (1 << 3)

#define GPIOD_BASE          0x40020C00
#define GPIOD_MODER         (*(volatile uint32_t *)(GPIOD_BASE + 0x00))
#define GPIOD_ODR           (*(volatile uint32_t *)(GPIOD_BASE + 0x14))

void delay(volatile uint32_t count) {
    while(count--);
}

int main(void) {
    /* Enable GPIOD clock */
    RCC_AHB1ENR |= RCC_AHB1ENR_GPIODEN;
    
    /* Configure PD12 as output */
    GPIOD_MODER &= ~(3 << (12 * 2));
    GPIOD_MODER |= (1 << (12 * 2));
    
    /* Main loop */
    while (1) {
        /* Toggle PD12 */
        GPIOD_ODR ^= (1 << 12);
        delay(1000000);
    }
}
"""
        with open(project_dir / "Core" / "Src" / "main.c", 'w') as f:
            f.write(main_c)
    
    def create_linker_script(self, project_dir, mcu_model):
        """Create basic linker script"""
        linker_script = """/* Entry Point */
ENTRY(Reset_Handler)

/* Memory Sections */
MEMORY
{
  RAM (xrw)    : ORIGIN = 0x20000000, LENGTH = 128K
  FLASH (rx)   : ORIGIN = 0x08000000, LENGTH = 1024K
}

_estack = ORIGIN(RAM) + LENGTH(RAM);

SECTIONS
{
  .isr_vector :
  {
    . = ALIGN(4);
    KEEP(*(.isr_vector))
    . = ALIGN(4);
  } >FLASH

  .text :
  {
    . = ALIGN(4);
    *(.text)
    *(.text*)
    . = ALIGN(4);
    _etext = .;
  } >FLASH

  .data :
  {
    . = ALIGN(4);
    _sdata = .;
    *(.data)
    *(.data*)
    . = ALIGN(4);
    _edata = .;
  } >RAM AT> FLASH

  _sidata = LOADADDR(.data);

  .bss :
  {
    . = ALIGN(4);
    _sbss = .;
    *(.bss)
    *(.bss*)
    *(COMMON)
    . = ALIGN(4);
    _ebss = .;
  } >RAM
}
"""
        with open(project_dir / "STM32_FLASH.ld", 'w') as f:
            f.write(linker_script)
    
    def create_startup_file(self, project_dir, mcu_model):
        """Create minimal startup file"""
        startup_s = """.syntax unified
.cpu cortex-m4
.thumb

.global g_pfnVectors
.global Default_Handler

.word _sidata
.word _sdata
.word _edata
.word _sbss
.word _ebss

.section .text.Reset_Handler
.weak Reset_Handler
.type Reset_Handler, %function
Reset_Handler:
  ldr   sp, =_estack
  ldr r0, =_sdata
  ldr r1, =_edata
  ldr r2, =_sidata
  movs r3, #0
  b LoopCopyDataInit

CopyDataInit:
  ldr r4, [r2, r3]
  str r4, [r0, r3]
  adds r3, r3, #4

LoopCopyDataInit:
  adds r4, r0, r3
  cmp r4, r1
  bcc CopyDataInit
  
  ldr r2, =_sbss
  ldr r4, =_ebss
  movs r3, #0
  b LoopFillZerobss

FillZerobss:
  str  r3, [r2]
  adds r2, r2, #4

LoopFillZerobss:
  cmp r2, r4
  bcc FillZerobss

  bl main
  bx lr
.size Reset_Handler, .-Reset_Handler

.section .text.Default_Handler,"ax",%progbits
Default_Handler:
Infinite_Loop:
  b Infinite_Loop
  .size Default_Handler, .-Default_Handler

.section .isr_vector,"a",%progbits
.type g_pfnVectors, %object

g_pfnVectors:
  .word _estack
  .word Reset_Handler
  .word Default_Handler  /* NMI_Handler */
  .word Default_Handler  /* HardFault_Handler */
  /* Add more vectors as needed */
"""
        with open(project_dir / "Startup" / "startup.s", 'w') as f:
            f.write(startup_s)
    
    def download_cmsis_headers(self):
        """Guide user to download CMSIS headers"""
        print("\n📥 CMSIS Headers Setup")
        print("="*70)
        print("\nCMSIS headers are required for bare metal development.")
        print("\nOption 1: Download from ST (Recommended)")
        print("   1. Go to: https://www.st.com/en/embedded-software/stm32cube-mcu-mpu-packages.html")
        print("   2. Download the package for your MCU family (e.g., STM32CubeF4)")
        print("   3. Extract: Drivers/CMSIS/")
        print(f"   4. Copy to: {self.workspace_dir}/[YourProject]/Drivers/CMSIS/")
        
        print("\nOption 2: Use CubeIDE built-in headers")
        print("   - CubeIDE includes CMSIS headers")
        print("   - Configure include paths in project settings")
        print("\n" + "="*70)
    
    def run_installation(self, installer_path=None):
        """Run the complete installation process"""
        print("\n" + "="*70)
        print("STM32CubeIDE Bare Metal Setup")
        print("="*70 + "\n")
        
        # Check prerequisites
        if not self.check_prerequisites():
            return False
        
        # If no installer path provided, show download instructions
        if not installer_path:
            self.download_cubeide_manually()
            if not self.download_only:
                print("\n⚠️  Please download the installer and run this script again.")
            return False
        
        # Install CubeIDE
        if not self.install_cubeide(installer_path):
            print("\n❌ Installation failed")
            return False
        
        print("\n⏳ Waiting for installation to complete...")
        time.sleep(5)
        
        # Create workspace
        self.create_workspace()
        
        # Create sample bare metal project
        self.create_bare_metal_project_template("BareMetal_Template")
        
        # Show CMSIS download instructions
        self.download_cmsis_headers()
        
        print("\n✅ Setup Complete!")
        print("\nNext steps:")
        print(f"1. Launch STM32CubeIDE")
        print(f"2. Select workspace: {self.workspace_dir}")
        print(f"3. Import project: File → Import → Existing Projects")
        print(f"4. Add CMSIS headers to your project")
        print(f"5. Configure build settings for bare metal (no HAL)")
        print("\n" + "="*70)
        
        return True


def main():
    parser = argparse.ArgumentParser(
        description='Automated STM32CubeIDE installer and bare metal configurator',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Show download instructions
  python3 stm32cubeide_installer.py
  
  # Install with downloaded installer (Linux)
  python3 stm32cubeide_installer.py --installer-path ~/Downloads/st-stm32cubeide*.sh
  
  # Install with custom directories
  python3 stm32cubeide_installer.py --installer-path installer.sh --install-dir /opt/cubeide --workspace ~/my_workspace
  
  # Only create workspace (CubeIDE already installed)
  python3 stm32cubeide_installer.py --workspace-only --workspace ~/my_workspace
        """
    )
    
    parser.add_argument('--installer-path', 
                       help='Path to downloaded STM32CubeIDE installer')
    parser.add_argument('--install-dir',
                       help='Custom installation directory')
    parser.add_argument('--workspace',
                       help='Custom workspace directory')
    parser.add_argument('--workspace-only', action='store_true',
                       help='Only create workspace (skip installation)')
    parser.add_argument('--download-only', action='store_true',
                       help='Only show download instructions')
    
    args = parser.parse_args()
    
    installer = STM32CubeIDEInstaller(
        install_dir=args.install_dir,
        workspace_dir=args.workspace,
        download_only=args.download_only
    )
    
    if args.workspace_only:
        # Just create workspace and template
        installer.create_workspace()
        installer.create_bare_metal_project_template("BareMetal_Template")
        installer.download_cmsis_headers()
        print("\n✅ Workspace setup complete!")
    else:
        # Full installation
        installer.run_installation(args.installer_path)


if __name__ == "__main__":
    main()
