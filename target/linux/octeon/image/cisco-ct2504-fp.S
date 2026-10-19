/* SPDX-License-Identifier: GPL-2.0-or-later */
/*
 * Replacement for the data plane application ("cavium_main") that the Cisco
 * WLCNG boot loader starts on cores 0 and 1 of the AIR-CT2504.
 *
 * Each core flags in bit 31 of its CIU mailbox that it is parked and waits
 * for Linux (see the octeon SMP code) to write the physical address of the
 * kernel entry point to the mailbox, then jumps there.
 */
	.set	noreorder
	.set	mips64r2
	.globl	_start
	.text
_start:
	rdhwr	$8, $0			/* core id */
	dsll	$9, $8, 3
	dli	$10, 0x8001070000000600	/* CIU_MBOX_SET0 */
	dli	$11, 0x8001070000000680	/* CIU_MBOX_CLR0 */
	daddu	$10, $10, $9
	daddu	$11, $11, $9
	lui	$12, 0x8000		/* 0xffffffff80000000 */
	sd	$12, 0($10)		/* advertise "parked" in bit 31 */
1:	ld	$13, 0($11)
	and	$14, $13, $12
	bnez	$14, 1b			/* still our own marker */
	 nop
	beqz	$13, 1b			/* nothing yet */
	 nop
	daddiu	$15, $0, -1
	sd	$15, 0($11)		/* ack, clear mailbox */
	or	$13, $13, $12		/* physical -> ckseg0 address */
	move	$4, $0
	move	$5, $0
	move	$6, $0			/* a2 = 0: not the init core */
	jr	$13
	 move	$7, $0

	.data
	.quad	0

	/* see cisco-ct2504-fp.ld */
	.bss
	.comm	fp_memory, 0xb3b4f0, 16
