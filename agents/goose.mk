# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026  Wladmis <dev@wladmis.org>

HOMEURL = https://github.com/aaif-goose/goose/releases/latest
INST    = scr
LINK    = https://github.com/aaif-goose/goose/releases/download/stable/download_cli.sh
BIN     = goose
WRITABLE_DIRS = .config/goose .local/share/goose .local/state/goose
READABLE_DIRS =
SCR_ENV = CONFIGURE=false

# bzip2 is needed to install goose
PACKAGES = bzip2
