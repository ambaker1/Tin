# Tin: A Tcl Package Manager

## Installing Tin

First install: 
* [Install Tcl](https://www.activestate.com/products/tcl/) and [install git](https://git-scm.com/book/en/v2/Getting-Started-Installing-Git).
* Download the [latest release of Tin](https://github.com/ambaker1/Tin/releases) and extract the files.
* Run the "InstallTin.bat" file, or run "install.tcl" in a Tcl interpreter.

Once Tin and git are installed, upgrading Tin is easy! Just copy the code below into a Tcl interpreter.

```tcl
package require tin
tin autoadd tin https://github.com/ambaker1/Tin install.tcl
tin upgrade tin
```

## Adding and Installing Packages

To install a package with Tin, there must be a unique repository-tag-file installation path for that version. For example, as shown below, the package "foo" version 1.0 can be installed by running the "install_foo.tcl" file in the repository "https://github.com/username/foo" with release tag "v1.0".

```tcl
package require tin
tin add foo 1.0 https://github.com/username/foo v1.0 install_foo.tcl
tin install foo
```

## Documentation

Full documentation [here](https://raw.githubusercontent.com/ambaker1/Tin/main/doc/tin.pdf).
