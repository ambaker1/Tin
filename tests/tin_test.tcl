# First install
cd ..
source installer.tcl
# Upgrade
package forget tin
package require tin
tin install tin
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
bar


