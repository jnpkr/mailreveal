#!/bin/zsh

set -euo pipefail

project_dir="${0:A:h:h}"
sdk_path="${SDKROOT:-$(xcrun --sdk macosx --show-sdk-path)}"
real_swiftc="$(xcrun --find swiftc)"
architecture="$(uname -m)"
cache_root="${TMPDIR:-/tmp}/mailreveal-swift-cache"

mkdir -p "${cache_root}/clang" "${cache_root}/swiftpm"
export SDKROOT="${sdk_path}"
export CLANG_MODULE_CACHE_PATH="${cache_root}/clang"
export SWIFTPM_MODULECACHE_OVERRIDE="${cache_root}/swiftpm"

if ! "${real_swiftc}" \
	-sdk "${sdk_path}" \
	-target "${architecture}-apple-macosx13.0" \
	-module-cache-path "${cache_root}/clang" \
	-typecheck /dev/null >/dev/null 2>&1; then
	interface_file="${sdk_path}/usr/lib/swift/Swift.swiftmodule/arm64e-apple-macos.swiftinterface"
	if [[ ! -f "${interface_file}" ]]; then
		echo "The active macOS SDK is incompatible with the Swift compiler." >&2
		exit 1
	fi

	interface_compiler_version="$(sed -n 's|^// swift-compiler-version: ||p' "${interface_file}" | head -n 1)"
	if [[ -z "${interface_compiler_version}" ]]; then
		echo "Could not determine the compiler version used by the active macOS SDK." >&2
		exit 1
	fi

	export MAILREVEAL_REAL_SWIFTC="${real_swiftc}"
	export MAILREVEAL_INTERFACE_COMPILER_VERSION="${interface_compiler_version}"
	export SWIFT_EXEC="${project_dir}/Scripts/swiftc-compatible.sh"
fi

cd "${project_dir}"

if [[ "${1:-}" == "test" ]]; then
	developer_root="$(xcode-select -p)/Library/Developer"
	developer_frameworks="${developer_root}/Frameworks"
	developer_libraries="${developer_root}/usr/lib"
	exec swift "$@" \
		--enable-swift-testing \
		--disable-xctest \
		-Xswiftc -F \
		-Xswiftc "${developer_frameworks}" \
		-Xlinker "-F${developer_frameworks}" \
		-Xlinker -rpath \
		-Xlinker "${developer_frameworks}" \
		-Xlinker -rpath \
		-Xlinker "${developer_libraries}"
fi

exec swift "$@"
