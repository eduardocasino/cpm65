; CP/M-65 Copyright © 2022 David Given
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.

; KIM-1 port Copyright © 2024 Eduardo Casino

; K-1013 FDC registers

HSRC = 0xffe8           ; R/W   - K-1003 Hardware Status Register
ADMA = 0xffea           ; Write - K-1013 Set DMA Address Register
MSTR = 0xffee           ; Read  - NEC-765 Main Status Register
DATR = 0xffef           ; R/W   - NEC-765 Data Register

; Disk buffer

DISK_BUFFER = $fe00
BUFFER_DMA  = $f8       ; Disk buffer address DMA encoded (see K-1013 manual)
