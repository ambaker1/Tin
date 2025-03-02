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

## Configuring Installation files
If you are developing your package to be compatible with Tin, there must be a Tcl file in your repository that can be run to install the package. 
Here is a simple example of an installation file that just copies specific files to a library directory:

```tcl
# Install dependency
package require tin
tin add bar 1.2 https://github.com/username/bar v1.2 install_bar.tcl
tin depend bar 1.2

# Copy files over to library folder
set dir [tin mkdir -force foo 1.0]
file copy README.md LICENSE foo.tcl pkgIndex.tcl $dir
```

If your package has binary release files on GitHub, such as .exe installers or .zip archives, the installation file can be modified as shown below, using [GitHub CLI](https://cli.github.com/) to download the release assets. 

```tcl
# Install dependency
package require tin
tin add bar 1.2 https://github.com/username/bar v1.2 install_bar.tcl
tin depend bar 1.2

# Use GitHub CLI to download release assets (InstallFoo1.0.exe and foo1.0.zip)
exec gh release download v1.0 --clobber; # --clobber overwrites

# Customize installation for operating system
switch -- $::tcl_platform(os) {
    Windows {
        # Run binary installation file
        exec InstallFoo1.0.exe
    }
    default {
        # Extract zip folder, and install contents to library folder
        package require zipfile::decode 0.7.1
        ::zipfile::decode::unzipfile foo1.0.zip [pwd]
        set dir [tin mkdir -force foo 1.0]
        set files [glob -directory foo1.0 *]
        file copy {*}$files $dir
    }
}
```

## Documentation

Full documentation [here](https://raw.githubusercontent.com/ambaker1/Tin/main/doc/tin.pdf).
