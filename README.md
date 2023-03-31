# Tin
Tcl package manager. 

## How to install and use Tin:

First install: Download the latest release, extract the files, and run the following code within the download folder:
```tcl
source tin.tcl
tin extract tin
```

Once installed, upgrading tin is easy!
```tcl
package require tin
tin install tin
```

Full documentation [here](doc/tin.pdf).

## How to make a Tin package

To make your Tcl package tin-compatible, simply add a "tinstall.tcl" file to your main repository folder. 
The "tinstall.tcl" file should copy required files from the main repository folder to the Tcl library folder, represented by variables $src and $dir, respectively.
Additionally, the "tinstall.tcl" file must contain a "tin provide" statement at the end of the file with the package name and version.
If your tin package requires other tin packages, dependencies can be handled with the "tin depend" command. 

See example "tinstall.tcl" file for the package "bar 2.4" that requires the package "foo 1.2":
```tcl
tin depend foo 1.2
file copy [file join $src README.md] $dir
file copy [file join $src LICENSE] $dir
file copy [file join $src lib/bar.tcl] $dir
file copy [file join $src lib/pkgIndex.pdf] $dir
tin provide bar 2.4
```
Including a "tinstall.tcl" file will make the repository compatible with the "tin extract" command, but to make it compatible with the "tin install" command, which allows for automatic installation from GitHub, the repository must also have release tags with the format v0.0.0

## Adding a package to Tin

Tin comes pre-packaged with a list of compatible repositories, listed [here](tin.txt).
To add a repository that is not on this list, either fork this repostiory and submit a pull request to add it to the list, or use "tin add" to add it manually, as shown below:

```tcl
package require tin
tin add foo https://github.com/username/foo
tin install foo
```


