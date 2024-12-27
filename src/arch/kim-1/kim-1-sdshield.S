; CP/M-65 Copyright © 2022 David Given
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.

; KIM-1 port Copyright © 2024 Eduardo Casino

#include "zif.inc"
#include "cpm65.inc"

#include "kim-1.S"

#define SECTORS_PER_TRACK 52

.section loader, "ax"

    ; System init

zproc system_init, loader
    lda #0
    sta current_drive
    sta pending_key
    sta buffer_dirty

    lda #0xff
    sta buffered_host_sector            ; Mark buffer data as invalid

    ; Initialize Disk Parameter Block

    lda #<DISK_BUFFER
    sta zp_sds_buffer+0
    lda #>DISK_BUFFER
    sta zp_sds_buffer+1

    lda #SECTORS_PER_TRACK
    sta zp_sds_spt

    ; Determine RAM size. Assumes at least a memory expansion from 0x2000 to 0x9fff

    ldy #0
    sty ptr+0
    lda #0xa0
    sta ptr+1

    zloop
        lda #0x55
        sta (ptr), y
        lda (ptr), y
        cmp #0x55
        bne 1f
        lda #0xaa
        sta (ptr), y
        lda (ptr), y
        cmp #0xaa
        bne 1f
        iny
        zif_eq
            inc ptr+1
            lda ptr+1
            cmp #0xff
            beq 1f
        zendif
    zendloop
1:  lda ptr+1
    sta mem_end

    rts
zendproc

.text

; Set the current absolute sector number.
; XA is a pointer to a three-byte number.

zproc bios_SETSEC
    sta ptr+0
    stx ptr+1

    ; Copy bottom 16 of sector number to temporary (the top byte must be 0).

    ldy #0
    lda (ptr), y
    sta ptr1+0
    iny
    lda (ptr), y
    sta ptr1+1

    ; There are 52 CP/M sectors per host track (each 256 byte host sector
    ; contains two CP/M sects). Do a 16-bit divide.

    ldx #16
    lda #0
    zrepeat
        asl ptr1+0
        rol ptr1+1
        rol a
        cmp #52
        zif_cs
            sbc #52
            inc ptr1+0
        zendif
        dex
    zuntil_eq

    ; Host sectors are 256 bytes long, so divide by 2 and put carry as MSB of
    ; buffer_offset
    lsr a
    sta requested_cpm_sector
    lda #0
    ror a
    sta buffer_offset

    lda ptr1+0
    sta requested_track

    clc
    rts
zendproc

; --- Disk access -----------------------------------------------------------

; This assumes that DISK_BUFFER is page aligned!!

zproc set_disk_buffer_offset
    ; WARNING: DISK_BUFFER __must__ be page aligned!!

    lda buffer_offset
    sta ptr+0
    lda #>DISK_BUFFER
    sta ptr+1

    rts
zendproc

zproc change_sector
    ; First check if requested sector is already in buffer

    lda requested_cpm_sector
    cmp buffered_host_sector
    zif_eq
        lda requested_track
        cmp buffered_track
        zif_eq
            lda current_drive
            cmp buffered_drive
            zif_eq
                ; Buffered disk/track/sector not changing, so do no work.

                clc
                rts
            zendif
        zendif
    zendif

    ; If requested sector is not buffered, flush buffer before changing

    bit buffer_dirty
    zif_mi
        jsr flush_buffer
        zif_cs
            rts
        zendif
    zendif

    ; Change sector

    lda current_drive
    sta buffered_drive
    lda requested_track
    sta buffered_track
    lda requested_cpm_sector
    sta buffered_host_sector

    ; Read sector from disk

    lda buffered_host_sector
    sta zp_sds_sector
    lda buffered_track
    sta zp_sds_track
    lda buffered_drive
    sta zp_sds_drive

    jsr DiskReadSector
    zif_cc
        rts
    zendif

    ; Some kind of read error. The data in the buffer is corrupt.

    lda #0xff
    sta buffered_host_sector

    rts
zendproc

zproc flush_buffer
    lda buffered_host_sector
    sta zp_sds_sector
    lda buffered_track
    sta zp_sds_track
    lda buffered_drive
    sta zp_sds_drive

    jsr DiskWriteSector
    zif_cc
        ; A successful write, so mark the buffer as clean.

        lda #0
        sta buffer_dirty
        rts
    zendif

    sec
    rts
zendproc

; --- Data ------------------------------------------------------------------

.data

; DPH for drive 0

define_drive dph0, 77*52, 2048, 128, 52

.bss

requested_cpm_sector:   .fill 1     ; CP/M sector requested by user
requested_track:        .fill 1     ; track requested by user
buffered_host_sector:   .fill 1     ; host sector in buffer
buffered_track:         .fill 1     ; track in buffer
buffered_drive:         .fill 1     ; Drive of track/sector in buffer
