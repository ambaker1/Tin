#!/bin/bash
cd $(dirname -- "$0")
tclsh install.tcl
echo "Tin is now installed :)"
read -p "Press any key to continue ..."
