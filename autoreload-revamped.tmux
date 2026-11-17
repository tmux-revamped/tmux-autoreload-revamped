#!/bin/sh

autoreload_revamped_dir=$(cd "$(dirname "$0")" && pwd)
"${autoreload_revamped_dir}/bin/autoreload-revamped" apply
