# First install
cd ..
source installer.tcl

tin add foo 1.0 https://github.com/username/foo v1.0 install_foo.tcl
catch {tin require foo 1.0} result; # will ask to install from github
puts $result

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

puts [package present tin]

puts [tin install wob]


