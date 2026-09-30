	page	59,132
	title	UDVD2 -- DOS UltraDMA CD/DVD Driver.
;
; UDVD2 is an UltraDMA driver for up to 4 SATA, IDE, and old PIO-mode
; CD/DVD drives.   On loading, it checks up to 9 SATA/IDE controllers
; and runs the first 4 drives found.    UDVD2 reads data files, plays
; audio CDs, and inputs "raw" trackwriter data.   If the UHDD caching
; driver is in use, UDVD2 will call it to cache CD/DVD data files and
; directories for FAR more speed!   (Audio/trackwriting is uncached).
;
; UDVD2 uses 144 bytes of upper/DOS memory and 1824 bytes of HMA with
; a /H switch, or 1968 bytes of memory without /H.   Caching via UHDD
; adds 80 bytes, and UDVD2 "shares" UHDD's XMS buffer, for misaligned
; or other input unsuited to UltraDMA.   Without UHDD, UDVD2 requires
; 128K of XMS memory as its own buffer for such input.
;
;
; General Program Equations.
;
	.386			;Allow use of 80386 instructions.
s	equ	<short>		;Make a conditional jump "short".
CDUNIT	equ	40		;CD/DVD initial cache-unit number.
CDTYP	equ	07Ch		;CD/DVD device-type code.
RMAXLBA	equ	00006DD39h	;Redbook (audio) maximum LBA value.
COOKSL	equ	2048		;CD/DVD "cooked" sector length.
RAWSL	equ	2352		;CD/DVD "raw" sector length.
CMDTO	equ	00Ah		;CD/DVD 500-msec min. command timeout.
SEEKTO	equ	037h		;CD/DVD 3-second min. "seek"  timeout.
STARTTO	equ	07Fh		;CD/DVD 7-second startup timeout.
BIOSTMR equ	0046Ch		;BIOS "tick" timer address.
VDSFLAG equ	0047Bh		;BIOS "Virtual DMA" flag address.
HDI_OFS	equ	0048Eh-BIOSTMR	;BIOS hard-disk int. flag "offset".
GENERR	equ	00Ch		;CD/DVD "general error" return code.
XMSERR	equ	0FFh		;XMS "memory error" return code.
IXM	equ	4096		;IOCTL transfer-length multiplier.
CR	equ	00Dh		;ASCII carriage-return.
LF	equ	00Ah		;ASCII line-feed.
TAB	equ	009h		;ASCII "tab".
;
; Fixed UHDD Driver Offsets, used by our caching routines below.
;
UHAttr	equ	word ptr  004h	;UHDD "attributes", always 08000h.
UHXHdl	equ	word ptr  008h	;UHDD XMS "handle" number.
UHNam1	equ	dword ptr 00Ah	;UHDD device name, "UHDD$" if caching
UHNam2	equ	dword ptr 00Eh	;  or "UHDD-SA$" for stand-alone dvr.
UHFlag	equ	byte ptr  013h	;UHDD I-O control flags.
UHCalB	equ	dword ptr 014h	;UHDD "callback routine" pointer.
UHType	equ	byte ptr  01Bh	;UHDD device "type", 07Ch if CD/DVD.
UHEntr	equ	000A0h		;UHDD user-driver "entry" offset.
;
; "Legacy IDE" Controller I-O Base Addresses.
;
NPDATA	equ	001F0h		;Normal primary      base address.
NSDATA	equ	00170h		;Normal secondary    base address.
APDATA	equ	001E8h		;Alternate primary   base address.
ASDATA	equ	00168h		;Alternate secondary base address.
;
; IDE Controller Register Offsets.
;
CDATA	equ	0		;Data port offset.
CDSEL	equ	6		;Disk-select and upper LBA offset.
CCMD	equ	7		;Command-register offset.
CSTAT	equ	7		;Primary-status register offset.
;
; Controller Status and Command Definitions.
;
BSY	equ	080h		;IDE controller is busy.
RDY	equ	040h		;IDE disk is "ready".
FLT	equ	020h		;IDE disk has a "fault".
DRQ	equ	008h		;IDE data request.
ERR	equ	001h		;IDE general error flag.
DMI	equ	004h		;DMA interrupt occured.
DME	equ	002h		;DMA error occurred.
MSEL	equ	0A0h		;"Master" device-select bits.
SSEL	equ	0B0h		;"Slave"  device-select bits.
DRCMD	equ	0C8h		;DMA read command (write is 0CAh,
				;    LBA48 commands are 025h/035h).
LBABITS equ	0E0h		;Fixed LBA command bits.
;
; Byte, Word, and Double-Word Definitions.
;
BDF	struc
lb	db	?
hb	db	?
BDF	ends

WDF	struc
lw	dw	?
hw	dw	?
WDF	ends

DDF	struc
dwd	dd	?
DDF	ends
;
; DOS "Request Packet" Layout.
;
RP	struc
RPHLen	db	?		;Header byte count.
RPSubU	db	?		;Subunit number.
RPOp	db	?		;Opcode.
RPStat	dw	?		;Status word.
	db	8 dup (?)	;(Unused by us).
RPUnit	db	?		;Number of units found.
RPLen	dw	?		;Resident driver 32-bit length.
RPSeg	dw	?		;(Segment must ALWAYS be set!).
RPCL	dd	?		;Command-line data pointer.
RP	ends
RPERR	equ	08003h		;Packet "error" flags.
RPDON	equ	00100h		;Packet "done" flag.
RPBUSY	equ	00200h		;Packet "busy" flag.
;
; IOCTL "Request Packet" Layout.
;
IOC	struc
	db	13 dup (?)	;Request "header" (unused by us).
	db	?		;Media descriptor byte (unused by us).
IOCAdr	dd	? 		;Data-transfer address.
IOCLen	dw	?		;Data-transfer length.
	dw	?		;Starting sector (unused by us).
	dd	?		;Volume I.D. pointer (unused by us).
IOC	ends
;
; Read Long "Request Packet" Layout.
;
RL	struc
	db	13 dup (?)	;Request "header" (unused by us).
RLAM	db	?		;Addressing mode.
RLAddr	dd	?		;Data-transfer address.
RLSC	dw	?		;Data-transfer sector count.
RLSec	dd	?		;Starting sector number.
RLDM	db	?		;Data-transfer mode.
RLIntlv	db	?		;Interleave size.
RLISkip	db	?		;Interleave skip factor.
RL	ends
;
; Segment Declarations.
;
CODE	segment	public use16 'CODE'
	assume	cs:CODE,ds:CODE
;
; DOS Driver Device Header.
;
@	dd	0FFFFFFFFh	;Link to next header block.
	dw	0C800h		;Driver "device attributes".
StratP	dw	(I_Stra-@)	;"Strategy" routine pointer.
	dw	(I_Init-@)	;Device-Interrupt routine pointer.
DvrNam	db	'UDVD1   '	;Driver name for our CD Redirector.
;
; General Driver "Base Page" Variables.
;
VLF	db	0		;VDS "lock" flag (01h = buffer lock).
RXF	db	0		;Reset UHDD busy (01h = reset needed).
	db	0		;First assigned drive letter.
CDUnits	db	0		;Number of CD/DVD drives (1 thru 6).
UHSeg	dw	0		;UHDD driver segment, if UHDD is used.
DMAAd	dw	0		;DMA status/command register address.
IdeDA	dw	0		;IDE data register address.
AudAP	dw	0		;Audio-start address pointer.
UserL	dw	0		;Working I-O buffer length.
UserB	dd	0		;Working I-O buffer address.
RqPkt	dd	0		;Request I-O packet address.
;
; ATAPI "Packet" Area (always 12 bytes for a CD/DVD).
;
Packet	db	0		;Opcode.
	db	0		;Unused (LUN and reserved).
PktLBA	dd	0		;CD/DVD logical block address.
PktLH	db	0		;"Transfer length" (sector count).
PktLn	dw	0		;Middle- and low-order sector count.
PktRM	db	0		;Read mode ("Raw" Read Long only).
	dw	0		;Unused ATAPI "pad" bytes (required).
;
; VDS Parameter Block and UltraDMA Command-List.
;
VDSLn	dd	(LMEnd-@)	;VDS block length.
VDSOf	dd	0		;VDS 32-bit buffer offset.
VDSSg	dd	0		;VDS 16-bit segment (hi-order zero).
IOAdr	dd	0		;VDS/DMA 32-bit buffer address.
IOLen	dd	080000000h	;DMA byte count and "end" flag.
;
; CD/DVD Audio Function Buffer (16 bytes), for most CD/DVD "audio"
;   requests.   Its variables shown below are only for driver Init.
;
InBuf	equ	$
UTblP	dw	UTable		;Initialization unit table pointer.
NoDMA	db	0		;"No UltraDMA" flag.
UMode	dw	0		;UltraDMA "mode select" bits.
UFlag	db	0		;UltraDMA "mode valid" flags.
USNdx	db	0		;Unit-select index.
USelB	db	082h		;PCI "modes" and unit-select byte.
DvdTP	dw	(Ctl1Tbl-@)	;UltraDMA address-table pointer.
HFlag	db	0		;"Use HMA space" flag.
PCI_IF	db	082h		;Current PCI "interface bit" value.
XMSRsv	dw	0		;Desired "reserved" XMS memory.
	db	0,0		;(Unused alignment "filler").
;
; DOS "Strategy" Routine.
;
Strat:	push	es		;Save DOS request-packet address.
	push	bx
	pop	cs:RqPkt
	retf			;Exit & await DOS "Device Interrupt".
;
; Miscellaneous Driver "Base Page" Variables, set here for alignment.
;
Try	db	0		;Input retry counter.
XMF	db	0		;XMS move  flag (01h if so).
DMF	db	0		;DMA input flag (01h if so).
;
; DOS Device-Interrupt Routine.
;
DevInt:	pushf			;Save CPU flags.
	pushad			;Save all 32-bit CPU registers.
	push	ds		;Save CPU segment registers.
	push	es
	sti			;Ensure CPU interrupts are enabled.
	mov	ah,005h		;Issue "A20 local-enable" request.
A20Ena	db	090h		;(Set to 09Ah by Init if using HMA.
@XMgr1:	clc			; Without HMA, these commands shall
	mov	ax,00001h	; return a "No XMS error" status).
	lds	si,cs:RqPkt	   ;Get DOS request-packet address.
	mov	[si].RPStat,0810Ch ;Post default "general error".
	dec	ax		   ;Any "A20 enable" errors?
	jnz s	DvIntE		   ;Yes?  Abandon request and exit!
	db	0EAh		;Go to main CD/DVD request handler.
@CDMain	dd	(CDReq-@)	;(CD/DVD request address, Init set).
DvIntX:	mov	ah,006h		;Issue "A20 local-disable" request.
A20Dis	db	090h		;(Set to 09Ah by Init if using HMA.
@XMgr2:	xchg	bx,bx		; Without HMA, these four bytes are
	xchg	bx,bx		; a set of "no-ops").
DvIntE:	pop	es		;Reload CPU segment registers.
	pop	ds
	popad			;Reload all 32-bit CPU registers.
	popf			;Reload CPU flags and exit.
	retf
LMEnd	equ	$		;End of driver low-memory data/logic.
				;  All beyond here can go in the HMA.
;
; Main CD/DVD request handler.
;
CDReq:	call	XMSRst		  ;Make all critical driver settings.
	mov	[bx+XMF-@],bx	  ;Reset XMS-move & DMA-input flags.
	call	ClrPkt		  ;Clear our ATAPI packet area.
@XBusy:	jmp s	CDReq1		  ;If not using UHDD, skip busy test.
	db	(UHSeg-@)	  ;("mov es,[bx+UHSeg-@]" with UHDD).
	bts	word ptr es:[bx].UHFlag,bx ;Is UHDD currently "busy"?
	jc	CDReqX		  ;Yes?  Exit with "general error"!
	mov	[bx+RXF-@].lb,01h ;Reset UHDD "busy" after this req.
CDReq1:	mov	ax,RPDON	  ;Reload request-packet address and
	call	RqStat		  ;  change packet status to "done".
	mov	al,18		  ;Set drive's "audio-start" ptr.
	mul	es:[si+RPSubU].lb
	add	ax,offset (UTable+6-@)
@UTable	equ	[$-2].lw
	xchg	ax,di
	mov	[bx+AudAP-@],di
	mov	eax,cs:[di-6]	      ;Set drive DMA/IDE addresses.
	mov	[bx+DMAAd-@],eax
	mov	al,es:[si+RPOp]	      ;Get packet request code.
	mov	di,offset (DspTbl2-@) ;Get DOS dispatch-table ptr.
@DspTB2	equ	[$-2].lw
	cmp	al,14		      ;CD/DVD "DOS function" request?
	ja s	TryDOS		      ;Yes, do DOS function dispatch.
	je s	CDReq2		      ;"Device Close", ignore & exit.
	mov	di,offset (DspTbl3-@) ;Get IOCTL input table ptr.
@DspTB3	equ	[$-2].lw
	cmp	al,3		      ;CD/DVD "IOCTL Input" request?
	je s	TryIOC		      ;Yes, go get actual IOCTL code.
	mov	di,offset (DspTbl4-@) ;Get IOCTL output table ptr.
@DspTB4	equ	[$-2].lw
	cmp	al,12		      ;CD/DVD "IOCTL Output" request?
	jb s	CDReqE		      ;No?  Handle as "unsupported".
	ja s	CDReq2		      ;"Device Open", ignore & exit.
TryIOC:	les	si,es:[si+IOCAdr] ;Get actual IOCTL request code.
	mov	al,es:[si]
	les	si,[bx+RqPkt-@]	  ;Reload DOS request-packet ptr.
	jmp s	Dispat		  ;Go do IOCTL request dispatch.
TryDOS:	sub	al,080h		  ;Not DOS code 0-14:  subtract 128.
Dispat:	cmp	al,cs:[di]	  ;Is request code out-of-bounds?
	inc	di		  ;(Skip past table-limit value).
	jae s	CDReqE		  ;Yes?  Handle as "unsupported".
	xor	ah,ah		  ;Point to request-handler addr.
	shl	ax,1
	add	di,ax
	mov	dx,cs:[di]	  ;Get handler address from table.
	mov	di,00FFFh
	and	di,dx
	xor	dx,di		  ;IOCTL request (xfr length > 0)?
	jz s	DspGo		  ;No, dispatch to desired handler.
	shr	dx,12		  ;Ensure correct IOCTL transfer
	mov	es:[si+IOCLen],dx ;  length is set in DOS packet.
	les	si,es:[si+IOCAdr] ;Get IOCTL data-transfer address.
	nop			  ;(Unused alignment "filler").
DspGo:	add	di,(USR-@)	;Dispatch to desired handler.
@DspOfs	equ	[$-2].lw	;(HMA dispatch offset, Init set).
	call	di
CDReq2:	shr	[bx+RXF-@].lb,1	;Should we reset UHDD "busy" flag?
	jnc s	CDReq3		;No, see if VDS "unlock" is needed.
	mov	es,[bx+UHSeg-@]	    ;Point to "base" UHDD segment.
	and	es:[bx].UHFlag,0FEh ;Reset UHDD's "busy" flag.
	nop			    ;(Unused alignment "filler").
CDReq3:	shr	[bx+VLF-@].lb,1	;Was user's buffer "locked" by VDS?
	jnc s	CDReqX		;No, return to CD/DVD exit routine.
	mov	ax,08104h	;Get VDS "unlock" parameters.
	xor	dx,dx
	mov	di,(VDSLn-@)	;Point to VDS parameter block.
	push	ds
	pop	es
	int	04Bh		;Issue VDS "unlock" request.
CDReqX:	db	0EAh		;Return to CD/DVD exit routine.
@CDExit	dd	(DvIntX-@)	;(CD/DVD exit address, Init set).
CDReqE:	call	USR		;Error!  Handle as "unsupported".
	jmp s	CDReq2		;Go reset UHDD "busy" and exit.
	db	0		;(Unused alignment "filler").
;
; Command-List XMS Block, for moving our DMA command-list to XMS.
;
CLXBlk	dd	8		;Move length      (always 8 bytes).
	dw	0		;Source handle       (always zero).
CLXSA	dd	(IOAdr-@)	;Source address (seg. set by Init).
CLXDH	dw	0		;Destination handle  (set by Init).
CLXDA	dd	0		;Destination offset  (set by Init).
;
; User-Data XMS Block, for moving XMS data to a user input buffer.
;
XMSBlk	dd	0		;Move length  (user buffer length).
XMSSH	dw	0		;Source handle (ours, set by Init).
XMSSA	dd	0		;Source offset (ours, set by Init).
	dw	0		;Destination handle  (always zero).
	dd	0		;Destination address (user buffer).
;
; CD/DVD Drive Parameter Tables.
;
UTable	dw	0FFFFh		;Unit 0 DMA address (set by Init).
	dw	0FFFFh		;	IDE address (set by Init).
	db	0FFh		;	Device-select (set by Init).
	db	0FFh		;	Media-change flag.
	dd	0FFFFFFFFh	;	Current audio-start address.
	dd	0FFFFFFFFh	;	Current audio-end   address.
	dd	0FFFFFFFFh	;	Last-session starting LBA.
	db	54 dup (0FFh)	;Unit 1 to 3 Drive Parameter Tables.
UTblEnd	equ	$		;End of all CD/DVD Parameter Tables.
;
; Subroutine to clear our ATAPI "packet" for the next CD/DVD request.
;   This subroutine is located here for "best fit".
;
ClrPkt:	mov	bl,12		 ;Set ATAPI packet size (loop count).
ClrPk1:	dec	bx		 ;Clear next ATAPI packet byte.
	mov	[bx+Packet-@],bh
	jnz s	ClrPk1		 ;If more bytes to clear, loop back.
	ret			 ;Exit.
;
; CD/DVD Dispatch Table for DOS request codes 128 thru 136.   Each
;   entry in the following tables has 4 bits of "IOCTL byte count"
;   and 12 bits of offset from symbol "USR" for its handler logic.
;   Any handler MUST be located no more than 4K bytes above "USR"!
;
DspTbl2	db	DspLmt2		;Number of valid request codes.
DspTblB	dw	RqRead-USR	;128 -- Read Long.
	dw	0		;129 -- Reserved	  (unused).
	dw	RqSeek-USR	;130 -- Read Long Prefetch.
	dw	RqSeek-USR	;131 -- Seek.
	dw	RqPlay-USR	;132 -- Play Audio.
	dw	RqStop-USR	;133 -- Stop Audio.
	dw	0		;134 -- Write Long	  (unused).
	dw	0		;135 -- Write Long Verify (unused).
	dw	RqRsum-USR	;136 -- Resume Audio.
DspLmt2	equ	($-DspTblB)/2	;Table request-code limit.
;
; CD/DVD Dispatch table for IOCTL Input requests.
;
DspTbl3	db	DspLmt3		    ;Number of valid request codes.
DspTblC	dw	ReqDHA+(5*IXM)-USR  ;00 -- Device-header address.
	dw	RqHLoc+(6*IXM)-USR  ;01 -- Current head location.
	dw	0		    ;02 -- Reserved	    (unused).
	dw	0		    ;03 -- Error Statistics (unused).
	dw	ReqACI+(9*IXM)-USR  ;04 -- Audio chan. info (PTDoom).
	dw	0		    ;05 -- Read drive bytes (unused).
	dw	ReqDS +(5*IXM)-USR  ;06 -- Device status.
	dw	ReqSS +(4*IXM)-USR  ;07 -- Sector size.
	dw	ReqVS +(5*IXM)-USR  ;08 -- Volume size.
	dw	ReqMCS+(2*IXM)-USR  ;09 -- Media-change status.
	dw	ReqADI+(7*IXM)-USR  ;10 -- Audio disk info.
	dw	ReqATI+(7*IXM)-USR  ;11 -- Audio track info.
	dw	ReqAQI+(11*IXM)-USR ;12 -- Audio Q-channel info.
	dw	0		    ;13 -- Subchannel info  (unused).
	dw	0		    ;14 -- Read UPC code    (unused).
	dw	ReqASI+(11*IXM)-USR ;15 -- Audio status info.
DspLmt3	equ	($-DspTblC)/2	    ;Table request-code limit.
;
; CD/DVD Dispatch table for IOCTL Output requests.
;
DspTbl4	db	DspLmt4		    ;Number of valid request codes.
DspTblD	dw	ReqEJ +(1*IXM)-USR  ;00 -- Eject Disk.
	dw	ReqLU +(2*IXM)-USR  ;01 -- Lock/Unlock Door.
	dw	ReqRS +(1*IXM)-USR  ;02 -- Reset drive.
	dw	ReqAC +(9*IXM)-USR  ;03 -- Audio control  (PTDoom).
	dw	0		    ;04 -- Write ctl. bytes (unused).
	dw	ReqCl +(1*IXM)-USR  ;05 -- Close tray.
DspLmt4	equ	($-DspTblD)/2	    ;Table request-code limit.
;
; Subroutine to convert LBA sector numbers into "RedBook" minutes,
;   seconds and "frames" format (MSF).   This subroutine is placed
;   here for "best fit".
;
CvtMSF:	add	eax,150		;Add in offset.
	push	eax		;Get address in DX:AX-regs.
	pop	ax
	pop	dx
	mov	cx,75		;Divide by 75 "frames"/second.
	div	cx
	shl	eax,16		;Set "frames" remainder in upper EAX.
	mov	al,dl
	ror	eax,16
	mov	cl,60		;Divide quotient by 60 seconds/min.
	div	cl
	ret			;Exit -- EAX-reg. contains MSF value.
;
; Subroutine to validate starting RedBook disk sector numbers.   This
;   subroutine is located here for "best fit".
;
ValSN:	mov	eax,es:[si].RLSec ;Get starting sector number.
	nop			  ;(Unused alignment "filler").
ValSN1:	movzx	edx,es:[si].RLAM  ;Get desired addressing mode.
	shr	dl,1		  ;HSG or RedBook addressing?
	jnz s	ValSNE		  ;No?  Return "sector not found".
	jnc s	RqExit		;HSG -- exit (accept any DVD value).
	mov	cx,ax		;Save "seconds" & "frames" in CX-reg.
	shr	eax,16		;Get "minute" value.
	cmp	ax,99		;Is "minute" value too large?
	ja s	ValSNE		;Yes, return "sector not found".
	cmp	ch,60		;Is "second" value too large?
	ja s	ValSNE		;Yes, return "sector not found".
	cmp	cl,75		;Is "frame" value too large?
	ja s	ValSNE		;Yes, return "sector not found".
	mov	dl,60		;Convert "minute" value to "seconds".
	mul	dl		;(Multiply by 60, obviously!).
	mov	dl,ch		;Add in "second" value.
	add	ax,dx
	mov	dl,75		;Convert "second" value to "frames".
	mul	edx		;(Multiply by 75 "frames"/second).
	mov	dl,150		;Subtract offset - "frame".
	sub	dl,cl		;("Adds" frame, "subtracts" offset).
	sub	eax,edx
	cmp	eax,RMAXLBA	;Is starting sector too big?
	jbe s	RqExit		;No, all is well -- go exit above.
ValSNE:	pop	ax		;Error!  Discard our exit address.
SectNF:	mov	al,8		;Sector not found!  Get error code.
	jmp s	ReqErr		;Go post "sector not found" and exit.
;
; CD/DVD Error Routines.
;
USR:	mov	al,3		  ;Unsupported request!  Get code.
ReqErr:	mov	ah,081h		  ;Get packet error flags.
RqStat:	les	si,[bx+RqPkt-@]	  ;Reload DOS request-packet addr.
	mov	es:[si+RPStat],ax ;Set error code & flags in packet.
RqExit:	ret			  ;Exit ("ignored" request handler).
;
; "Read Long" request handler.   All CD/DVD file data is read here.
;
RqRead:	call	ValSN		;Validate starting sector number.
	call	MultiS		;Handle Multi-Session disk if needed.
	jc s	ReqErr		;If error, post return code & exit.
	mov	cx,es:[si+RLSC]	;Get request sector count.
	jcxz	RqExit		;If zero, simply exit.
	xchg	cl,ch		;Save swapped sector count.
	mov	[bx+PktLn-@],cx
	cmp	es:[si.RLDM],1	;"Cooked" or "raw" read mode?
	ja s	SectNF		;Neither?  Return "sector not found"!
	mov	dl,028h		;Get "cooked" input values.
	mov	ax,COOKSL
	jb s	RqRL1		;If "cooked" input, set values.
	mov	dl,0BEh		;Get "raw" input values.
	mov	ax,RAWSL
	mov	[bx+PktRM-@].lb,0F8h ;Set "raw" input flags.
RqRL1:	mov	[bx+Packet-@].lb,dl  ;Set "packet" opcode.
	mul	es:[si+RLSC]	     ;Get desired input byte count.
	test	dx,dx		     ;More than 65535 bytes desired?
	jnz s	SectNF		     ;Yes?  Return sector not found!
	mov	[bx+VDSLn-@],ax	     ;Set VDS & I-O buffer lengths.
	mov	[bx+IOLen-@],ax
	les	ax,es:[si+RLAddr]    ;Set user input-buffer address.
	mov	[bx+VDSOf-@],ax
	mov	[bx+VDSSg-@],es
	mov	[bx+UserB+2-@],es
RqRL2:	or	[bx+IOAdr-@].dwd,-1 ;Invalidate VDS buffer address.
	mov	ax,08103h	    ;Get VDS "lock" parameters.
	mov	dx,0000Ch
	mov	di,(VDSLn-@)	    ;Point to VDS parameter block.
	push	ds
	pop	es
	int	04Bh		    ;Issue VDS "lock" request.
	call	XMSRst		    ;Restore all critical settings.
	les	si,[bx+RqPkt-@]	    ;Reload request packet address.
	jc s	RqRL6		    ;"Lock" error?  Use "PIO mode"!
	cmp	[bx+IOAdr-@].dwd,-1 ;Is VDS address still all-ones?
	jb s	RqRL3		    ;No, go set VDS "lock" flag.
	movzx	eax,[bx+VDSSg-@].lw ;VDS logic is NOT present --
	shl	eax,4		    ;  set 20-bit buffer address.
	add	eax,[bx+VDSOf-@]
	mov	[bx+IOAdr-@],eax
RqRL3:	adc	[bx+VLF-@],bl	    ;Set VDS "lock" flag from carry.
	cmp	[bx+PktRM-@],bl	;Is this a "raw mode" read?
RqRL4:	jmp s	RqRL7		;Yes, use "non-cached" logic.
				;("jne s RqRL7" if using caching).
	call	Cache		;Do cached CD/DVD input through UHDD.
	jc s	RqRLE		;Error?  Set code in packet and exit!
RqRL5:	ret			;All is well -- exit.
RqRL6:	call	Flush		;Flush cache on VDS "lock" errors!
RqRL7:	push	cs		;Non-cached:  Input all desired data.
	call	RLRead
	jnc s	RqRL5		;If no errors, go exit above.
RqRLE:	jmp	ReqErr		;Set error code in packet, then exit.
;
; CD/DVD "Seek" request handler.
;
RqSeek:	call	RdAST1		;Read current "audio" status.
	call	ClrPkt		;Reset our ATAPI packet area.
	jc s	RqSK2		;If status error, do DOS seek.
	mov	al,[di+1]	;Get "audio" status flag.
	cmp	al,011h		;Is drive in "play audio" mode?
	je s	RqSK1		;Yes, validate seek address.
	cmp	al,012h		;Is drive in "pause" mode?
	jne s	RqSK2		;No, do DOS seek below.
RqSK1:	call	ValSN		;Validate desired seek address.
	mov	di,[bx+AudAP-@]	;Point to audio-start address.
	cmp	eax,cs:[di+4]	;Is address past "play" area?
	ja s	RqSK2		;Yes, do DOS seek below.
	mov	cs:[di],eax	;Update audio-start address.
	call	PlayA		;Issue "Play Audio" command.
	jc s	RqPLE		;If error, post return code & exit.
	cmp	[di+1].lb,011h	;Were we playing audio before?
	je s	RqPLX		;Yes, post "busy" status and exit.
	call	ClrPkt		;Reset our ATAPI packet area.
	jmp s	APause		;Go put drive back in "pause" mode.
RqSK2:	call	ValSN		;Validate desired seek address.
	call	MultiS		;Handle Multi-Session disk if needed.
	jc s	RqPLE		;If error, post return code & exit.
	mov	[bx+Packet-@].lb,02Bh  ;Set "seek" command code.
RqSK3:	call	DoCmd		;Issue desired command to drive.
	jc s	RqPLE		;If error, post return code & exit.
RqSKX:	ret			;Exit.
;
; CD/DVD "Play Audio" request handler.
;
RqPlay:	cmp	es:[si.RLSC].dwd,0  ;Is sector count zero?
	je s	RqSKX		    ;Yes, just exit above.
	mov	eax,es:[si+RLAddr]  ;Validate audio-start address.
	call	ValSN1
	mov	di,[bx+AudAP-@]	;Save drive's audio-start address.
	mov	cs:[di],eax
	add	eax,es:[si+18]	;Calculate audio-end address.
	mov	edx,RMAXLBA	;Get maximum audio address.
	jc s	RqPL1		;If "end" WAY too big, use max.
	cmp	eax,edx		;Is "end" address past maximum?
	jbe s	RqPL2		;No, use "end" address as-is.
RqPL1:	xchg	eax,edx		;Set "end" address to maximum.
RqPL2:	mov	cs:[di+4],eax	;Save drive's audio-end address.
	call	PlayA		;Issue "Play Audio" command.
RqPLE:	jc s	RqDS0		;If error, post return code & exit.
RqPLX:	jmp	RdAST4		;Go post "busy" status and exit.
;
; CD/DVD "Stop Audio" request handler.
;
RqStop:	call	RdAST1		;Read current "audio" status.
	call	ClrPkt		;Reset our ATAPI packet area.
	jc s	APause		;If status error, just pause.
	mov	al,[di+1]	;Get "audio" status flag.
	cmp	al,011h		;Is drive in "play audio" mode?
	je s	APause		;Yes, pause it.
	mov	[bx+Packet-@].lb,04Eh ;Set "Stop" command.
	jmp s	DoStop		      ;Go stop "audio" and exit.
APause:	mov	[bx+Packet-@].lb,04Bh ;Set "Pause/Resume" command.
DoStop:	jmp	DoCmd		      ;Go pause "audio" and exit.
;
; CD/DVD "Resume Audio" request handler.
;
RqRsum:	inc	[bx+PktLn+1-@].lb  ;Set "Resume" flag for above.
	call	APause		;Issue "Pause/Resume" command.
	jmp s	RqPLE		;Go exit through "RqPlay" above.
;
; CD/DVD IOCTL Input "Device Header Address" handler.
;
ReqDHA:	push	ds		;Return our base driver address.
	push	bx
	pop	es:[si+1].dwd
	ret			;Exit.
;
; CD/DVD IOCTL Input "Current Head Location" handler.
;
RqHLoc:	mov	[bx+Packet-@].dwd,001400042h   ;Set command bytes.
	mov	al,16		;Set input byte count of 16.
	call	RdAST3		;Issue "Read Subchannel" request.
	jc s	RqDS0		;If error, post return code & exit.
	mov	es:[si+1],bl	;Return "HSG" addressing mode.
	call	SwpLBA		;Return "swapped" head location.
	mov	es:[si+2],eax
	jmp s	RqVSX		;Go post "busy" status and exit.
;
; CD/DVD IOCTL Input "Device Status" handler.
;
ReqDS:	mov	[bx+Packet-@].dwd,0002A005Ah  ;Set up mode-sense.
	mov	al,16		;Use input byte count of 16.
	call	DoBuf1		;Issue mode-sense for hardware data.
RqDS0:	jc s	RqVSE		;If error, post return code & exit.
	mov	eax,00214h	;Get our basic driver status flags.
	mov	cl,070h		;Get media status byte.
	xor	cl,[di+2]
	shr	cl,1		;Door open, or closed with no disk?
	jnz s	RqDS1		;No, check "drive locked" status.
	adc	ax,00800h	;Post "door open" & "no disk" flags.
RqDS1:	test	[di+14].lb,002h	;Drive pushbutton "locked out"?
	jnz s	RqVSS		;No, set flags in IOCTL and exit.
	or	al,002h		;Set "door locked" status flag.
	jmp s	RqVSS		;Go set flags in IOCTL and exit.
;
; CD/DVD IOCTL Input "Sector Size" handler.
;
ReqSS:	cmp	es:[si+1].lb,1	;Is read mode "cooked" or "raw"?
	ja	RqGenE		;Neither -- Post "general error".
	mov	ax,RAWSL	;Get "raw" sector length.
	je s	RqSS1		;If "raw" mode, set sector length.
	mov	ax,COOKSL	;Get "cooked" sector length.
RqSS1:	mov	es:[si+2],ax	;Post sector length in IOCTL packet.
	ret			;Exit.
;
; CD/DVD IOCTL Input "Audio Channel Info" handler (PTDoom).   Returns the
; MSCDEX default, input channels 0-3 each at full volume.   Programs using
; the Miles Sound System's CD audio (e.g. Dungeon Keeper) ask for this and
; treat the drive as having no audio CD without it.
;
ReqACI:	mov	dword ptr es:[si+1],0FF01FF00h ;Channels 0 and 1, full volume.
	mov	dword ptr es:[si+5],0FF03FF02h ;Channels 2 and 3, full volume.
	ret			;Exit.
;
; CD/DVD IOCTL Output "Audio Control" handler (PTDoom).   Accepts the
; channel and volume settings and ignores them, as drives may.
;
ReqAC:	ret			;Exit.
;
; CD/DVD IOCTL Input "Volume Size" handler.
;
ReqVS:	mov	[bx+Packet-@].lb,025h  ;Set "Read Capacity" code.
	mov	al,008h		;Get 8 byte data-transfer length.
	call	DoBuf2		;Issue "Read Capacity" command.
RqVSE:	jc s	RqAQIE		;If error, post return code & exit.
	mov	eax,[di]	;Get and "swap" volume size.
	call	Swp32
RqVSS:	mov	es:[si+1],eax	;Set desired IOCTL data value.
RqVSX:	jmp s	RqATIX		;Go post "busy" status and exit.
;
; CD/DVD IOCTL Input "Media-Change Status" handler.
;
ReqMCS:	call	DoCmd		;Issue "Test Unit Ready" command.
	mov	di,[bx+AudAP-@]	;Get media-change flag from table.
	mov	al,cs:[di-1]
	mov	es:[si+1],al	;Return media-change flag to user.
	ret			;Exit.
;
; CD/DVD IOCTL Input "Audio Disk Info" handler.
;
ReqADI:	mov	al,0AAh		;Specify "lead-out" session number.
	call	RdTOC		;Read disk table-of-contents (TOC).
	mov	es:[si+3],eax	;Set "lead out" LBA addr. in IOCTL.
	mov	ax,[di+2]	;Set first & last tracks in IOCTL.
	mov	es:[si+1],ax
	jmp s	RqATIX		;Go post "busy" status and exit.
;
; CD/DVD IOCTL Input "Audio Track Info" handler.
;
ReqATI:	mov	al,es:[si+1]	;Specify desired session (track) no.
	call	RdTOC		;Read disk table-of-contents (TOC).
	mov	es:[si+2],eax	;Set track LBA address in IOCTL.
	mov	al,[di+5]
	shl	al,4
	mov	es:[si+6],al
RqATIX:	jmp	RdAST		;Go post "busy" status and exit.
;
; CD/DVD IOCTL Input "Audio Q-Channel Info" handler.
;
ReqAQI:	mov	ax,04010h	;Set "data in", use 16-byte count.
	call	RdAST2		;Read current "audio" status.
RqAQIE:	jc s	RqASIE		;If error, post return code & exit.
	mov	eax,[di+5]	;Get ctrl/track/index in EAX-reg.
	rol	al,4		;Swap & save control byte, then do
	mov	cl,al		;  track binary-to-BCD conversion.
	mov	al,ah		;  Many Thanks to Japheth, also to
	aam			;  Nagatoshi Uehara of Japan, for
	shl	ah,4		;  finding the "swap" and "binary-
	add	ah,al		;  to-BCD" conversions are needed!
        mov     al,cl		;Restore control byte into AL-reg.
	mov	es:[si+1],eax	;Set ctrl/track/index in IOCTL.
	mov	eax,[di+13]	;Set time-on-track in IOCTL.
	mov	es:[si+4],eax
	mov	eax,[di+9]	;Get time-on-disk & clear high
	shl	eax,8		;  order time-on-track in IOCTL.
	jmp s	RqASI4		;Go set value in IOCTL and exit.
;
; CD/DVD IOCTL Input "Audio Status Info" handler.
;
ReqASI:	mov	ax,04010h	;Set "data in", use 16-byte count.
	call	RdAST2		;Read current "audio" status.
RqASIE:	jc s	RqErrJ		;If error, post return code & exit.
	mov	es:[si+1],bx	;Reset IOCTL "audio paused" flag.
	cmp	[di+1].lb,011h  ;Is drive now "playing" audio?
	jne s	RqASI1		;No, check for audio "pause".
	mov	di,[bx+AudAP-@]	;Point to this drive's audio data.
	mov	eax,cs:[di]	;Get current audio "start" addr.
	call	RqASI5		;Convert to "big-endian" MSF.
	jmp s	RqASI3		;Go set IOCTL "audio start" addr.
RqASI1:	cmp	[di+1].lb,012h	;Is drive now in audio "pause"?
	je s	RqASI2		;Yes, go set "audio paused" flag.
	xor	eax,eax		;Zero IOCTL "audio start" address.
	mov	es:[si+3],eax
	jmp s	RqASI4		;Go zero "audio end" addr. & exit.
RqASI2:	inc	es:[si+1].lb	;Set IOCTL "audio paused" flag.
	call	SwpLBA		;Get & swap current time-on-disk.
	mov	di,[bx+AudAP-@]	;Point to this drive's audio data.
RqASI3:	mov	es:[si+3],eax	;Set IOCTL "audio start" address.
	mov	eax,cs:[di+4]	;Get current audio "end" address.
	call	RqASI5		;Convert to "big-endian" MSF.
RqASI4:	mov	es:[si+7],eax	;Set IOCTL "audio end" address.
	ret			;Exit.
RqASI5:	call	CvtMSF		;Local "ReqASI" subroutine which
	shl	eax,8		;  converts audio start/end LBAs
	jmp s	Swp32		;  to "big-endian" MSF format.
;
; CD/DVD IOCTL Output "Eject Disk" handler.
;
ReqEJ:	mov	[bx+Packet-@].lw,0011Bh  ;Set "eject" commands.
	mov	[bx+PktLBA+2-@].lb,002h  ;Set "eject" function.
	jmp	RqSK3			 ;Go do "eject" & exit.
;
; CD/DVD IOCTL Output "Lock/Unlock Door" handler.
;
ReqLU:	mov	al,es:[si+1]	;Get "lock" or "unlock" function.
	cmp	al,001h		;Is function byte too big?
	ja s	RqGenE		;Yes, post "general error" & exit.
	mov	cx,0001Eh	    ;Get "lock" & "unlock" commands.
RqLU1:	mov	[bx+Packet-@],cx    ;Set "packet" command bytes.
	mov	[bx+PktLBA+2-@],al  ;Set "packet" function byte.
	call	DoCmd		    ;Issue desired command to drive.
	jc s	RqErrJ		;If error, post return code & exit.
	jmp s	RdAST		;Go post "busy" status and exit.
;
; CD/DVD IOCTL Output "Reset Drive" handler.
;
ReqRS:	call	HltDMA		;Stop previous DMA & select drive.
	inc	dx		;Point to IDE command register.
	mov	al,008h		;Do an ATAPI "soft reset" command.
	out	dx,al
	call	ChkTO		;Await controller-ready.
	jnc s	SwpLBX		;If no timeout, go exit below.
RqGenE:	mov	al,GENERR	;General error!  Get return code.
RqErrJ:	jmp	ReqErr		;Go post error return code and exit.
	db	0		;(Unused alignment "filler").
;
; CD/DVD IOCTL Output "Close Tray" handler.
;
ReqCL:	mov	al,003h		;Get "close tray" function byte.
	mov	cx,0011Bh	;Get "eject" & "close" commands.
	jmp s	RqLU1		;Go do "close tray" command above.
;
; CD/DVD subroutine to read disk "Table of Contents" (TOC) values.
;
RdTOCE:	pop	cx		;Error -- Discard exit address.
	jmp s	RqErrJ		;Go post return code and exit.
RdTOC:	mov	[bx+Packet-@].lw,00243h  ;Set TOC and MSF bytes.
	call	DoTOC1		;Issue "Read Table of Contents" cmd.
	jc s	RdTOCE		;If error, exit immediately.
;
; CD/DVD subroutine to "swap" the 4 bytes of a a 32-bit value.
;
SwpLBA:	mov	eax,[di+8]	;Get audio-end or buffer LBA value.
Swp32:	xchg	al,ah		;"Swap" original low-order bytes.
	rol	eax,16		;"Exchange" low- and high-order.
	xchg	al,ah		;"Swap" ending low-order bytes.
SwpLBX:	ret			;Exit.
;
; CD/DVD subroutine to read current "audio" status & disk addresses.
;
RdAST:	call	ClrPkt		  ;Status only -- reset ATAPI packet.
RdAST1:	mov	ax,00004h	  ;Clear "data in", use 4-byte count.
RdAST2:	mov	[bx+Packet-@].dwd,001000242h  ;Set command bytes.
	mov	[bx+PktLBA-@],ah  ;Set "data in" flag (RdAST2 only).
RdAST3:	call	DoBuf1		  ;Issue "Read Subchannel" command.
	jc s	RdASTX		  ;If error, exit immediately.
	cmp	[di+1].lb,011h	  ;Is a "play audio" in progress?
	clc			  ;(Zero carry flag in any case).
	jne s	RdASTX		  ;No, just exit below.
RdAST4:	push	si		  ;Save SI- and ES-regs.
	push	es
	les	si,[bx+RqPkt-@]	  ;Reload DOS request-packet addr.
	or	es:[si.RPStat],RPBUSY  ;Set "busy" status bit.
	pop	es		  ;Reload ES- and SI-regs.
	pop	si
RdASTX:	ret			  ;Exit.
;
; Subroutine to handle CD/DVD Multi-Session disks for reads & seeks.
;   Multi-Session disks require (A) saving the last-session starting
;   LBA for a new disk after any media-change and (B) "offsetting" a
;   read of the VTOC or initial directory block, sector 16 or 17, to
;   access the VTOC/directory of the disk's last session.
;
MultiS:	mov	di,[bx+AudAP-@]		;Point to drive variables.
	cmp	cs:[di+11].lb,0FFh	;Is last-session LBA valid?
	jne s	MultS1			;Yes, proceed with request.
	mov	[bx+Packet-@].lb,043h	;Set "Read TOC" command.
	inc	[bx+PktLBA-@].lb	;Set "format 1" request.
	call	DoTOC2			;Read first & last session.
	jc s	MultSX			;If any error, exit below.
	mov	[bx+PktLBA-@],bl	;Reset "format 1" request.
	mov	al,[di+3]		;Get last-session number.
	call	DoTOC1		;Read disk info for last session.
	jc s	MultSX		;If error, exit with carry set.
	call	SwpLBA		;"Swap" & save last-session LBA addr.
	mov	di,[bx+AudAP-@]
	mov	cs:[di+8],eax
	call	ClrPkt		   ;Reset our ATAPI packet area.
MultS1:	mov	eax,es:[si+RLSec]  ;Get starting sector number.
	mov	dx,ax		   ;Save low-order sector number.
	and	al,0FEh		;"Mask" sector to an even number.
	cmp	eax,16		;Sector 16 (VTOC) or 17 (directory)?
	xchg	ax,dx		;(Restore low-order sector number).
	jne s	MultS2		;No, set sector in packet.
	add	eax,cs:[di+8]	;Offset sector to last-session start.
MultS2:	call	Swp32		;"Swap" sector into packet as LBA.
	mov	[bx+PktLBA-@],eax
	clc			;Clear carry flag (no errors).
MultSX:	ret			;Exit.
;
; Subroutine to ensure CD/DVD UltraDMA is stopped and then select our
;   drive.   For some older chipsets, if UltraDMA is running, reading
;   an IDE register causes the chipset to "HANG"!!
;
HltDMA:	mov	dx,[bx+DMAAd-@]	;Get drive UltraDMA command address.
	test	dl,001h		;Is this drive using UltraDMA?
	jnz s	HltDM1		;No, just select "master" or "slave".
	in	al,dx		;Ensure any previous DMA is stopped!
	and	al,0FEh
	out	dx,al
HltDM1:	mov	bp,[bx+IdeDA-@]	;Get drive's IDE address in BP-reg.
	lea	dx,[bp+CDSEL]	;Point to IDE device-select register.
	mov	di,[bx+AudAP-@]	;Get drive's IDE device-select byte.
	mov	al,cs:[di-2]
	out	dx,al		;Select IDE "master" or "slave" unit.
	ret			;Exit.
;
; Subroutine to do actual CD/DVD input.   This subroutine can be
;   "called back" by the UHDD driver, to cache CD/DVD data files
;   and their directories.   At exit, carry is set for any error
;   and the AL-reg. has an appropriate error code.
;
RLRead:	call	XMSRst		     ;Make all our critical settings.
	test	[bx+DMAAd-@].lb,001h ;Is this drive using UltraDMA?
	jnz s	RLRd3		     ;No, go use "PIO mode" input.
	test	[bx+IOAdr-@].lb,003h ;Is user buffer 32-bit aligned?
	jnz s	RLRd1		     ;No, use our XMS memory buffer.
	cmp	[bx+IOAdr-@].hw,009h ;Is DMA beyond our 640K limit?
	ja s	RLRd1		     ;Yes, use our XMS memory buffer.
	mov	cx,[bx+IOLen-@]	     ;Get (length - 1) + I-O address.
	dec	cx
	add	cx,[bx+IOAdr-@].lw   ;Will I-O cross a 64K boundary?
	jnc s	RLRd2		     ;No, user-buffer DMA is O.K.
RLRd1:	stc			     ;Set carry to denote our buffer.
	mov	[bx+IOAdr-@].dwd,0   ;Set our 32-bit XMS buffer addr.
@XBAddr	equ	[$-4].dwd	     ;(XMS buffer address, Init set).
RLRd2:	adc	[bx+XMF-@].lw,00100h ;Set XMS-move & DMA-input flags.
	mov	si,(CLXBlk-@)	     ;Get command-list XMS block ptr.
CLXPtr	equ	[$-2].lw
	push	cs
	pop	ds
	call	XMSMov		 ;Move DMA command-list up to XMS.
	jc s	RLRdE		 ;Failed?  Return "general error"!
RLRd3:	call	DoIO		 ;Do desired CD/DVD input request.
	jc s	RLRdX		 ;If error, exit with carry flag on.
	or	[bx+XMF-@],bl	 ;Do we need an XMS buffer "move"?
	jz s	RLRdX		 ;No, just exit with carry flag off.
	mov	cx,[bx+VDSLn-@]	 ;Get user-buffer length & address.
	mov	eax,[bx+UserB-@]
	mov	si,(XMSBlk-@)	 ;Point to user-data XMS block.
XMSPtr	equ	[$-2].lw
	push	cs
	pop	ds
	mov	[si],cx		;Set user-buffer length & address.
	mov	[si+12],eax
	call	XMSMov		;Move data from XMS to user buffer.
RLRdE:	mov	al,GENERR	;Use "General Error" if XMS failed.
RLRdX:	retf			;Exit ("retf" for calls from UHDD).
;
; Subroutines to issue various CD/DVD audio functions.
;
DoTOC1:	mov	[bx+PktLH-@],al	   ;"TOC" -- set packet session no.
DoTOC2:	mov	al,12		   ;Use 12-byte "TOC" alloc. count.
DoBuf1:	mov	[bx+PktLn+1-@],al  ;Buffered -- set packet count.
DoBuf2:	mov	[bx+VDSLn-@],al	   ;Set 8-bit data-transfer length.
	mov	[bx+VDSOf-@].lw,(InBuf-@)  ;Use our buffer for I-O.
	mov	[bx+UserB+2-@],ds
	jmp s	DoCmd1		   ;Go zero hi-order and start I-O.
;
; Subroutine to issue a CD/DVD "Play Audio" command.   At entry, the
;   DI-reg. points to the audio-start address for this drive.
;
PlayA:	mov	eax,cs:[di]	      ;Set packet audio-start addr.
	call	CvtMSF
	mov	[bx+PktLBA+1-@],eax
	mov	eax,cs:[di+4]	      ;Set packet audio-end address.
	call	CvtMSF
	mov	[bx+PktLH-@],eax
	mov	[bx+Packet-@].lb,047h ;Set "Play Audio" command &
				      ;  fall-through to "DoCmd".
;
; Ye Olde CD/DVD I-O Subroutine.   All CD/DVD I-O gets executed here!
;
DoCmd:	mov	[bx+VDSLn-@],bl    ;Command only -- zero xfr length.
DoCmd1:	mov	[bx+VDSLn+1-@],bx  ;Zero hi-order VDS buffer length.
DoIO:	push	si		   ;Save SI- and ES-registers.
	push	es
	mov	[bx+Try-@].lb,4	;Set request retry count of 4.
DoIO1:	call	HltDMA		;Stop previous DMA & select drive.
	call	ChkTO		;Await controller-ready.
	jc	DoIO4		;Timeout!  Handle as a "hard error".
	cmp	[bx+DMF-@],bl	;UltraDMA input request?
	je s	DoIO2		;No, output ATAPI "packet" command.
	mov	ax,00008h	;Get DMA-input command bit.
	mov	dx,[bx+DMAAd-@]	;Get DMA command-register address.
	out	dx,al		;Reset DMA commands and set DMA mode.
	inc	dx		;Point to DMA status register.
	inc	dx
	in	al,dx		;Reset DMA status register.
	or	al,006h		;(Done this way so we do NOT alter
	out	dx,al		;  the "DMA capable" status flags!).
	inc	dx		;Point to PRD address register.
	inc	dx
	mov	eax,(IOAdr-@)	;Set Physical-Region Descriptor ptr.
PRDAd	equ	[$-4].dwd	;(32-bit PRD address, set by Init).
	out	dx,eax
DoIO2:	push	[bx+VDSOf-@].lw	;Reset data-transfer count & address.
	push	[bx+VDSLn-@].lw
	pop	[bx+UserL-@].dwd
	lea	dx,[bp+1]	 ;Point to IDE "features" register.
	mov	al,[bx+DMF-@]	 ;If UltraDMA input, set "DMA" flag.
	out	dx,al
	add	dx,3		;Point to byte count registers.
	mov	si,(UserL-@)	;Output data-transfer length.
	outsb
	inc	dx
	outsb
	inc	dx		;Point to command register.
	inc	dx
	mov	al,0A0h		;Issue "Packet" command.
	out	dx,al
	mov	cl,DRQ		;Await controller- and data-ready.
	call	ChkTO1
	jc s	DoIO4		;Timeout!  Handle as a "hard error".
	xchg	ax,si		;Save BIOS timer address.
	mov	dx,bp		;Point back to IDE data register.
	mov	cl,6		;Output all 12 "Packet" bytes.
	mov	si,(Packet-@)
	rep	outsw
	xchg	ax,si		;Reload BIOS timer address.
	mov	ah,STARTTO	;Allow 7 seconds for drive startup.
	cmp	[bx+DMF-@],bl	;UltraDMA input request?
	je	DoIO12		;No, start "PIO mode" transfer below.
	mov	[bx+UserL-@],bx	;Reset transfer length (DMA does it).
	mov	ch,ah		;Set 7-second timeout in AH-reg.
	add	ch,es:[si]
	mov	es:[si+HDI_OFS],bl  ;Reset BIOS disk-interrupt flag.
	mov	dx,[bx+DMAAd-@]	    ;Point to DMA command register.
	in	al,dx		;Set DMA Start/Stop bit (starts DMA).
	inc	ax
	out	dx,al
ChkDMA:	inc	dx		;Point to DMA status register.
	inc	dx
	in	ax,dx		;Read DMA controller status.
	dec	dx		;Point back to DMA command register.
	dec	dx
	and	al,DMI+DME	;DMA interrupt or DMA error?
	jnz s	EndDMA		;Yes, halt DMA and check results.
	cmp	ch,es:[si]	;Has our DMA transfer timed out?
	je s	EndDMA		    ;Yes?  Halt DMA & post timeout!
	cmp	es:[si+HDI_OFS],bl  ;Did BIOS get a disk interrupt?
	je s	ChkDMA		    ;No, loop back & retest status.
	mov	al,DMI		;Set "simulated" interrupt flag.
EndDMA:	push	ax		;Save ending DMA status.
	in	al,dx		;Reset DMA Start/Stop bit.
	and	al,0FEh
	out	dx,al
	pop	ax		;Reload ending DMA status.
	cmp	al,DMI		;Did DMA end with only an interrupt?
	jne s	DoIO4		;No?  Handle as a "hard error"!
	inc	dx		;Reread DMA controller status.
	inc	dx
	in	al,dx
	test	al,DME		;Any "late" DMA error after DMA end?
	jnz s	DoIO4		;Yes?  Handle as a "hard error"!
	call	ChkTO		;Await final controller-ready.
	jc s	DoIO4		;Timeout!  Handle as a "hard error"!
DoIO3:	mov	si,[bx+AudAP-@]	;Get drive media-change flag pointer.
	dec	si
	and	ax,00001h	;Did controller detect any errors?
	jz s	DoIO6		;No, see if all data was transferred.
	sub	dx,6		;Get controller's sense key value.
	in	al,dx
	shr	al,4
	cmp	al,006h		;Is sense key "Unit Attention"?
	je s	DoIO7		;Yes, check for prior media-change.
	mov	ah,0FFh		;Get 0FFh flag for "Not Ready".
	cmp	al,002h		;Is sense key "Drive Not Ready"?
	je s	DoIO8		;Yes, go set our media-change flag.
DoIO4:	lea	dx,[bp+CCMD]	;Hard error!  Point to command reg.
	mov	al,008h		;Issue ATAPI "soft reset" to drive.
	out	dx,al
	mov	al,11		;Get "hard error" return code.
	dec	[bx+Try-@].lb	;Do we have more I-O retries left?
	jz s	DoIO9		;No, set carry & return error code.
	jmp	DoIO1		;Try re-executing this I-O request.
DoIO6:	cmp	[bx+UserL-@],bx	;Was all desired data input?
	jne s	DoIO4		;No?  Handle as a "hard error".
	mov	cs:[si].lb,001h	;Set "no media change" flag.
	jmp s	DoIO10		;Go reload regs. and exit below.
	db	0		;(Unused alignment "filler").
DoIO7:	mov	al,002h		;"Attention":  Get "Not Ready" code.
DoIO8:	call	Flush		;"Flush" our cache for a new CD/DVD.
	xchg	ah,cs:[si]	   ;Load and set media-change flag.
	mov	cs:[si+12].lb,0FFh ;Make last-session LBA invalid.
	dec	ah		   ;Media-change flag already set?
	jnz s	DoIO9		;Yes, set carry flag and exit.
	mov	al,15		;Return "Invalid Media Change".
DoIO9:	stc			;Set carry flag (error!).
DoIO10:	pop	es		;Reload ES- and SI-registers.
	pop	si
	mov	di,(InBuf-@)	;For audio, point to our buffer.
	ret			;Exit.
DoIO11:	mov	ah,SEEKTO	;"PIO mode" -- Get "seek" timeout.
DoIO12:	call	ChkTO2		;Await controller-ready.
	jc s	DoIO4		;Timeout!  Handle as a "hard error".
	test	al,DRQ		;Did we also get a data-request?
	jz s	DoIO3		;No, go check for any input errors.
	dec	dx		;Get controller-buffer byte count.
	dec	dx
	in	al,dx
	mov	ah,al
	dec	dx
	in	al,dx
	mov	dx,bp		;Point to IDE data register.
	mov	si,[bx+UserL-@]	;Get our data-transfer length.
	or	si,si		;Any remaining bytes to input?
	jz s	DoIO14		;No, "eat" all residual data.
	cmp	si,ax		;Remaining bytes > buffer count?
	jbe s	DoIO13		;No, input all remaining bytes.
	mov	si,ax		;Use buffer count as input count.
DoIO13:	les	di,[bx+UserB-@]	;Get input data-transfer address.
	mov	cx,si		;Input all 16-bit data words.
	shr	cx,1
	rep	insw
	add	[bx+UserB-@],si	;Increment data-transfer address.
	sub	[bx+UserL-@],si	;Decrement data-transfer length.
	sub	ax,si		;Any data left in controller buffer?
	jz s	DoIO11		;No, await next controller-ready.
DoIO14:	xchg	ax,cx		;"Eat" all residual input data.
	shr	cx,1		;(Should be NO residual data as we
DoIO15:	in	ax,dx		;  always set an exact byte count.
	loop	DoIO15		;  This logic is only to be SAFE!).
	jmp s	DoIO11		;Go await next controller-ready.
;
; Subroutine to issue "move memory" requests to the XMS manager.
;
XMSMov:	mov	ah,00Bh		;Issue XMS "move memory" request.
	db	09Ah
@XMgr3	dd	0		;(XMS "entry" address, set by Init).
	sub	ax,1		;Zero AX-reg. if success, -1 if error.
XMSRst:	sti			;RESTORE all critical driver settings!
	cld			;(Never-NEVER "trust" external code!).
	push	08000h		;Reload this driver's DS-register.
@DSReg	equ	[$-2].lw	;(Driver DS-reg. value, set by Init).
	pop	ds
	mov	bx,0		;Rezero BX-reg. but save carry flag.
	ret			;Exit.
;
; Subroutine to test for CD/DVD I-O timeouts.   At entry the CL-reg.
;   is 008h to test for a data-request, also.   At exit, the DX-reg.
;   points to the drive's IDE primary-status reg.   The AH-, SI- and
;   ES-regs. will be lost.
;
ChkTO:	xor	cx,cx		;Check for only controller-ready.
ChkTO1:	mov	ah,CMDTO	;Use 500-msec command timeout.
ChkTO2:	mov	es,bx		;Point to low-memory BIOS timer.
	mov	si,BIOSTMR
	add	ah,es:[si]	;Set timeout limit in AH-reg.
ChkTO3:	cmp	ah,es:[si]	;Has our I-O timed out?
	stc			;(If so, set carry flag).
	je s	ChkTOX		;Yes?  Exit with carry flag on.
	lea	dx,[bp+CSTAT]	;Point to IDE status reg.
	in	al,dx		;Read IDE primary status.
	test	al,BSY		;Is our controller still busy?
	jnz s	ChkTO3		;Yes, loop back and test again.
	jcxz	ChkTOX		;If not awaiting I-O data, exit now.
	test	al,cl		;Is data-request (DRQ) also set?
	jz s	ChkTO3		;No, loop back and test again.
ChkTOX:	ret			;Exit:  Carry "on" denotes a timeout!
;
; Subroutine to flush our cache on media-changes or a VDS lock error.
;
Flush:	ret			 ;If not doing caching, just exit!
	db	047h,(UHSeg-@)	 ;("mov es,[bx+UHSeg-@]" if caching).
	or	es:[bx].UHFlag,2 ;Request a UHDD cache "flush".
	ret			 ;Exit.
HMALEN	equ	($-CDReq)	 ;(Length of all "normal" HMA logic).
;
; Subroutine to set up and issue CD/DVD data-caching requests.
;   Calling UHDD for input will reset its "busy" flag, thus we
;   must NOT reset that flag again, when this request is done!
;
Cache:	mov	[bx+RXF-@],bl	 ;Do NOT reset UHDD "busy" on exit!
	mov	cx,es:[si+RLSC]      ;Get sector count & read code.
	shl	cl,2		     ;Multiply by 4 for 2K sectors.
	movzx	bp,es:[si+RPSubU].lb ;Get our CD/DVD drive number.
	add	bp,CDUNIT	     ;Convert to our "cache unit".
	mov	eax,[bx+PktLBA-@]    ;Convert packet LBA to "little
	call	Swp32		     ;  endian" format for caching.
	rol	eax,2		 ;"Multiply" by 4 for 2K sectors.
	mov	di,00003h	 ;Put upper 2 bits in DI-reg. and
	and     di,ax		 ;  put low 30 bits in DX/SI-regs.
	xor	ax,di		 ;(Disks use 48-bit LBAs and 512-
	push	eax		 ;  byte sectors.  CDs use 32-bit
	pop	si		 ;  LBAs, with 2048-byte sectors.
	pop	dx		 ;  So, a conversion is NEEDED!).
	mov	eax,[bx+IOAdr-@] ;Get 32-bit input buffer addr.
	mov	es,[bx+UHSeg-@]  ;Point to UHDD "base page" data.
	push	cs		 ;Set our "callback" address and
	push	(RLRead-@)	 ;  "device type" code for UHDD.
@CBAddr	equ	[$-2].lw
	pop	es:[bx].UHCalB
	mov	es:[bx].UHType,CDTYP
	pushf			;Save CPU flags and call "GoUHDD"
	push	cs		;  for input -- with flags saved,
	call	GoUHDD		;  the call acts like an Int 13h!
	mov	al,ah		;Put "BIOS" AH-reg. code into AL-reg.
	jmp s	XMSRst		;Restore critical settings, and exit.
	db	0,0		;(Unsued alignment "filler").
;
; Subroutine to enter the UHDD driver for cached CD/DVD input.
;
GoUHDD:	pushf			;Save CPU flags and BP-reg. same as
	push	bp		;  an "Int 13h" I-O request will do.
	db	0EAh		;Go switch to UHDD stack & do input.
	dw	UHEntr
@UHSeg1	dw	0		;(UHDD segment address, set by Init).
	db	0		;(Unused alignment "filler").
CACHLEN	equ	($-Cache)	;(Added length of caching routines).
;
; Initialization Variables.
;
PCIDevX	dw	0		;Current PCI "device index".
PCISubC	dw	00100h		;PCI subclass and function code.
CtlrAdP	dw	(Ctl1Tbl-@)	;Disk controller address-table ptr.
HMASize	dw	HMALEN		;Size of all HMA driver routines.
;
; Initialization UltraDMA "Mode" Table (digit count in low 4 bits).
;
Modes	dw	01602h		;Mode 0, ATA-16.
	dw	02502h		;Mode 1, ATA-25.
	dw	03302h		;Mode 2, ATA-33.
	dw	04402h		;Mode 3, ATA-44.
	dw	06602h		;Mode 4, ATA-66.
	dw	01003h		;Mode 5, ATA-100.
	dw	01333h		;Mode 6, ATA-133.
	dw	01663h		;Mode 7, ATA-166.
;
; Initialization Controller I-O Address Table.
;
Ctl1Tbl	dw	0FFFFh		;Controller 1 DMA base address.
Ctl1Pri	dw	NPDATA		;   "Legacy" primary   addresses.
Ctl1Sec	dw	NSDATA		;   "Legacy" secondary addresses.
Ctl2Tbl	dw	0FFFFh		;Controller 2 DMA base address.
Ctl2Pri	dw	APDATA		;   "Legacy" primary   addresses.
Ctl2Sec	dw	ASDATA		;   "Legacy" secondary addresses.
	dw	21 dup (0FFFFh)	;Controller 3 to 9 I-O addresses.
CtlTEnd	equ	$		   ;End of controller I-O tables.
CTLTSIZ	equ	(Ctl2Tbl-Ctl1Tbl)  ;Size of a controller's table.
;
; Initialization Messages.
;
TTLMsg	db	CR,LF,'UDVD2, 12-12-2022.  CD/DVD name is '
TTLName	db	'         ',CR,LF,0
NXMsg	db	'No XMS$'
IBMsg	db	'No V2.0C+ PCI!',CR,LF,'$'
DNMsg	db	', '
CDName	equ	$
BCMsg	db	'BAD$'
PCMsg	db	'IDE0'
PCMsg1	db	' Controller at I-O address '
PCMsg2	db	'PCI h, Chip I.D. '
PCMsg3	db	'-SA$    h.',CR,LF,'$'
CDMsg	db	'CD'
CDMsgNo	db	'0:  '
CtlMsg	db	'IDE'
CtlrNo	db	'0 $'
PriMsg	db	'Primary-$'
SecMsg	db	'Secondary-$'
MstMsg	db	'master$'
SlvMsg	db	'slave$'
NDMsg	db	'Nothing to use$'
VEMsg	db	'VDS init error$'
PRMsg	db	'No 386+ CPU'
Suffix	db	'; UDVD2 not loaded!',CR,LF,'$'
;
; Initialization "Strategy" Routine.   This MUST be placed above all
;   run-time logic, to prevent CPU cache "code modification" ERRORS!
;
I_Stra:	mov	cs:RqPkt.lw,bx	;Save DOS request-packet address.
	mov	cs:RqPkt.hw,es
	retf			;Exit & await DOS "Device Interrupt".
;
; Initialization "Device Interrupt" Routine.   This is the main init
;   routine for the driver.
;
I_Init:	pushf			;Entry -- save CPU flags.
	push	ds		;Save CPU segment registers.
	push	es
	push	ax		;Save needed 16-bit CPU registers.
	push	bx
	push	dx
	lds	bx,cs:RqPkt	;Point to DOS "Init" packet.
	cmp	[bx].RPOp,0	;Is this really an "Init" packet?
	jne s	I_Exit		;No?  Reload regs. and exit QUICK!
	mov	[bx].RPStat,RPDON+RPERR  ;Set "Init" packet defaults.
	and	[bx].RPLen,0
	mov	[bx].RPSeg,cs
	push	ds		;Set "Init" packet segment in ES-reg.
	pop	es
	push	cs		;NOW point DS-reg. to this driver!
	pop	ds
	push	sp		;See if CPU is an 80286 or newer.
	pop	ax		;(80286+ push SP, then decrement it).
	cmp	ax,sp		;Did SP-reg. get saved "decremented"?
	jne s	I_Junk		;Yes?  CPU is an 8086/80186, TOO OLD!
	pushf			;80386 test -- save CPU flags.
	push	07000h		;Try to set NT|IOPL status flags.
	popf
	pushf			;Get resulting CPU status flags.
	pop	ax
	popf			;Reload starting CPU flags.
	test	ah,070h		;Did any NT|IOPL bits get set?
	jnz s	I_Sv32		;Yes, go save 32-bit CPU registers.
I_Junk:	mov	dx,(PRMsg-@)	;Point to "No 80386" error message.
I_Quit:	call	I_Msg		;Display "No 80386" and msg. suffix.
I_Exit:	pop	dx		;Reload 16-bit registers we used.
	pop	bx
	pop	ax
	pop	es		;Reload CPU segment registers.
	pop	ds
	popf			;Reload CPU flags and exit.
	retf
I_VErr:	mov	VEMsg.dwd,eax	;Set prefix in "VDS init error" msg.
I_VEr1:	mov	dx,(VEMsg-@)	;Point to "VDS init error" message.
I_Err:	push	dx		;Init ERROR!  Save message pointer.
	shr	VDSOf.lb,1	;Was driver "locked" by VDS?
	jnc s	I_XDis		;No, see if we reserved XMS memory.
	mov	ax,08104h	;"Unlock" this driver from memory.
	xor	dx,dx
	call	I_VDS
I_XDis:	mov	dx,CLXDH	;Load our XMS memory "handle".
	or	dx,dx		;Did we reserve any XMS memory?
	jz s	I_LDMP		;No, reload pointer & display msg.
	mov	ah,00Dh		;Unlock and "free" our XMS memory.
	push	dx
	call	I_XMS
	mov	ah,00Ah
	pop	dx
	call	I_XMS
I_LDMP:	pop	dx		;Reload error message pointer.
I_EMsg:	call	I_Msg		;Display desired error message.
	popad			;Reload all 32-bit CPU registers.
	mov	dx,(Suffix-@)	;Display message suffix and exit!
	jmp s	I_Quit
I_Sv32:	pushad			;Save all 32-bit CPU registers.
	les	si,es:[bx].RPCL	;Get command-line data pointer.
	xor	bx,bx		;Zero BX-reg. for relative logic.
I_NxtC:	cld			;Get next command-line byte.
	lods	es:[si].lb
	cmp	al,0		;Is byte the command-line terminator?
	je s	I_TrmJ		;Yes, go check for valid device name.
	cmp	al,LF		;Is byte an ASCII line-feed?
	je s	I_TrmJ		;Yes, go check for valid device name.
	cmp	al,CR		;Is byte an ASCII carriage-return?
I_TrmJ:	je	I_Term		;Yes, go check for valid device name.
	and	al,0FDh		;Mask out bit 1 of this byte.
	cmp	al,'-'		;Is byte a dash or a slash?
	jne s	I_NxtC		;No, check next command-line byte.
	mov	ax,es:[si]	;Get next 2 command-line bytes.
	and	al,0DFh		;Mask out 1st byte's lower-case bit.
	cmp	al,'A'		;Is this byte an "A" or "a"?
	jne s	I_ChkH		  ;No, see if byte is "H" or "h".
	mov	al,(ASDATA-0100h) ;Reverse all "Legacy IDE" addrs.
	mov	Ctl1Sec.lb,al
	mov	al,(APDATA-0100h)
	mov	Ctl1Pri.lb,al
	mov	al,(NSDATA-0100h)
	mov	Ctl2Sec.lb,al
	mov	al,(NPDATA-0100h)
	mov	Ctl2Pri.lb,al
I_ChkH:	cmp	al,'H'		;Is switch byte an "H" or "h"?
	jne s	I_ChkR		;No, see if byte is "R" or "r".
	mov	HFlag,al	;Set "use HMA space" flag.
I_ChkR:	cmp	al,'R'		;Is switch byte an "R" or "r"?
	jne s	I_ChkD		;No, see if bytes are "D:" or "d:".
	mov	ax,es:[si+1]	;Get next 2 command-line bytes.
	mov	cx,15296	;Get 15-MB XMS memory size.
	cmp	ax,"51"		;Does user want 15-MB XMS reserved?
	je s	I_CkRA		;Yes, set memory size to reserve.
	mov	ch,(64448/256)	;Get 63-MB XMS memory size.
	cmp	ax,"36"		;Does user want 63-MB XMS reserved?
	jne s	I_NxtC		;No, continue scan for a terminator.
I_CkRA:	mov	XMSRsv,cx	;Set desired XMS memory to reserve.
I_ChkD:	cmp	ax,":D"		;Are next 2 bytes "D:" or "d:"?
	je s	I_Nam0		;Yes, scan desired device name.
	and	ah,0DFh		;Mask out 2nd byte's lower-case bit.
	cmp	ax,"XU"		;Are next 2 bytes "UX" or "ux"?
	jne s	I_NxtJ		;No, continue scan for a terminator.
	mov	NoDMA,al	;Set CD/DVD "No UltraDMA" flag.
I_NxtJ:	jmp	I_NxtC		;Continue scanning for a terminator.
I_Nam0:	inc	si		;Device name -- Skip past "D:" bytes.
	inc	si
	mov	bl,8		;Set driver-name byte count of 8.
	mov	cx,bx
	mov	di,(DvrNam-@)	;Blank out previous driver name.
I_Nam1:	dec	bx
	mov	[bx+di].lb,' '
	jnz s	I_Nam1
I_Nam2:	mov	al,es:[si]	;Get next device-name byte.
	cmp	al,0		;Is byte the command-line terminator?
	je s	I_Term		;Yes, go check for valid device name.
	cmp	al,LF		;Is byte an ASCII line-feed?
	je s	I_Term		;Yes, go check for valid device name.
	cmp	al,CR		;Is byte an ASCII carriage-return?
	je s	I_Term		;Yes, go check for valid device name.
	cmp	al,TAB		;Is byte a "tab"?
	je s	I_NxtJ		;Yes, handle above, "name" has ended!
	cmp	al,' '		;Is byte a space?
	je s	I_NxtJ		;Yes, handle above, "name" has ended!
	cmp	al,'/'		;Is byte a slash?
	je s	I_NxtJ		;Yes, handle above, "name" has ended!
	cmp	al,'a'		;Ensure letters are upper-case.
	jb s	I_Nam3
	cmp	al,'z'
	ja s	I_Nam3
	and	al,0DFh
I_Nam3:	cmp	al,'!'		;Is this byte an exclamation point?
	je s	I_Nam4		;Yes, store it in device name.
	cmp	al,'#'		;Is byte below a pound-sign?
	jb s	I_InvN		;Yes, Invalid!  Zero first byte.
	cmp	al,')'		;Is byte a right-parenthesis or less?
	jbe s	I_Nam4		;Yes, store it in device name.
	cmp	al,'-'		;Is byte a dash?
	je s	I_Nam4		;Yes, store it in device name.
	cmp	al,'0'		;Is byte below a zero?
	jb s	I_InvN		;Yes, invalid!  Zero first byte.
	cmp	al,'9'		;Is byte a nine or less?
	jbe s	I_Nam4		;Yes, store it in device name.
	cmp	al,'@'		;Is byte below an "at sign"?
	jb s	I_InvN		;Yes, invalid!  Zero first byte.
	cmp	al,'Z'		;Is byte a "Z" or less?
	jbe s	I_Nam4		;Yes, store it in device name.
	cmp	al,'^'		;Is byte below a carat?
	jb s	I_InvN		;Yes, invalid!  Zero first byte.
	cmp	al,'~'		;Is byte above a tilde?
	ja s	I_InvN		;Yes, invalid!  Zero first byte.
	cmp	al,'|'		;Is byte an "or" symbol?
	je s	I_InvN		;Yes, invalid!  Zero first byte.
I_Nam4:	mov	[di],al		;Store next byte in device name.
	inc	si		;Bump command-line pointer.
	inc	di		;Bump device-name pointer.
	loop	I_Nam2		;If more name bytes to go, loop back.
	jmp s	I_NxtJ		 ;Go get next command byte.
I_InvN:	mov	[bx+DvrNam-@],bl ;Invalid name!  Zero first byte.
	jmp s	I_NxtJ		 ;Go get next command byte.
I_Term:	mov	ah,'.'		  ;Set a period for "stores" below.
	mov	cx,8		  ;Set driver-name byte count of 8.
	mov	di,(DvrNam-@)	  ;Point to our driver name.
	cmp	[di].lb,' '	  ;Is driver "name" valid?
	ja s	I_SetN		  ;Yes, set name in "title" message.
	mov	[di+4].dwd,"   1" ;If not, set "UDVD1" default name.
	mov	[di].dwd,"DVDU"
I_SetN:	mov	al,[di]		  ;Get next driver "name" byte.
	cmp	al,' '		  ;End of driver "name"?
	je s	I_InqX			 ;Yes, inquire about XMS mgr.
	mov	[di+(TTLName-DvrNam)],ax ;Store title byte & period.
	inc	di			 ;Bump driver "name" pointer.
	loop	I_SetN		;If more name bytes to go, loop back.
I_InqX:	mov	ax,04300h	;Inquire if we have an XMS manager.
	call	I_In2F
	mov	dx,(NXMsg-@)	;Point to "No XMS" error message.
	cmp	al,080h		;Is an XMS manager installed?
	jne	I_EMsg		;No?  Display error message and exit!
	mov	ax,04310h	;Save XMS manager "entry" address.
	call	I_In2F
	push	es
	push	bx
	pop	@XMgr3.dwd
	mov	ax,0005Fh	;Start UHDD search at 0060:0000h.
	xor	bx,bx
I_UHD1:	inc	ax		;Point ES-reg. to next memory page.
	mov	es,ax
	cmp	ax,0F800h	;Did we reach the system BIOS area?
	jae	I_UseH		;Yes, UHDD absent -- Forget about it!
	cmp	es:[bx].dwd,-1	      ;UHDD "link" still set to -1?
	je s	I_UHD1		      ;Yes, check next memory page.
	cmp	es:[bx].UHAttr,08000h ;Driver attributes correct?
	jne s	I_UHD1		      ;No, check next memory page.
	cmp	es:[bx].UHNam1,"DDHU" ;UHDD hi-order name correct?
	jne s	I_UHD1		      ;No, check next memory page.
	xor	cx,cx		   ;Indicate "stand alone" driver.
	mov	edx,es:[bx].UHNam2 ;Get last 4 UHDD name bytes.
	cmp	edx,PCMsg3.dwd	   ;"Stand alone" UHDD driver?
	je s	I_UHD2		   ;Yes, go save its segments.
	cmp	edx,'$'		  ;"Full caching" UHDD driver?
	jne s	I_UHD1		  ;No, check next memory page.
	inc	cx		  ;Indicate "full caching" driver.
I_UHD2:	mov	UHSeg,ax	  ;Found UHDD!  Save its segment
	mov	@UHSeg1,ax	  ;  for our use, where required.
	mov	ax,es:[bx].UHXHdl ;Save UHDD's XMS "handle", so we
	mov	CLXDH,ax	  ; can "share" its XMS I-O buffer.
	mov	XMSSH,ax
	mov	ax,0478Eh	  ;Enable UHDD "busy" test on entry.
	mov	@XBusy.lw,ax
	jcxz	I_UseH		;If no cache, see about HMA use.
	mov	Flush.lb,al	;Enable cache flushes as needed.
	mov	RqRL4.lb,075h	;Enable UHDD data caching calls.
	add	HMASize,CACHLEN	;Add caching logic to driver size.
I_UseH:	shl	HFlag,1		;Will we be loading in the HMA?
	jz s	I_NoHM		;No, go set our normal-memory size.
	mov	ax,04A01h	;Get "free" HMA memory size.
	call	I_In2F
	cmp	bx,HMASize	;Enough "free" HMA for our logic?
	jb s	I_NoHM		;No, go disable use of HMA space.
	mov	eax,@XMgr3.dwd	;Issue "A20 local-enable" on entry
	mov	@XMgr1.dwd,eax	;  and "A20 local-disable" on exit.
	mov	@XMgr2.dwd,eax
	mov	al,09Ah
	mov	A20Ena.lb,al
	mov	A20Dis.lb,al
	jmp s	I_TTL		;Go display driver "title" message.
I_NoHM:	mov	HFlag,0		;Ensure NO use of HMA space!
	mov	ax,HMASize	;Set "normal memory" driver size.
	add	VDSLn.lw,ax
I_TTL:	mov	si,(TTLMsg-@)	;Point to driver "title" message.
I_TTL1:	lodsb			;Get next byte of message & "swap"
	xchg	ax,dx		;  it into DL-reg. for an Int 21h.
	push	si		;Display next message byte.   If a
	mov	ah,002h		;  dollar-sign is part of a CD/DVD
	call	I_In21		;  name, this special routine will
	pop	si		;  display it properly!
	cmp	[si].lb,0	;Are we at the terminating "null"?
	jnz s	I_TTL1		;No, loop back & display next byte.
	xor	eax,eax		;Zero EAX-reg. for 20-bit addressing.
	mov	es,ax		;Point ES-reg. to low memory.
	mov	ax,cs		;Set fixed driver segment addresses
	mov	VDSSg.lw,ax	;  and our run-time entry addresses.
	mov	@CDMain.hw,ax
	mov	@CDExit.hw,ax
	mov	CLXSA.hw,ax
	mov	@DSReg,ax
	mov	StratP.dwd,(((DevInt-@)*65536)+(Strat-@))
	shl	eax,4		;Set 20-bit VDS driver address.
	mov	IOAdr,eax
	cli			      ;Avoid interrupts in VDS tests.
	test	es:[VDSFLAG].lb,020h  ;Are "VDS services" active?
	jz s	I_REnI		      ;No, re-enable CPU interrupts.
	mov	ax,08103h	;"Lock" this driver into memory.
	mov	dx,0000Ch
	call	I_VDS
	jc	I_VEr1		;If "lock" error, display msg. & exit!
	inc	VDSOf.lb	;Set initialization VDS "lock" flag.
I_REnI:	sti			;Re-enable CPU interrupts.
	xor	edi,edi		;Get PCI BIOS "I.D." code.
	mov	al,001h
	call	I_In1A
	cmp	edx,PCMsg2.dwd	;Is PCI BIOS V2.0C or newer?
	je s	I_ScnC		;Yes, scan for all IDE controllers.
	mov	dx,(IBMsg-@)	;Display "No V2.0C+ PCI" message.
	call	I_Msg
	jmp s	I_SetX		;Go do setup for our XMS manager.
I_ScnC:	mov	al,PCI_IF	;Get next "interface bit" value.
	and	ax,00003h
	or	ax,PCISubC	;"Or" in subclass & current function.
	call	I_PCIC		;Test for specific PCI class/subclass.
	rol	PCI_IF,4	;Swap both "interface bit" values.
	mov	al,PCI_IF	;Load next "interface bit" value.
	or	al,al		;Both "interface" values tested?
	jns s	I_ScnC		;No, loop back and test 2nd one.
	add	PCISubC.lb,004h	;More PCI function codes to try?
	jnc s	I_ScnC		;Yes, loop back & try next function.
	test	al,001h		;Have we tested "Native PCI" ctlrs.?
	mov	PCI_IF,093h	;(Set "Native PCI" interface bits).
	jz s	I_ScnC		;No, loop back and test them, also.
I_SetX:	cmp	CLXDH,0		;Has UHDD given us an XMS "handle"?
	jne s	I_XLok		;Yes, go get its XMS buffer address.
	mov	dx,XMSRsv	;Get "reserved" XMS memory size.
	or	dx,dx		;Does user want any "reserved" XMS?
	jz s	I_XGet		;No, get driver's actual XMS memory.
	mov	ah,009h		;Get 15-MB or 63-MB "reserved" XMS
	call	I_XMS		;  memory, which we "release" below.
	jnz s	I_XErr		;If error, display message and exit!
	mov	CLXDH,dx	;Save reserved-XMS "handle" number.
I_XGet:	mov	ah,009h		;Request 128K of XMS memory.
	mov	dx,128
	call	I_XMS
	jz s	I_XFre		;If no errors, "free" reserved XMS.
I_XErr:	mov	dx,(VEMsg-@)	;Set up "XMS init error" message.
	mov	VEMsg.lw,"MX"
I_ErrJ:	jmp	I_Err		;Go display XMS error message & exit!
I_XFre:	mov	XMSSH,dx	;Save XMS buffer "handle" numbers.
	xchg	CLXDH,dx
	or	dx,dx		;Any XMS reserved by /R15 or /R63?
	jz s	I_XLok		;No, go "lock" our XMS memory.
	mov	ah,00Ah		;"Free" our reserved XMS memory.
	call	I_XMS
	jnz s	I_XErr		;If error, display message and exit!
I_XLok:	mov	ah,00Ch		;"Lock" our driver's XMS memory.
	mov	dx,CLXDH	;(Also returns its 32-bit address).
	call	I_XMS
	jnz s	I_XErr          ;If error, display message and exit!
	shl	edx,16		;Get unaligned 32-bit buffer address.
	or	dx,bx
	mov	esi,edx		;Initialize command-list XMS offset.
	mov	eax,edx		;Copy 32-bit address to EAX-reg.
	jz s	I_XBAd		;Any low-order XMS buffer "offset"?
	mov	ax,0FFFFh	;Yes, align address to an even 64K.
	inc	eax
I_XBAd:	mov	@XBAddr,eax	;Save aligned "main buffer" address.
	mov	cx,ax		;Get buffer "offset" in XMS memory.
	sub	cx,dx
	mov	XMSSA.lw,cx	;Set offset in user-data XMS block.
	mov	edx,000010010h	;Put command-list after XMS buffer.
	jcxz	I_PRDA		;Is buffer already on a 64K boundary?
	or	edx,-16		;No, put command-list before buffer.
I_PRDA:	add	eax,edx		;Set our 32-bit PRD address.
	mov	PRDAd,eax
	sub	eax,esi		;Set final command-list XMS offset.
	mov	CLXDA,eax
I_SCD:	xor	bx,bx		;Zero BX-reg. for CD/DVD logic.
	cmp	Ctl1Tbl,-1	;Did we find any PCI controllers?
	jne s	I_SCD1		;Yes, go scan for CD/DVD drives.
	mov	Ctl1Tbl,bx	;Enable "legacy" address checks.
	mov	Ctl2Tbl,bx
I_SCD1:	cmp	[bx+USNdx-@].lb,004h ;Is this a new controller?
	jb s	I_SCD2		     ;No, get unit's I-O addresses.
	inc	CtlrNo.lb	     ;Bump display controller number.
	add	[bx+DVDTP-@].lw,6    ;Bump to next I-O addresses.
	mov	[bx+USNdx-@],bl	     ;Reset unit-select index.
I_SCD2:	mov	si,[bx+DVDTP-@]	     ;Load CD/DVD I-O addresses ptr.
	cmp	si,(CtlTEnd-@)	     ;Any more IDE units to check?
	jae s	I_AnyD		     ;No, check for any drives to use.
	mov	al,[bx+USNdx-@]	     ;Set indicated unit-select byte.
	shl	al,4
	or	al,MSEL
	mov	[bx+USelB-@],al
	mov	eax,[si]	     ;Get this unit's I-O addresses.
	cmp	ax,-1		     ;Any more controllers to check?
	je s	I_AnyD		     ;No, check for any drives to use.
	mov	[bx+DMAAd-@],eax     ;Set this unit's I-O addresses.
	test	[bx+USNdx-@].lb,002h ;Secondary-channel drive?
	jz s	I_SCD3		     ;No, see if UltraDMA is disabled.
	add	[bx+DMAAd-@].lw,8    ;Set secondary-channel addresses.
	push	[si+4]
	pop	[bx+IdeDA-@]
I_SCD3:	cmp	[bx+NoDMA-@],bl	   ;Is all UltraDMA disabled?
	jne s	I_SCD4		   ;Yes, default to no DMA address.
	or	ax,ax		   ;"Legacy IDE" with no DMA ctlr.?
	jnz s	I_SCD5		   ;No, bump index & validate unit.
I_SCD4:	or	[bx+DMAAd-@].lw,-1 ;Invalidate UltraDMA address.
I_SCD5:	inc	[bx+USNdx-@].lb	   ;Bump unit-select index.
	call	I_VCD		   ;Validate unit as ATAPI CD/DVD.
	jc s	I_SCD1		   ;If invalid, merely ignore it.
	mov	si,[bx+UTblP-@]	   ;Update unit-table parameters.
	mov	eax,[bx+DMAAd-@]
	mov	[si],eax
	mov	al,[bx+USelB-@]
	mov	[si+4],al
	add	si,18		   ;Update unit-table pointer.
	mov	[bx+UTblP-@],si
	inc	[bx+CDUnits-@].lb  ;Bump number of active units.
	inc	CDMsgNo		   ;Bump display unit number.
	cmp	si,(UTblEnd-@)	;Can we install another drive?
	jb	I_SCD1		;Yes, loop back and check for more.
I_AnyD:	mov	dx,(NDMsg-@)	;Point to "Nothing to use" message.
	cmp	CDUnits,0	;Do we have any CD/DVD drives to use?
	jz	I_Err		;No?  Display error message and exit!
	shr	HFlag,1		;Will we be loading in the HMA?
	jz s	I_Done		;No, go post "Init" packet results.
	mov	ah,005h		;Issue "A20 local-enable" request.
	call	I_XMS
I_A20E:	mov	eax," 02A"	;Get "A20" error-message prefix.
	jnz s	I_HMAX		;If any "A20" error, bail out QUICK!!
	mov	ax,04A02h	;Request needed memory in the HMA.
	mov	bx,HMASize
	call	I_In2F
	push	es		;Get our 32-bit HMA base address.
	push	di
	pop	eax
	mov	@CDMain,eax	;Set CD/DVD entry routine address.
	inc	eax		;Is our HMA address -1 (no HMA)?
	jnz s	I_HMA1		;No, adjust addresses for HMA usage.
	call	I_A20D		;BAAAD News!  Do "A20 local-disable".
	mov	eax," AMH"	;Get "HMA" error-message prefix.
I_HMAX:	jmp	I_VErr		  ;Go display error message & exit!
I_HMA1:	lea	ax,[di-(CDReq-@)] ;Get starting HMA logic offset.
	add	@UTable,ax	  ;Adjust CD/DVD table pointers.
	add	@DspTB2,ax
	add	@DspTB3,ax
	add	@DspTB4,ax
	add	@DspOfs,ax	;Adjust CD/DVD dispatch offset.
	add	CLXPtr,ax	;Adjust our XMS block pointers.
	add	XMSPtr,ax
	add	@CBAddr,ax	;Adjust UHDD "callback" address.
	mov	cx,HMASize	;Move needed logic up to the HMA.
	mov	si,(CDReq-@)
	rep	movsb
	call	I_A20D		;Issue "A20 local-disable" request.
I_Done:	popad			;Done!  Reload all 32-bit CPU regs.
	les	bx,RqPkt	;Set results in DOS "init" packet.
	mov	ax,VDSLn.lw
	mov	es:[bx].RPLen,ax
	mov	es:[bx].RPStat,RPDON
	pop	dx		;Reload 16-bit registers we used.
	pop	bx
	pop	ax
	pop	es		;Reload CPU segment registers.
	pop	ds
	popf			;Reload CPU flags and exit.
	retf
;
; Init subroutine to test for and set up each PCI controller.
;
I_PCIX:	ret			     ;(Local exit, used below).
I_PCIC:	mov	IdeDA,ax	     ;Save subclass & function codes.
	and	PCIDevX,0	     ;Reset PCI device index.
I_PCI1:	cmp	CtlrAdP,(CtlTEnd-@)  ;More space in address tables?
 	jae s	I_PCIX		     ;No, go exit above.
	mov	ax,IdeDA	;Test PCI class 1, subclass/function.
	mov	ecx,000010003h	;(Returns bus/device/function in BX).
	xchg	ax,cx
	mov	si,PCIDevX
	call	I_In1A
	jc s	I_PCIX		;Controller not found -- exit above.
	inc	PCIDevX		;Bump device index for another test.
	xor	di,di		;Get controller Vendor & Device I.D.
	call	I_PCID
	push	ecx		;Save Vendor and Device I.D.
	mov	di,32		;Save DMA controller base address.
	call	I_PCID
	xchg	ax,cx
	and	al,0FCh
	mov	DMAAd,ax
	mov	si,(PCMsg2-@)	;Set controller address in msg.
	call	I_Hex
	mov	si,(PCMsg3-@)	;Set vendor I.D. in message.
	pop	ax
	call	I_Hex
	pop	ax		;Set Device I.D. in message.
	call	I_Hex
	mov	di,4		;Get low-order PCI command byte.
	call	I_PCID
	not	cl		;Get "Bus Master" & "I-O Space" bits.
	and	cl,005h		;Is controller using both BM and IOS?
	jz s	I_PCI2		;Yes, save this controller's data.
	mov	dx,(BCMsg-@)	;Display "BAD controller!", and hope
	call	I_Msg		;  our user can find a better BIOS!
	mov	dx,(PCMsg1-@)
	call	I_Msg
I_PCIJ:	jmp s	I_PCI1		;Go test for more same-class ctlrs.
I_PCI2:	mov	si,CtlrAdP	;Get current I-O address table ptr.
	mov	ax,DMAAd	;Set controller DMA base address.
	mov	[si],ax
	test	PCI_IF,001h	;Is this a "Native PCI" controller?
	jz s	I_PCI3		;No, go display controller data.
	mov	di,16		;Set primary-channel base address.
	call	I_PCID
	and	cl,0FCh
	mov	[si+2],cx
	mov	di,24		;Set secondary-channel base address.
	call	I_PCID
	and	cl,0FCh
	mov	[si+4],cx
I_PCI3:	mov	dx,(PCMsg-@)	;Display all controller data.
	call	I_Msg
	inc	[PCMsg+3].lb	;Bump controller number in message.
	add	CtlrAdP,CTLTSIZ	;Bump controller address-table ptr.
	jmp s	I_PCIJ		;Go test for more same-class ctlrs.
;
; Init subroutine to "validate" an IDE unit as an ATAPI CD/DVD drive.
;
I_VCD:	mov	dx,[bx+DMAAd-@]	;Get unit UltraDMA command address.
	test	dl,001h		;Will this unit be using UltraDMA?
	jnz s	I_VC0		;No, just select "master" or "slave".
	in	al,dx		;Ensure any previous DMA is stopped!
	and	al,0FEh
	out	dx,al
I_VC0:	mov	bp,[bx+IdeDA-@]	;Get drive's IDE address in BP-reg.
	lea	dx,[bp+CDSEL]	;Point to IDE device-select register.
	mov	al,[bx+USelB-@]	;Select IDE "master" or "slave" unit.
	out	dx,al
	call	ChkTO		;Await controller-ready.
	jc s	I_VC7		;If timeout, go exit below.
	mov	al,0A1h		;Issue "Identify Packet Device" cmd.
	out	dx,al
	call	ChkTO		;Await controller-ready.
	jc s	I_VC7		;If timeout, go exit below.
	test	al,DRQ		;Did we also get a data-request?
	jz s	I_VC6		;No, go set carry & exit below.
	mov	dx,bp		;Point back to IDE data register.
	in	ax,dx		;Read I.D. word 0, main device flags.
	and	ax,0DF03h	;Mask off flags for an ATAPI CD/DVD.
	xchg	ax,si		;Save main device flags in SI-reg.
	mov	cx,26		;Skip I.D. words 1-26 (unimportant).
I_VC1:	in	ax,dx
	loop	I_VC1
	mov	di,(CDName-@)	;Point to drive "name" buffer.
	push	cs
	pop	es
	mov	cl,20		;Read & swap words 27-46 into buffer.
I_VC2:	in	ax,dx		;(Manufacturer "name" of this drive).
	xchg	ah,al
	stosw
	loop	I_VC2
	mov	cl,7		;Skip I.D. words 47-52 (unimportant)
I_VC3:	in	ax,dx		;  and read I.D. word 53 into AX-reg.
	loop	I_VC3
	mov	[bx+UFlag-@],al	;Save UltraDMA "valid" flags.
	mov	cl,35		;Skip I.D. words 54-87 (unimportant)
I_VC4:	in	ax,dx		;  and read I.D. word 88 into AX-reg.
	loop	I_VC4
	mov	[bx+UMode-@],ah	;Save posted UltraDMA "mode" value.
	mov	cl,167		;Skip all remaining I.D. data.
I_VC5:	in	ax,dx
	loop	I_VC5
	cmp	si,08500h	;Do device flags say "ATAPI CD/DVD"?
	je s	I_VC8		;Yes, see about UltraDMA use.
I_VC6:	stc			;Set carry flag on (error!) and exit.
I_VC7:	ret
I_VC8:	test	[bx+UFlag-@].lb,004h ;Valid UltraDMA "mode" bits?
	jz s	I_VC9		     ;No, disable drive UltraDMA.
	cmp	[bx+UMode-@],bl	     ;Can drive do mode 0 minimum?
	jne s	I_VC10		     ;Yes, display "Unit n:" msg.
I_VC9:	or	[bx+DMAAd-@].lb,1    ;Disable this drive's UltraDMA.
I_VC10:	mov	dx,(CDMsg-@)	     ;Display "CDn:  " message.
	call	I_Msg
	mov	dx,(PriMsg-@)	     ;Point to "Primary" message.
	test	[bx+IdeDA-@].lb,080h ;Primary-channel drive?
	jnz s	I_VC11		     ;Yes, display "Primary" msg.
	mov	dx,(SecMsg-@)	     ;Point to "Secondary" message.
I_VC11:	call	I_Msg		     ;Display CD/DVD's IDE channel.
	mov	dx,(MstMsg-@)	     ;Point to "Master" message.
	cmp	[bx+USelB-@].lb,SSEL ;Is this drive a "slave"?
	jnz s	I_VC12		     ;No, display "Master".
	mov	dx,(SlvMsg-@)	     ;Point to "Slave" message.
I_VC12:	call	I_Msg		  ;Display "Master" or "Slave".
	mov	si,(CDName+40-@)  ;Point to end of CD/DVD name.
I_VC13:	cmp	si,(CDName-@)	  ;Are we at the vendor-name start?
	je s	I_VC14		  ;Yes, vendor name is all spaces!
	dec	si		  ;Decrement vendor-name pointer.
	cmp	[si].lb,' '	  ;Is this name byte a space?
	je s	I_VC13		  ;No, continue scan for non-space.
	inc	si		  ;Skip non-space character.
	mov	[si].lw," ,"	  ;End disk name with comma/space.
	inc	si		  ;Skip comma and space.
	inc	si
I_VC14:	test	[bx+DMAAd-@].lb,1 ;Will this drive use "PIO mode"?
	jz s	I_VC15		  ;No, get drive's UltraDMA "mode".
	mov	[si].dwd,"OIP"	  ;Set "PIO" after drive name.
	add	si,3
	jmp s	I_VC18		;Go set message terminators.
I_VC15:	mov	cx,[bx+UMode-@]	;Initialize UltraDMA "mode" scan.
	mov	di,(Modes-2-@)
I_VC16:	inc	di		;Advance to next UltraDMA "mode".
	inc	di
	shr	cx,1		;Will drive do next "mode"?
	jnz s	I_VC16		;Yes, keep scanning for maximum.
I_VC17:	mov	[si].dwd,"-ATA"	;Set "ATA-" after drive name.
	add	si,4
	mov	ax,[di]		;Set UltraDMA "mode" in message.
	mov	cl,00Fh
	and	cl,al
	call	I_HexA
I_VC18:	mov	[si].dwd,0240A0D2Eh ;Set message terminators.
	mov	dx,(DNMsg-@)	    ;Display mfr. name/"mode" & exit.
	jmp s	I_Msg
;
; Init subroutines to issue "external" calls.
;
I_A20D:	mov	ah,006h		;"A20 local-disable" -- get XMS code.
I_XMS:	call	@XMgr3.dwd	;XMS -- issue desired request.
	dec	ax		;Zero AX-reg. if success, -1 if error.
	jmp s	I_IntX		;Restore driver settings, then exit.
I_VDS:	mov	di,(VDSLn-@)	;VDS -- Point to parameter block.
	push	cs
	pop	es
	int	04Bh		;Execute VDS "lock" or "unlock".
	jmp s	I_IntX		;Restore driver settings, then exit.
I_PCID:	push	bx		;Save PCI bus/device/function codes.
	push	si		;Save IDE address-table pointer.
	mov	al,00Ah		;Set "PCI doubleword" request code.
	call	I_In1A		;Get desired 32-bit word from PCI.
	pop	si		;Reload IDE address-table pointer.
	pop	bx		;Reload PCI bus/device/function.
	ret			;Exit.
I_In1A:	mov	ah,0B1h		;Issue PCI BIOS interrupt.
	int	01Ah
	jmp s	I_IntX		;Restore driver settings, then exit.
I_Msg:	push	bx		;Message -- save our BX-register.
	mov	ah,009h		;Issue DOS "display string" request.
	int	021h
	pop	bx		;Reload our BX-register.
	jmp s	I_IntX		;Restore driver settings, then exit.
I_In21:	int	021h		;General DOS request -- issue Int 21h.
	jmp s	I_IntX		;Restore driver settings, then exit.
I_In2F:	int	02Fh		;"Multiplex" -- issue XMS/HMA request.
I_IntX:	sti			;RESTORE all critical driver settings!
	cld			;(Never-NEVER "trust" external code!).
	push	cs
	pop	ds
	ret			;Exit.
;
; Init subroutine to convert 4-digit hex values to ASCII for messages.
;   At entry, the number is in the AX-reg., and the message pointer is
;   in the SI-reg.   At exit, SI is updated, and the CX-reg. is zero.
;
I_Hex:	mov	cx,4		;Set 4-digit count.
I_HexA:	rol	ax,4		;Get next hex digit in low-order.
	push	ax		;Save remaining digits.
	and	al,00Fh		;Mask off next hex digit.
	cmp	al,009h		;Is digit 0-9?
	jbe s	I_HexB		;Yes, convert to ASCII.
	add	al,007h		;Add A-F offset.
I_HexB:	add	al,030h		;Convert digit to ASCII.
	mov	[si],al		;Store next digit in message.
	inc	si		;Bump message pointer.
	pop	ax		;Reload remaining digits.
	loop	I_HexA		;If more digits to go, loop back.
	ret			;Exit.
CODE	ends
	end
