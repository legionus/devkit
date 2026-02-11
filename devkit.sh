#!/bin/sh -efu
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026  Alexey Gladkov <gladkov.alexey@gmail.com>

scr="$(realpath "$0")"
cwd="${scr%/*}"

PROG="${scr##*/}"

a=
i="$#"
while [ "$i" -gt 0 ] && [ "$a" != 'shell' ] && [ "$a" != 'run' ]; do
	a="$1"
	set -- "$@" "$a"
	shift
	i=$(( $i - 1 ))
done

NARGS=0
while [ "$i" -gt 0 ]; do
	eval "ARG${NARGS}=\"\$1\""
	eval "export ARG${NARGS}"
	NARGS=$(( $NARGS + 1 ))
	shift
	i=$(( $i - 1 ))
done
export PROG NARGS

exec make -f "$cwd/devkit.mk" -- "$@"
