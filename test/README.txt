This is to spoof "ls-remote" on a local computer. An empty git repository is located in this folder, and its remote origin is specified as the folder "Tin-Test".
This empty repository should not be used, it is simply a workaround to allow local testing.
The original "Tin-Test" repository is hosted at https://github.com/ambaker1/Tin-Test

Code used to set this up:
git init .
git remote add Tin-Test Tin-Test