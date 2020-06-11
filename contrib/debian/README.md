
Debian
====================
This directory contains files used to package tbcd/tbc-qt
for Debian-based Linux systems. If you compile tbcd/tbc-qt yourself, there are some useful files here.

## tbc: URI support ##


tbc-qt.desktop  (Gnome / Open Desktop)
To install:

	sudo desktop-file-install tbc-qt.desktop
	sudo update-desktop-database

If you build yourself, you will either need to modify the paths in
the .desktop file or copy or symlink your tbc-qt binary to `/usr/bin`
and the `../../share/pixmaps/tbc128.png` to `/usr/share/pixmaps`

tbc-qt.protocol (KDE)

