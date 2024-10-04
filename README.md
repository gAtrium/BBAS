# Better Better ADB sync
Why fix a python script when you can write a new tool?

# BUGS
* Windows only for now
* RCE related to calling the adb pull, so be careful about that (Needs escaping special chars, i.e & on windows)
* ~~Should there be any unicode characters in the filename, pull operation will fail based on system's locale settings (Borks on windows)~~ (this needs testing on other unicode characters.)
* ~~Doesn't skip already present files if the path contains spaces~~

# Missing features
* Pushing to the device
* Cross-Sync (Syncing files that do not exist in one of the devices (Puller/Pullee))
* CHECKSUM mode, more resource intensive, but should ward off any questionmarks. (Should use an sqlite file)

# Features that could be neat if added in the future
* Android mode (android app that communicates over a reverse TCP shell to back up critical data such as contacts, messages etc)
* Wireless mode (Which would make the ADB in the title optional, so we would be left with Better Better Sync, and that acronym has long been taken)
* Recovery Mode (Needs a binary for target arch, we could pull partitions that require imaging and tar over computer)
* Be even more ambitious, too ambitious
* Find a better better name.
