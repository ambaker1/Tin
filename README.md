# Tin: A Tcl Package Manager

## Installing Tin

First install: 
* [Install Tcl](https://www.activestate.com/products/tcl/) and [install git](https://git-scm.com/book/en/v2/Getting-Started-Installing-Git)
* Download the [latest release of Tin](https://github.com/ambaker1/Tin/releases) and extract the files.
* Run the InstallTin.bat file, or run "install.tcl" in a Tcl interpreter.

Once Tin and git are installed, upgrading Tin is easy!
```tcl
package require tin
tin upgrade tin
```

## Available Packages

Tin comes pre-packaged with a [database](tinlist.tcl) of packages that can be installed directly from GitHub.
If a package is not on the list, it can easily be added and then installed as shown below:
```tcl
package require tin
tin add foo 1.0 https://github.com/username/foo v1.0 install_foo.tcl
tin install foo
```

## Documentation

Full documentation [here](https://raw.githubusercontent.com/ambaker1/Tin/main/doc/tin.pdf).
