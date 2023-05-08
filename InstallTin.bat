@echo off
cd "%~dp0"
tclsh install.tcl || goto :error
echo Tin is now installed :) 
pause
goto :EOF

:error
echo Failed to install Tin :(
pause
exit /b %errorlevel%
