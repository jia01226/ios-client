"""写 ExportOptions.plist：手机必带，手表有描述文件就一起写。"""
import os
import plistlib
import sys

method = os.environ.get("EXPORT_METHOD", "ad-hoc")
profiles = {}
if os.environ.get("PROFILE_NAME", "").strip():
    profiles[os.environ["BUNDLE_ID"]] = os.environ["PROFILE_NAME"]
watch = os.environ.get("WATCH_PROFILE_NAME", "").strip()
if watch:
    profiles[os.environ["BUNDLE_ID"] + ".watchkitapp"] = watch

options = {
    "method": method,
    "signingStyle": os.environ.get("EXPORT_SIGNING", "manual"),
    "teamID": os.environ["TEAM_ID"],
}
if profiles:
    options["provisioningProfiles"] = profiles
with open(sys.argv[1], "wb") as f:
    plistlib.dump(options, f)
print(profiles)
