# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026  Alexey Gladkov <gladkov.alexey@gmail.com>
# Copyright (C) 2026  Wladmis <dev@wladmis.org>

HOMEURL = https://github.com/Aider-AI/aider/releases/latest
# Use upstream installer to provision Aider's required Python 3.12.
INST    = scr
LINK    = https://aider.chat/install.sh
BIN     = aider
CONFDIR = .aider
DATADIR =
SCR_ENV =

CONFFILES = .aider.conf.yml .aider.model.metadata.json .aider.model.settings.yml
