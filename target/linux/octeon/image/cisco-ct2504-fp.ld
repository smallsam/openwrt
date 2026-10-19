/* SPDX-License-Identifier: GPL-2.0-or-later */
/*
 * The boot loader maps the memory of the application it starts after the
 * segments of its ELF file and resets the board if they are small. This
 * has the layout of the application which ships with the unit: code, data
 * and a large zero-filled segment.
 */
ENTRY(_start)
PHDRS
{
	text PT_LOAD FLAGS(5);
	data PT_LOAD FLAGS(6);
	bss PT_LOAD FLAGS(6);
}
SECTIONS
{
	. = 0x10000018;
	.text : { . = 0x140; *(.text) } :text
	. = 0x12226458;
	.data : { *(.data) } :data
	. = 0x14000000;
	.bss : { *(.bss) *(COMMON) } :bss
	/DISCARD/ : { *(.MIPS.abiflags) *(.reginfo) *(.gnu.attributes) *(.comment) *(.pdr) *(.mdebug*) }
}
