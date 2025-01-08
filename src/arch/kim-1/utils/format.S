; ---------------------------------------------------------------------------
;
; K-1013 format utility
;
; Copyright (C) 2024 Eduardo Casino
; This file is licensed under the terms of the 2-cluse BSD license. Please
; see the COPYING file in the root project directory for the full test.
;
; The low-level disk routines are basically copied from MTU's K-1013
; diagnostics.
;
; ---------------------------------------------------------------------------

#include "zif.inc"
#include "cpm65.inc"

; K-1013 FDC registers

HSRC = $ffe8                ; R/W   - K-1003 Hardware Status Register
ADMA = $ffea                ; Write - K-1013 Set DMA Address Register
MSTR = $ffee                ; Read  - NEC-765 Main Status Register
DATR = $ffef                ; R/W   - NEC-765 Data Register

; Disk buffer

DISK_BUFFER = $fe00
BUFFER_DMA  = $f8           ; Disk buffer address DMA encoded (see K-1013 manual)

NSTAG = 8                   ; Number of sectors to stagger per track

zproc main
    ; Get drive from command line

    lda cpm_fcb+1
    cmp #' '                ; File name must be empty
    bne usage
	lda cpm_fcb
    cmp #0                  ; Drive number can't be default
    beq usage

    ; Get drive number in base 0 and drive leter

    sec
    sbc #1
    sta drive
    clc
    adc #'A'
    sta drive_letter

    ; Check if the drive exists

    lda drive
    ldy #BIOS_SELDSK
    jsr BIOS
    bcs invalid

    ; Warning message

    lda drive_letter
    sta warning_drv
    lda #<warning_msg
    ldx #>warning_msg
    ldy #BDOS_WRITE_STRING
    jsr BDOS

    ; Get confirmation

    ldy #BDOS_CONSOLE_INPUT
    jsr BDOS
    cmp #'y'
    bne abort

    lda #<crlf
    ldx #>crlf
    ldy #BDOS_WRITE_STRING
    jsr BDOS

    jsr format

    zif_cc
        lda #<done_msg
        ldx #>done_msg
        ldy #BDOS_WRITE_STRING
        jmp BDOS
    zendif

    rts

invalid:
    lda drive_letter
    sta invalid_drv
    lda #<invalid_msg
    ldx #>invalid_msg
    ldy #BDOS_WRITE_STRING
    jsr BDOS

usage:
    lda #<usage_msg
    ldx #>usage_msg
    ldy #BDOS_WRITE_STRING
    jmp BDOS

abort:
    lda #<abort_msg
    ldx #>abort_msg
    ldy #BDOS_WRITE_STRING
    jmp BDOS

zendproc

zproc print_dot
    lda #'.'
    ldy #BIOS_CONOUT
    jmp BIOS
zendproc

zproc format
    ; Put the disk controller in a sane state

    lda HSRC                ; Test if an interrupt is pending
    zif_mi
        ldx #snsicm-dskcmd  ; Execute sense interrupt status command
        ldy #1
        jsr command_phase
        ldx #0              ; Read status bytes
        jsr result_phase
    zendif

    ; Recalibrate (send heads to track 0)

    lda drive
    jsr recalibrate
    zif_cs
        jmp recal_error
    zendif

    lda #0                  ; Set DMA read mode, unprotect SYSRAM
    sta HSRC
    sta side                ; Initialize disk side,
    sta track               ; track number
    sta stagger             ; and stagger factor

    ; Create formatting data area for next track
    ; We are using the 256-byte disk buffer at $fe00 for this

    zloop
        jsr print_dot

        ldx stagger         ; Initialize sector number pointer
        ldy #0              ; Initialize pointer into format data area
        zrepeat
            lda track       ; Put track number,
            sta DISK_BUFFER,Y
            iny
            lda side        ; side number
            sta DISK_BUFFER,Y
            iny
            lda alttab,X    ; Lookup sector number in alternate table
            sta DISK_BUFFER,Y
            iny
            lda formcm+2    ; Number of bytes per sector
            sta DISK_BUFFER,Y
            iny
            inx             ; Increment sector number pointer
            txa             ; Mod 26
            jsr mod26
            tax
            cpy #26*4       ; Test if 26 sectors gone through
        zuntil_eq

        ; Set up the FORMAT command

        lda #BUFFER_DMA     ; Set DMA addres for formatting data
        sta ADMA
        lda side            ; Set up second byte of FORMAT command
        asl A               ; according to drive number and side
        asl A
        ora drive
        sta formcm+1
        ldx #formcm-dskcmd
        ldy #6              ; FORMAT command is 6 bytes long
        jsr command_phase   ; Send the command to the controller
        zif_cs
            jmp format_error
        zendif

        ldy #0              ; Wait a while before seeking to prevent
        zrepeat             ; overlap with erase current on disk drive
            dey
        zuntil_eq

        lda stagger         ; Add in stagger factor for next track
        clc
        adc #26-NSTAG
        jsr mod26           ; Sum mod 26
        sta stagger         ;

        inc track           ; Increment track number
        lda track
        cmp #77             ; Test if all tracks formatted
        zbreakif_eq         ; If so, finished

        tax                 ; Seek to the new track
        jsr seek
        zif_cs
            jmp seek_error
        zendif
    zendloop

    clc
    rts
zendproc

; Floppy disk recalibrate
; Seeks the drive number loaded into A to track 0
;
zproc recalibrate
    and #$03                ; Format drive number into second byte of 
    sta reclcm+1            ; recalibrate command
    lda #0                  ; Save new cylinder number (0) to the stack
    pha
    ldx #reclcm-dskcmd      ; Execute recalibrate command
    ldy #2                  ; which is 2 bytes long

    jmp execute_seek
zendproc

; Seek track loaded into X
; drive and side must be set
;
zproc seek
    lda side                ; Set up second byte of SEEK command
    asl A                   ; according to drive number and side
    asl A
    ora drive
    sta seekcm+1            ; SEEK command and select head 0
    stx seekcm+2            ; Store new cylinder number into third byte
    txa                     ; Save new cylinder number on the stack
    pha
    ldx #seekcm-dskcmd      ; Execute the SEEK command
    ldy #3                  ; which is 3 bytes long
zendproc
; Fallthrough
zproc execute_seek
    jsr command_phase
    bcs ret_error           ; Jump out if error

    zrepeat
        lda HSRC            ; Wait until FDC requests an interrupt
    zuntil_pl

    ldx #snsicm-dskcmd      ; Execute a sense interrupt status command
    ldy #1                  ; which is 1 byte long
    jsr command_phase

    ldx #0                  ; Read status into dsksts
    jsr result_phase

    pla                     ; Compare present cylinder number with
    cmp dsksts+1            ; desired cylinder number
    bne ret_error           ; Error if non-zero
    lda dsksts              ; Look at ST0 status register
    and #$f8                ; Delete don't care bits
    cmp #$20                ; Remaining bits must be $20
    bne ret_error           ; Otherwise, it's an error
    clc
    rts
zendproc

; Command execution phase
; Executes command at offset X of the diskcmd table
;
zproc command_phase
    lda MSTR                ; Check that the controller is
    and #$10                ; ready to accept commands
    zif_eq
        zrepeat
            zrepeat
                lda MSTR    ; Wait until request for master goes true
            zuntil_mi
            and #$40        ; Test data direction bit
            bne ret_error   ; Error if FDC wants to talk
            lda dskcmd,x    ; Gte a command byte
            sta DATR        ; Store it into the FDC data register
            inx             ; Point to next command byte
            dey             ; Decrement command byte count
        zuntil_eq           ; Transfer until no more bytes
        clc                 ; Clear carry for normal return
        rts
    zendif
zendproc
; Fallthrough
zproc ret_error 
    sec                     ; Set carry for error return
    rts
zendproc

; Command result phase
; Reads status registers into dsksts
;
zproc result_phase
    zrepeat
        zrepeat
            lda MSTR        ; Wait until request for master goes true
        zuntil_mi
        and #$40            ; Test data direction bit
        beq ret_error       ; Error if FDC wants to lisen
        lda DATR            ; Get a status byte from the FDC data register
        sta dsksts,x
        inx                 ; Point to next status byte
        nop                 ; Give time to the controller chip
        nop
        lda #$10            ; Check if there are more result bytes
        and MSTR
    zuntil_eq
    clc
    rts
zendproc

; Calculate modulo 26 of A
;
zproc mod26
    zloop
        cmp     #26         ; Return a mod 26
        zbreakif_cc
        sbc     #26         ; If not, substract 26
    zendloop
    rts
zendproc

; Error routines: Print error message, set carry and return
;
zproc recal_error
    lda #<recal_msg
    ldx #>recal_msg
    jmp print_err
zendproc

zproc seek_error
    lda #<seek_msg
    ldx #>seek_msg
    ldy #BDOS_WRITE_STRING
    jsr BDOS
    lda track
    jsr print_byte
    lda #<seek_msg2
    ldx #>seek_msg2
    jmp print_err
zendproc

zproc format_error
    lda #<format_msg
    ldx #>format_msg
    ldy #BDOS_WRITE_STRING
    jsr BDOS
    lda track
    jsr print_byte
    lda #<format_msg2
    ldx #>format_msg2
zendproc
; Fallthrough
zproc print_err
    ldy #BDOS_WRITE_STRING
    jsr BDOS
    sec
    rts
zendproc

; This routine assumes A < 100 (disk has 77 tracks)
;
; Derived from https://beebwiki.mdfs.net/Number_output_in_6502_machine_code
;
zproc print_byte
    ldx #$ff
    sec
    zrepeat
        inx                 ; Count number of 10s
        sbc #10
    zuntil_cc
    adc #10
    pha                     ; Save units
    txa
    zif_ne
        jsr print_digit
    zendif
    pla                     ; Restore units
zendproc
; fallthrough
zproc print_digit
    ora #'0'
    ldy #BIOS_CONOUT
    jmp BIOS
zendproc

    .bss

; Uninitiaized program variables

drive:          .fill 1
drive_letter:   .fill 1
side:           .fill 1
track:          .fill 1
sector:         .fill 1
stagger:        .fill 1

dsksts:         .fill 8         ; Room for 8 status bytes from FDC

    .rodata

; Constants

alttab: .byte   0,  13, 1,  14  ; Table of interleaved sector numbers
        .byte   2,  15, 3,  16  ; Interleave factor = 2
        .byte   4,  17, 5,  18
        .byte   6,  19, 7,  20
        .byte   8,  21, 9,  22
        .byte   10, 23, 11, 24
        .byte   12, 25

    .data

; Disk commands. Some bytes are modified by the program

dskcmd:                         ; Start of preformatted disk commands
sstscm: .byte   $04             ; SENSE DISK STATUS command
        .byte   $00             ; Drive number in bits 0-1, side number B2
reclcm: .byte   $07             ; RECALIBRATE command
        .byte   $00             ; Drive number in bits 0-1
snsicm: .byte   $08             ; SENSE INTERRUPT STATUS command
seekcm: .byte   $0f             ; SEEK command
        .byte   $00             ; Drive number in bits 0-1, side number B2
        .byte   $00             ; New cylinder number
formcm: .byte   $4d             ; FORMAT a double density track command
        .byte   $00             ; Head 0, Drive number in bits 0-1
        .byte   $01             ; Specify 256 bytes/sector
        .byte   $1a             ; Specify 26 sectors/track
        .byte   $36             ; Gap length for 26 sectors, 256 bytes/sect
        .byte   $e5             ; Data field filler byte

; Messages

invalid_msg:    .ascii "Error: invalid drive '"
invalid_drv:    .byte 0
                .ascii "'."
crlf:           .byte 13,10,0

usage_msg:      .ascii "Syntax: format <drive>"
                .byte 13,10,0

warning_msg:    .ascii "Warning: about to format drive '"
warning_drv:    .byte 0
                .ascii "',destroying everything on it."
                .byte 13,10
                .ascii "Press Y to proceed, anything else to cancel: "
                .byte 0

abort_msg:      .byte 13,10
                .ascii "Aborted by user."
                .byte 13,10,0

done_msg:       .byte 13,10
                .ascii "Done."
                .byte 13,10,0

recal_msg:      .ascii "Error: Unable to retract head to track 0."
                .byte 13,10,0

seek_msg:       .byte 13,10
                .ascii "Error: Unable to position head over cylinder "
                .byte 0
seek_msg2:      .byte '.',13,10,0

format_msg:     .byte 13,10
                .ascii "Error: Unable to format track "
                .byte 0
format_msg2:    .byte '.',13,10,0
