# First install
cd ..
source installer.tcl
# Upgrade
# package forget tin
# package require tin
# puts [tin install tin]
# Importing commands
package forget tin
package require tin
namespace eval ::foo {
    namespace export bar
}
proc ::foo::bar {} {
    puts hi
}
package provide foo 1.0
tin import foo
bar; # should print "hi"
puts [tin library]
tin library [info library]
puts [tin library]

tin import -force import from tin 0.3

import require from tin
puts [require Tcl] 


