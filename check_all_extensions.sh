#!/usr/bin/env bash
# -*- coding: utf-8 -*-
#
# DESCRIPTION: Check installed Chromium-based browser extensions against a list
#              of known spying/malicious extensions.
#
# USAGE: ./check_all_extensions.sh
#
# HOW IT WORKS:
#   1. Iterates through supported Chromium-based browsers (Chrome, Chromium,
#      Brave, Vivaldi, Comet)
#   2. Finds all installed extension IDs in each browser's Extensions folder
#   3. Uses jq to extract extension names from each extension's manifest.json
#   4. Outputs extension ID,name pairs to _instaladas_N.txt files
#   5. Compares against bad_extensions.txt to find matches
#
# DEPENDENCIES: jq (for JSON parsing)
#
# SOURCES:
#   bad_extensions.txt from:
#   - https://qcontinuum.substack.com/p/spying-chrome-extensions-287-extensions-495
#   - https://github.com/qcontinuum1/spying-extensions
#
# VERSION: 0.0.2
#
# AUTHOR: Jordi Roca
# CREATED: 2026/02/12 23:56
#
# GITHUB: https://github.com/jordiroca/check_chrome_leaking_extensions
#
# LICENSE: See LICENSE file.
#

# Check for jq dependency
if ! command -v jq &>/dev/null; then
  echo "Error: jq is required but not installed."
  echo "Install with: brew install jq"
  exit 1
fi

echo "Checks installed extensions in Chromium-based browsers against a list of known spying/malicious extensions."
echo "Searching for leaking browser extensions in all profiles..."

declare -A BROWSERS=(
  ["Chrome"]="Google/Chrome"
  ["Chromium"]="Chromium"
  ["Brave"]="BraveSoftware/Brave-Browser"
  ["Vivaldi"]="Vivaldi"
  ["Comet"]="Comet"
)
first=true
echo -n "Checking Browsers: "
for slug in "${!BROWSERS[@]}"; do
  B="${BROWSERS[$slug]}"
  BASE="$HOME/Library/Application Support/$B"
  if [ -d "$BASE" ]; then
    if [ "$first" = true ]; then
      first=false
    else
      echo -n " | "
    fi
    echo -n "$slug"
    echo "# $B" > "Extensiones $slug"
    
    # Find all profile directories (Default, Profile 1, Profile 2, etc.)
    while IFS= read -r profile_dir; do
      profile_name=$(basename "$profile_dir")
      extensions_dir="$profile_dir/Extensions"
      
      if [ -d "$extensions_dir" ]; then
        # Find all extension directories and extract ID,name pairs
        while IFS= read -r ext_dir; do
          ext_id=$(basename "$ext_dir")
          # Find the manifest.json in the version subdirectory
          manifest=$(find "$ext_dir" -name "manifest.json" -type f 2>/dev/null | head -1)
          if [ -n "$manifest" ]; then
            ext_name=$(jq -r '.name // "unknown"' "$manifest" 2>/dev/null)
            # Resolve __MSG_*__ placeholders from _locales
            if [[ "$ext_name" =~ ^__MSG_(.+)__$ ]]; then
              msg_key="${BASH_REMATCH[1]}"
              ext_dir_base=$(dirname "$manifest")
              # Try en, en_US, then first available locale
              for locale in en en_US; do
                messages_file="$ext_dir_base/_locales/$locale/messages.json"
                if [ -f "$messages_file" ]; then
                  resolved=$(jq -r --arg key "$msg_key" '.[$key].message // .[$key | ascii_downcase].message // empty' "$messages_file" 2>/dev/null)
                  if [ -n "$resolved" ]; then
                    ext_name="$resolved"
                    break
                  fi
                fi
              done
              # Fallback: try first available locale
              if [[ "$ext_name" =~ ^__MSG_ ]]; then
                first_locale=$(find "$ext_dir_base/_locales" -maxdepth 1 -type d 2>/dev/null | head -2 | tail -1)
                if [ -n "$first_locale" ] && [ -f "$first_locale/messages.json" ]; then
                  resolved=$(jq -r --arg key "$msg_key" '.[$key].message // .[$key | ascii_downcase].message // empty' "$first_locale/messages.json" 2>/dev/null)
                  if [ -n "$resolved" ]; then
                    ext_name="$resolved"
                  fi
                fi
              fi
            fi
            echo "${ext_id},${slug},${profile_name},\"${ext_name}\"" >> "Extensiones $slug"
          else
            echo "${ext_id},${slug},${profile_name},\"unknown\"" >> "Extensiones $slug"
          fi
        done < <(find "$extensions_dir" -maxdepth 1 -type d 2>/dev/null | grep -v "^$extensions_dir$" | sort -u)
      fi
    done < <(find "$BASE" -maxdepth 1 -type d \( -name "Default" -o -name "Profile *" \) 2>/dev/null | sort)
  fi
done

echo -e "\n\nFound extensions:"

# Check for bad extensions across all browsers
echo "Extension ID,Browser,Profile,Extension Name" > resultado.csv
cat bad_extensions.txt | sort -u | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -v "^$" | while read a; do grep -h "$a" "Extensiones "*; done | sed 's/Extensiones //' >> resultado.csv
if command -v tw &>/dev/null; then
  tw resultado.csv
else
  echo "----------------"
  column -t -s',' resultado.csv
fi
