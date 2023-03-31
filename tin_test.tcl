# tin_test.tcl
source tin.tcl
tin extract tin
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