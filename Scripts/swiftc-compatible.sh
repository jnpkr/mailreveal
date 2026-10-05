#!/bin/zsh

set -euo pipefail

if [[ -z "${MAILREVEAL_REAL_SWIFTC:-}" || -z "${MAILREVEAL_INTERFACE_COMPILER_VERSION:-}" ]]; then
	echo "MailReveal Swift compiler compatibility environment is incomplete." >&2
	exit 2
fi

exec "${MAILREVEAL_REAL_SWIFTC}" \
	-interface-compiler-version "${MAILREVEAL_INTERFACE_COMPILER_VERSION}" \
	"$@"
