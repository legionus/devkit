#!/bin/sh -efu
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026  Alexey Gladkov <gladkov.alexey@gmail.com>

scr="$(realpath "$0")"
cwd="${scr%/*}"

export PROG="${scr##*/}"

exec make -f "$cwd/devkit.mk" -- "$@"
