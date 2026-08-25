# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026  Alexey Gladkov <gladkov.alexey@gmail.com>

HOMEURL = https://github.com/openai/codex/releases/latest
INST    = npm
LINK    = @openai/codex
BIN     = codex
WRITABLE_DIRS = .codex
READABLE_DIRS =
SCR_ENV =

SASHIKO.agent.options = --dangerously-bypass-approvals-and-sandbox
