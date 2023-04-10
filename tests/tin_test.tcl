# First install
cd ..
source installer.tcl
<<<<<<< Updated upstream
# "Upgrade"
package forget tin
package require tin
puts [tin install tin]
=======
# Upgrade
# package forget tin
# package require tin
# puts [tin install tin]
>>>>>>> Stashed changes
# Importing commands
# tin add foo 1.0 https://github.com/username/foo v1.0 install_foo.tcl
# package require bar

package forget tin
<<<<<<< Updated upstream
puts [package require tin]
=======
package require tin

tin add foo 1.0 https://github.com/username/foo v1.0 install_foo.tcl
catch {tin require foo 1.0} result; # will ask to install from github
puts $result


# package require bar


>>>>>>> Stashed changes
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



