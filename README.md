The idea of this project is to have a test environment on a USB stick that allows both Android OSs and Linux OSs to run without the need to set up a dual-boot on the Windows computer using QEMU (Quick EMUlator) what is a free and open-source emulator and virtualizer that can emulate a full system, including a processor, memory, hence allowing you to run a guest operating system within it.

So you need a high-speed USB-C stick on which a copy of QEMU and the .ISO file of the OSs to be tested are installed.

The minimum storage capacity of the USB-C stick needed can be calculated as follows: 20 GB per virtual machine what QEMU creates, plus the amount of GBs the .ISO files housed, plus the GBs used by QEMU itself.

The main folder layout of the USB stick would be:

qemu
iso
	\ android
	\ linux

In addition there is file named autoexec.bat

Because on Windows 11 the AutoRun feature is disabled by default you have to add a batch file to Windows startup that runs the autoexec.bat file housed on the USB stick. Here's how you can do it:

1. Create a Batch File named run_usb_autoexec.bat what contains following lines:

@echo off
start /d "E:\path\to\usb\stick" autoexec.bat 2>nul

Important
Replace "E:\path\to\usb\stick" with the actual path to your USB stick.

2. Add to it to Startup: Press Win + R, type shell:startup, and press Enter. This will open the Startup folder

3. Copy the run_usb_autoexec.bat file from its location to the Startup folder


When you restart your Windows computer, the batch file will run and execute the autoexec.bat file on the USB stick.
