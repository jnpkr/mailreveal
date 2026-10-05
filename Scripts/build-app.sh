#!/bin/zsh

set -euo pipefail

project_dir="${0:A:h:h}"
app_dir="${project_dir}/dist/MailReveal.app"
contents_dir="${app_dir}/Contents"

cd "${project_dir}"
"${project_dir}/Scripts/swiftpm.sh" build -c release

rm -rf "${app_dir}"
mkdir -p "${contents_dir}/MacOS" "${contents_dir}/Resources"
cp ".build/release/MailReveal" "${contents_dir}/MacOS/MailReveal"
cp "App/Info.plist" "${contents_dir}/Info.plist"
osacompile -o "${contents_dir}/Resources/RevealMessage.scpt" "Scripts/RevealMessage.applescript"
plutil -lint "${contents_dir}/Info.plist"
codesign \
	--force \
	--sign - \
	--requirements '=designated => identifier "app.mailreveal.utility"' \
	"${app_dir}"

echo "Built ${app_dir}"
