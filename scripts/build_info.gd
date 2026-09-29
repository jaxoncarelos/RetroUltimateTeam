class_name BuildInfo
extends RefCounted
## Build stamp shown on the title screen so you can tell which build is installed.
## CI overwrites this file with the commit id (and the OTA update repo/token) before exporting.

const ID := "dev"
const REPO := ""
const TOKEN := ""
