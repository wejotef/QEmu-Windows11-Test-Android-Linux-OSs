:
:: Copyright (c) 2024 <wejotef@gmail.com>
::
:: Permission is hereby granted, free of charge, to any person obtaining a copy
:: of this software and associated documentation files (the "Software"), to deal
:: in the Software without restriction, including without limitation the rights
:: to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
:: copies of the Software, and to permit persons to whom the Software is
:: furnished to do so, subject to the following conditions:
::
:: The above copyright notice and this permission notice shall be included in all
:: copies or substantial portions of the Software.
::
:: THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
:: IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
:: FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
:: AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
:: LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
:: OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
:: SOFTWARE.
::
@echo off
setlocal enabledelayedexpansion
cd /D %~dp0
set "workDir=%CD%"

:: Force running this script as Administrator
if exist "!workDir!\forceadmin.vbs" ( del /F /Q "!workDir!\forceadmin.vbs" )
fsutil dirty query %systemdrive% >nul 2>&1 || (
    echo Set UAC = CreateObject^("Shell.Application"^) > "!workDir!\forceadmin.vbs"
    echo UAC.ShellExecute "cmd.exe", "/k cd ""%~sdp0"" && ""%~s0"" %*", "", "runas", 1 >> "!workDir!\forceadmin.vbs"
    "!workDir!\forceadmin.vbs"
    exit /B
)

pushd !workDir!

:: Some pre-sets
set "vmsPath=!workDir!\VMs"
set /A baseMemoryNeededAndroidMB=1024
set /A baseMemoryNeededLinuxMB=8192
set /A baseSpaceNeededGB=15

set "TAB=   "
if exist "!workDir!\forceadmin.vbs" ( del /F /Q "!workDir!\forceadmin.vbs" )

echo Verifying Windows OS...
for /f "tokens=3 delims= " %%a in ('wmic os get caption /value ^| findstr /i /C:"Caption"') do (
    set /A osVersion=%%a
)

if !osVersion! lss 11 (
    echo This computer is not running Windows 11. Exiting...
    timeout /t 5 >nul && popd && endlocal && exit /b 1
)

:: Check if UEFI or BIOS
for /f "tokens=2 delims==" %%a in ('wmic computersystem get bootupstate /value') do (
    set "firmwareType=%%a"
)
if "!firmwareType!"=="Normal boot" (
    set "firmwareType=BIOS"
) else (
    set "firmwareType=UEFI"
)

:: Check for QEMU installation
set "qemuLocation=!workDir!\qemu"
if NOT exist "!qemuLocation!" (
    echo QEMU not found. Exiting...
    timeout /t 5 >nul && popd && endlocal && exit /B 1
)

set "QEMU_EXE=!qemuLocation!\qemu-system-x86_64.exe"
set "QEMU_IMG_EXE=!qemuLocation!\qemu-img.exe"

echo Checking system features...
set /A kvmSupported=0
systeminfo | findstr /i /C:"Hyper-V" > nul 2>&1 && set /A kvmSupported=1

:: Check for Intel processor
set /A cpuIntel=0
for /f "skip=1 tokens=*" %%a in ('wmic cpu get Manufacturer ^| findstr /I /C:"Intel"') do (
    set /A cpuIntel=1
)

:: Check HAXM status
if !cpuIntel! equ 1 (
    sc query intelhaxm | findstr /I /C:"RUNNING" >nul 2>&1 && set /A haxmIsRunning=1 || set /A haxmIsRunning=0
)

:: Handle conflicting drivers
if !kvmSupported! equ 1 (
    if !haxmIsRunning! equ 1 (
        echo Conflicting drivers encountered:
        echo Disable Hyper-V or HAXM. Exiting...
        timeout /t 5 >nul && popd && endlocal && exit /B 1
    )
)

if !cpuIntel! equ 1 (
    if !haxmIsRunning! equ 0 (
        echo(
        echo !TAB!Note: Intel HAXM driver is not installed or not running.
        echo !TAB!It's highly recommended to install it.
        echo(
    )
)

:: Check if QVMF is present
if "!firmwareType!"=="BIOS" (
    set "ovmfFile=!workDir!\ovmf\ovmf.qcow2"
    if NOT exist "!ovmfFile!" (
        echo Error: File ovmf.qcow2 not found. Please add it! Exiting...
        timeout /t 5 >nul && popd && endlocal && exit /B 1
    )
)

:: Check for guest OS files
set "isoFilesPath=!workDir!\iso-files"
if NOT exist "!isoFilesPath!" (
    echo No guest OS ISO files found. Exiting...
    timeout /t 5 >nul && popd && endlocal && exit /B 1
)

set /A cntPathsExist=0

for %%d in ("android" "linux") do (
    if exist "!isoFilesPath!\%%d" ( 
        set /A cntPathsExist+=1 
    )
)

if !cntPathsExist! equ 0 (
    echo Neither Linux nor Android guest OS ISO files found. Exiting...
    timeout /t 5 >nul && popd && endlocal && exit /B 1
)

:: List all ISO files in the directories
echo(
echo Found:
set /A countISO=0

for %%d in ("android" "linux") do (
    if exist "!isoFilesPath!\%%d" (
        for %%f in ("!isoFilesPath!\%%d\*.iso") do (
            set /a countISO+=1
            set "isoFiles[!countISO!]=%%f"
            echo !countISO!. %%~nxf
        )
    )
)

echo 0. Exit

:: Prompt user to select a guest OS
set /p choice="Select a guest OS to boot with QEMU (0-%countISO%): "
set /A choice=!choice!

if !choice! equ 0 (
   echo User abort. Exiting...
   timeout /t 5 >nul && popd && endlocal && exit /b
)
if !choice! gtr !countISO! (
    echo Invalid choice. Exiting...
    timeout /t 5 >nul && popd && endlocal && exit /b
)

echo(
set "guestOS=!isoFiles[%choice%]!"
for %%f in ("!guestOS!") do ( set "guestOS=%%~nf" )

:: Determine memory needed based on the selected OS type
set /A isAndroidISO=0
echo !guestOS! | findstr /I /C:"android" >nul && (
    set /A isAndroidISO=1
    set /A memoryNeededMB=!baseMemoryNeededAndroidMB!
) || (
    set /A memoryNeededMB=!baseMemoryNeededLinuxMB!
)

:: Check available RAM
echo Checking for enough free RAM...
for /f "skip=1 tokens=2 delims=," %%a in ('wmic OS get FreePhysicalMemory /format:csv') do (
    set "freeMemoryKB=%%a"
)
set /A freeMemoryMB=!freeMemoryKB:~0,-3!

if !freeMemoryMB! lss !memoryNeededMB! (
    echo Not enough free RAM to run !guestOS!. Exiting...
    timeout /t 5 >nul && popd && endlocal && exit /b 1
)

:: Define VM file path and check if it exists
set "vmFile=!vmsPath!\!guestOS!\!guestOS!.qcow2"
if exist "!vmFile!" (
    set /A vmFileExists=1
    echo A !guestOS! VM already exists,
    set /p choice="re-create it (Y,N): "
    
    if /i "!choice!"=="N" goto :configure_qemu
    
    del /F /Q "!vmFile!"
)

:: Create storage directory for VM if it doesn't exist
if NOT exist "!vmsPath!" ( mkdir "!vmsPath!" )

set "vmPath=!vmsPath!\!guestOS!"
if NOT exist "!vmPath!" ( mkdir "!vmPath!" )

:: Verify enough space for the VM
echo Verifying enough free storage space...
set /A spaceNeededGB=!baseSpaceNeededGB!

for %%a in (!isoFile!) do (
    set "fileSizeBytes=%%~za"
    set /A spaceNeededGB+=!fileSizeBytes:~0,-9!
)

set "freeSpaceBytes="
for /f "skip=5 tokens=3 delims= " %%a in ('dir !workDir! ^| findstr /C:"Total"') do ( 
    set "freeSpaceBytes=!retval:,=!"
)

set /A freeSpaceGB=!freeSpaceBytes:~0,-9!
if !freeSpaceGB! lss !spaceNeededGB! (
    echo Not enough free storage space available. Exiting...
    timeout /t 5 >nul && popd && endlocal && exit /B
)

:: Allocate storage space for the VM
echo Allocating storage space for the !guestOS! VM...
"!QEMU_IMG_EXE!" create -q -f qcow2 -o cluster_size=2M "!vmFile!" !spaceNeededGB!G >nul 2>&1 || (
    echo Failed to create the sparse image (VM). Exiting...
    timeout /t 5 >nul && popd && endlocal && exit /b 1
)

:: Convert the ISO to QCOW2 format for better performance
echo Converting selected !guestOS! ISO-file to a QCOW2-file...
"!QEMU_IMG_EXE!" convert -q -f raw -O qcow2 "!isoFile!" "!vmFile!" >nul 2>&1 || (
    echo Failed to convert the ISO-file. Exiting...
    timeout /t 5 >nul && popd && endlocal && exit /b 1
)

"!QEMU_IMG_EXE!" check -q "!vmFile!" >nul 2>&1 || (
    echo Conversion failed. Exiting...
    timeout /t 5 >nul && popd && endlocal && exit /b 1
)

:configure_qemu
echo Configuring QEMU...

:: Determine CPU core and thread count, adjusting for hyperthreading if necessary.
set /A hyperThreadingSupported=0
for /F "skip=1 tokens=2,3 delims=," %%a in ('wmic cpu get NumberOfCores,NumberOfLogicalProcessors /Format:csv') do (
    set cntCores=%%a
    set cntThreads=%%b
)
if !cntThreads! gtr !cntCores! ( set /A hyperThreadingSupported=1 )
set cntCores-=2 

:: Build QEMU arguments
set "qemuArgs=-L . -name !guestOS! -M q35 -drive file=!vmFile!,if=virtio,cache=writeback -cdrom !isoFile! -boot d -m !memoryNeededMB!M "
if !hyperThreadingSupported! equ 1 ( 
    set "qemuArgs=!qemuArgs!-smp cores=!cntCores!,threads=!cntThreads! "
) else ( 
    set "qemuArgs=!qemuArgs!-smp !cntCores! "
)
set "qemuArgs=!qemuArgs!-cpu host "

if "!firmwareType!"=="BIOS" (
    set "qemuArgs=!qemuArgs!-bios !ovmfFile! "
)

set "qemuArgs=!qemuArgs!-audiodev pa,id=snd0 "
if !isAndroidISO! equ 1 (
    set "qemuArgs=!qemuArgs!-append androidboot.hardware=android_x86 -device intel-hda -device hda-duplex -device virtio-gpu-pci -display gtk,gl=on "
) else (
    set "qemuArgs=!qemuArgs!-append root=/dev/sda1 quiet nomodeset -device virtio-vga-gl -display sdl,gl=on -device virtio-tablet -device virtio-keyboard -device AC97,audiodev=snd0 "
)

set "qemuArgs=!qemuArgs!-device usb-mouse -device usb-kbd -usb -net nic,model=virtio-net-pci "

if !isAndroidISO! equ 1 (
    set "qemuArgs=!qemuArgs!-net user,hostfwd=tcp::4444-:5555 "
) else (
    set "qemuArgs=!qemuArgs!-net user,hostfwd=tcp::2222-:22 "
)

if !kvmSupported! equ 1 (
    set "qemuArgs=!qemuArgs!-enable-kvm -accel whpx "
) else if !haxmIsRunning! equ 1 (
    set "qemuArgs=!qemuArgs!-accel hax "
)

set "qemuArgs=!qemuArgs!-rtc base=localtime -sandbox on -no-reboot"

:: Start the selected guest OS in QEMU
echo Starting !guestOS!...
timeout /t 3 >nul

popd && endlocal
start "" "!QEMU_EXE!" !qemuArgs! >nul 2>&1

