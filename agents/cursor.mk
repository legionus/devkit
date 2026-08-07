# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026  Alexey Gladkov <gladkov.alexey@gmail.com>

HOMEURL = https://cursor.com/docs/agent/overview
INST    = scr
LINK    = https://cursor.com/install
BIN     = cursor-agent
CONFDIR = .cursor
DATADIR =
SCR_ENV =

RELEASE_URL = https://api2.cursor.sh/updates/download/golden/linux-x64/cursor/
RELEASE_CMD = $(CURL) -fsSLI -o /dev/null -w '%{url_effective}' $(RELEASE_URL) | sed -n 's,.*/Cursor-\(.*\)-x86_64.AppImage,\1,p'
