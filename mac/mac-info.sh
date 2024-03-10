#!/bin/bash
# Prints out one-line info about this Mac

# Store output of sw_vers into variables
os_name="$(sw_vers -productName)"
os_version="$(sw_vers -productVersion)"
os_build="$(sw_vers -buildVersion)"

# https://apple.stackexchange.com/a/333470/6278
os_friendly_name="$(awk '/SOFTWARE LICENSE AGREEMENT FOR macOS/' '/System/Library/CoreServices/Setup Assistant.app/Contents/Resources/en.lproj/OSXSoftwareLicense.rtf' \
    | awk -F 'macOS ' '{print $NF}' \
    | awk '{print substr($0, 0, length($0)-1)}')"

# Get Model Identifier from system_profiler
model_identifier="$(system_profiler SPHardwareDataType | sed -n 's/.*Model Identifier: //p')"
chip="$(system_profiler SPHardwareDataType | sed -n 's/.*Chip: //p')"

arch="$(arch)"

echo "$os_name $os_version $os_build ($os_friendly_name) $model_identifier ($chip, $arch)"
