;;;
;; Day 4 https://adventofcode.com/2023/day/4
;;
;; TODO

.segment "HEADER"
    .byte 'N', 'E', 'S', $1A

    .byte $02
    .byte $01

    .byte $00
    .byte $00

.segment "VECTORS"
    .addr nmi, reset, irq

.segment "CHARS"
    .incbin "../assets/alphanum.chr"

.segment "STARTUP"
.segment "CODE"

.include "../vendor/bcd16.s"

.include "../include/apu.s"
.include "../include/oam.s"
.include "../include/ppu.s"
.include "../include/reset.s"
.include "../include/globals.s"
.include "../include/print.s"

.include "../test/defines.s"

;; "Variables" used by this program.
.scope Vars
    ;; Variables used when parsing numbers, and also used as temporary values
    ;; after that.
    m_num_1 = $00
    m_num_2 = $01
    m_num_3 = $02

    ;; The base address of the current row being evaluated.
    ;;
    ;; NOTE: 16-bit ($03-$04)
    m_address = $03

    ;; The number that has been accumulated for the current row.
    ;;
    ;; NOTE: 16-bit ($05-$06).
    m_row = $05

    ;; The number which is the result of adding up the previous row values.
    ;;
    ;; NOTE: 16-bit ($07-$08).
    m_total = $07

    ;; List of winning numbers. Note that we assume that a row will have 10
    ;; elements maximum (guaranteed by the enunciate).
    m_list = $10

    ;; Index of the next position to write into the `m_list`. That is, it's also
    ;; the size of the `m_list` when we are done filling it.
    m_list_index = $1A

    ;; Initialize some of the variables.
    .proc init
        lda #0
        sta m_total
        sta m_total + 1

        lda #.LOBYTE(data)
        sta Vars::m_address
        lda #.HIBYTE(data)
        sta Vars::m_address + 1

        rts
    .endproc
.endscope

;; The main function will be called at the end of the `reset` vector as defined
;; in `include/reset.s`.
.proc main
    ;; Initialize palettes and variables being used for this program.
    jsr Print::load_basic_palettes
    jsr Vars::init

    ;; This program uses two flags:
    ;;   - 7 (`render`): whether NMI-code can render stuff on screen.
    ;;   - 6 (`done`): whether the computation has been done.
    ;; Note that we are setting the render flag so the initial message is
    ;; shown.
    lda #%10000000
    sta Globals::m_flags

    cli

    lda #%10010000
    sta PPU::CONTROL
    lda #%00011110
    sta PPU::MASK

@loop:
    ;; Skip everything if the `done` flag is set.
    bit Globals::m_flags
    bvs @end

    jsr compute_next
    jmp @loop

@end:
    ;; Run tests now that everything has been done.
.ifdef RUN_TESTS
@test:
    nop
.endif
@halt:
    jmp @halt
.endproc

;; Compute the next card if needed.
.proc compute_next
    jsr compute_row

    ;; `compute_row` leaves the `y` register right at the end of the current
    ;; string (`\0` character). Now let's increase this value to get into the
    ;; first byte of the next row and add it into the base `Vars::m_address`, so
    ;; it's prepared for the next iteration.
    iny
    tya
    clc
    adc Vars::m_address
    sta Vars::m_address
    lda #0
    adc Vars::m_address + 1
    sta Vars::m_address + 1

    ;; Are we actually at the end of the exercise? If not, return early.
    ldy #0
    lda (Vars::m_address), y
    cmp #$ED
    bne @end

    ;; Mark the `done` flag so future iterations don't go through all of this.
    lda #%01000000
    ora Globals::m_flags
    sta Globals::m_flags

    ;; Store the 16-bit number into `bcdNum` and call `bcdConvert` so it's
    ;; converted into a format that can be displayed on screen.
    lda Vars::m_total
    sta bcdNum
    lda Vars::m_total + 1
    sta bcdNum + 1
    jsr bcdConvert

    ;; Because of the previous, we can set the `render` flag again.
    SET_RENDER_FLAG
@end:
    rts
.endproc

;; Evaluate the current row and add up the results.
.proc compute_row
    ;; Basically: set the winning list (left of the `|` character), and check it
    ;; with the numbers we have on the right of the `|` character.
    jsr skip_card_title
    jsr fill_winning_list
    jsr check_given_list

    ;; And add the value we have just computed with the general `Vars::m_total`
    ;; variable.
    lda Vars::m_row
    clc
    adc Vars::m_total
    sta Vars::m_total
    lda Vars::m_row + 1
    adc Vars::m_total + 1
    sta Vars::m_total + 1

    rts
.endproc

;; Each row starts with a title, call this subroutine to leave `y` at a point
;; where that has been skipped.
.proc skip_card_title
    ldy #0
@loop:
    lda (Vars::m_address), y
    cmp #$3A
    beq @done
    iny
    jmp @loop
@done:
    rts
.endproc

;; Fill the winning list with the numbers that can be parsed before the `|`
;; character.
.proc fill_winning_list
    lda #0
    sta Vars::m_list_index

@loop:
    ;; If this is the `|` character, then we are done. Otherwise, if this is not
    ;; a numeric value, then we need to move into the next byte.
    lda (Vars::m_address), y
    cmp #$7C
    beq @done
    sec
    sbc #48
    bcc @next
    cmp #10
    bcs @next

    ;; This is a numeric value: parse the whole number and push it into the
    ;; `Vars::m_list` array.
    jsr parse_number
    ldx Vars::m_list_index
    sta Vars::m_list, x
    inc Vars::m_list_index
@next:
    iny
    jmp @loop
@done:
    rts
.endproc

;; Loop over the list that is given to the right of the `|` symbol and check for
;; matches while updating `Vars::m_row` accordingly.
.proc check_given_list
    lda #0
    sta Vars::m_row
    sta Vars::m_row + 1

@loop:
    lda (Vars::m_address), y
    beq @done

    ;; If this is not a number, move into the next byte.
    sec
    sbc #48
    bcc @next
    cmp #10
    bcs @next

    ;; This is a number! Parse it and check if it matches into the list we have
    ;; of winning numbers.
    jsr parse_number
    sta Vars::m_num_1
    jsr check_with_winning

    ;; `parse_number` will leave `y` at the byte right after the last numeric
    ;; value. If this was the last number, then `y` is pointing to the `\0` byte
    ;; already. Let's check on that.
    lda (Vars::m_address), y
    beq @done
@next:
    iny
    jmp @loop
@done:
    rts
.endproc

;; Check the value on `Vars::m_num_1` with the list of winning numbers that we
;; have stored previously at `Vars::m_list`. If the number is a match, then
;; `Vars::m_row` will be updated accordingly.
.proc check_with_winning
    ldx #0
@loop:
    ;; Are we at the end of the list? If so just quit.
    cpx Vars::m_list_index
    beq @done

    ;; The core of the loop: grab an item on the list, compare it with the given
    ;; parameter. If it's a match let's compute it, otherwise let's move into
    ;; the next item and check again.
    lda Vars::m_list, x
    cmp Vars::m_num_1
    beq @won
    inx
    jmp @loop

@won:
    ;; There's a match! Now we need to shift left a `1` across a 16-bit number.
    lda Vars::m_row
    beq @set

    ;; The low byte is set, then just rotate it left and carry it into the high
    ;; byte if needed.
    clc
    rol Vars::m_row
    rol Vars::m_row + 1
    jmp @done
@set:
    ;; The low byte is not set. If the high byte is not set either, then we are
    ;; at the base case: we just need to set the low byte to 1 (@init).
    ;; Otherwise, if the high byte is set, it means that we need to shift the 1
    ;; located there one to the left. At this point, note that we assume that
    ;; there will be no overflows.
    lda Vars::m_row + 1
    beq @init
    asl Vars::m_row + 1
    jmp @done
@init:
    inc Vars::m_row
@done:
    rts
.endproc

;; Parse a number that is being pointed by `Vars::m_address` and the `y`
;; register. This subroutine assumes that the number will be maximum 2 digits
;; long, and it will change the `y` register to point to the byte exactly after
;; the last numeric digit. The evaluated number will be set into the `a`
;; register.
.proc parse_number
    ;; Initialize with a guard value.
    lda #$FF
    sta Vars::m_num_1
    sta Vars::m_num_2

@loop:
    ;; Load the given byte. If this is not a numerical value, just go to @done.
    lda (Vars::m_address), y
    sec
    sbc #48
    bcc @done
    cmp #10
    bcs @done

    ;; This is a numerical value! At this point we will set the number on
    ;; `Vars::m_num_{1, 2}` in order.
    ldx Vars::m_num_1
    cpx #$FF
    beq @first
    sta Vars::m_num_2
    iny
    jmp @done
@first:
    sta Vars::m_num_1
    iny
    jmp @loop

    ;; There are no more numerical digits, let's evaluate what we have parsed.
@done:
    ;; Let's check if we found two digits.
    lda Vars::m_num_2
    cmp #$FF
    beq @just_unit

    ;; If there are two digits, then `m_num_1` contains the tenth. Hence, we
    ;; have to multiply this number by 10 and then add the unit stored in
    ;; `m_num_2`.
    lda Vars::m_num_1
    asl
    sta Vars::m_num_3
    asl
    asl
    clc
    adc Vars::m_num_3
    clc
    adc Vars::m_num_2
    rts
@just_unit:
    ;; Only one digit, this is our value as is.
    lda Vars::m_num_1
    rts
.endproc

;; Non-Maskable Interrupts handler.
nmi:
    bit PPU::STATUS

    ;; Skip rendering if the `render` flag is not set.
    bit Globals::m_flags
    bpl @nmi_next

    ;; Backup registers.
    pha
    txa
    pha
    tya
    pha

    ;; If the result is not there yet, then we just print an initial message.
    ;; Otherwise print the given result.
    bit Globals::m_flags
    bvs :+
    jsr Print::show_wait_message
    jmp :++
:
    jsr Print::show_bcd_16_number
:

    ;; Reset the scroll.
    bit PPU::STATUS
    lda #$00
    sta PPU::SCROLL
    sta PPU::SCROLL

    ;; And unset the render flag so the `main` code is unblocked.
    UNSET_RENDER_FLAG

    ;; Restore registers.
    pla
    tay
    pla
    tax
    pla
@nmi_next:
    rti

;; Unused.
irq:
    rti

.segment "RODATA"
data:
    .asciiz "Card   1: 72 28 41 15 98 13 27 99 93 38 | 62  5 80 81 53 29 23 25 59 72 90 19 54 86 68 73 55 21 56 27 32 15 12 42 44"
    .asciiz "Card   2: 37 28 78 94 73 43 57 44 75 85 |  1 70 85 94 68 39 11 16 86 77 28 25 78 43 71 26 10 97 81 83 31 88 54 60 98"
    .asciiz "Card   3: 29 62 28 53 94 87 50 67  7 24 | 62 37 95 70 38  7 28 97 24 67 78 35 94 22 21 50 10 87 33 49 92 53 29 55  2"
    .asciiz "Card   4: 82 49 64 77 88 37 48 55 74 10 | 48  2 97 27 62 42 49 63 94 32 77 40  8 82 52 87 37 76 45 44 88 41 20 74  3"
    .asciiz "Card   5:  6 67 39 18 36 95 50 74 55 98 | 50 15 18 59 45 75 67 36  4 79 13 98 47 11 97 54 23 95 99 55 37 90  6 42 74"
    .asciiz "Card   6: 23 15 17 73 24 59 22 80 46 67 | 27 59 60 32 35 14 33 12 44 45 69 73  2 46  7 24 23 92 17 67 25 94 80 22 15"
    .asciiz "Card   7: 51 76  4 56 62 55 67 16 58 64 | 67 32 82 22 62 55 64 65 24  4 58 45 68 16 61 66 72 96 31 83 21 56 76 51 54"
    .asciiz "Card   8: 44 48 45 99 54 60 78 37 65  1 | 82 66 45 54 11 94 41  1 26 12 22 43 96 60  9 92 56 46 93 81 61 49 91  3 65"
    .asciiz "Card   9: 87 25 59 21 58 27 72  9 85 52 | 53  4 20 89 93 42 56 23 17  3 57 10 21  5 26 25 79 98 87 85 27  2 74 54 49"
    .asciiz "Card  10:  9 76 20 82 41 52 87 78 37 59 | 37 29 76 44 99 56 14 70  9 45 82 93  5 89 95 41 65 20 27 87 61 71 39 51 52"
    .asciiz "Card  11: 59 22 35  8 90 28 60 97 10 13 | 46 18 54 30 47 88 74 14 21 17 50 52 26 84 39 37 36 67 94 66 59 95 28 41 86"
    .asciiz "Card  12: 11 10 77 92 45 61 50 47 23 44 | 45 49 61 10 48 39 73 44 66 97 53 90 85 24 70 47  2 74 83 93 82 79 42 33 15"
    .asciiz "Card  13: 82 25 28 20 48 29 90 22 45 96 | 81 14 28 12 97 25 60 76  5 90 11 29 85  4 89 96 38 69 57 95 24 86 22 63 98"
    .asciiz "Card  14: 48 27  4 95 22 45 78 73 70 12 | 85 23 45 51 68 73 62 18 40 31 30 55 19 27 65 74 88 24 98 72 48 63 47 26 12"
    .asciiz "Card  15: 27 87 34 36 64 85 32 74 58 20 | 22 27 26  3  6 92 42 64 36 68 58 72 32 82 59 18 74 85 78 34 17 20 79 53 54"
    .asciiz "Card  16: 63 90 45  7 41  6 27 11 43 24 |  2  9 88 24 71 52 91  3 95  7 45 50 20 28 39 49 34 63 41 21  6 11 43 13 27"
    .asciiz "Card  17: 96 57 79 27 22 14 87 99 65 28 |  1 75 98 45  5  4 95 55 93 56 44 68 16 47 62 77 17 64 71  8 10 34  6  7 52"
    .asciiz "Card  18: 56 46 12 15 66 36 30 13 54  5 | 81 39 98 37  9 74 83 13 86 56 85 77 11 57 78 75 47 95 10 84 99  1  8  3 26"
    .asciiz "Card  19: 92 11 56  8 42 86 89 40 58  2 | 31 42 33 58 98 74 29 54 10 26 25 79  3 81 59 78 95 52 39 22  8 45 72 40 15"
    .asciiz "Card  20: 96  5 95 79 86 54 14 34 68 20 | 45 86 96 35 43 56 28 12  3 33 59 41 54 65 29 21 47  5 61 95 82 83 63 16 27"
    .asciiz "Card  21: 38 79 50 63 76 64 41 20 14 85 | 37  5 27 56 14 58 13 26 71 55 60 51 21 78 94 76 15 42 53 73 20 80 24 83  3"
    .asciiz "Card  22: 81 91 75 86 56 48 69 61 41 40 | 60 23 74 75  4 22 59 19 93 94 88  2 56 87 36 73 98 41 42 97 90  8 53 24 20"
    .asciiz "Card  23: 43 81 40 66 11 53 90 48  1  4 |  7 79 33 28 89 21 26  3 55 47 83 42 88 91 32 19 69 84 96 31 82 49 77 76 81"
    .asciiz "Card  24: 34 97 36 21  9 16 33  1 61 77 | 25 19 40 47 74 64 11 50 22 17  7 83 67 26 53 93 78 56 30 68 13  8 39 54 98"
    .asciiz "Card  25: 94 85 93 45 95 64  9 49 76  3 | 32 57 82 75 90 42 89 13 71 99 39  6 70 24 81 56 51 52 21 36 53 69 91 20 48"
    .asciiz "Card  26: 74 99  5 37 76 19 68 96 49 36 | 70 79 60 21  9 78 18 96  7 25 22  6 29 74 87 45 85 30 11 89 27 94 15 77 17"
    .asciiz "Card  27: 44  7 49 67 45 53 79 77 81 33 |  6 77 53 44 45 49  8  7 27 68 79 24  2 12 75 11 35 69 51 83 40 46 61 85 88"
    .asciiz "Card  28: 62 45 65 77 83 80 81 17 74 16 |  5 17 70 78 59 52 37 84 80 45  7 93 81 25 58 10 50 75 95 57  9 43 77 12 51"
    .asciiz "Card  29: 49  1 22 80 19 12  5 63 82 91 | 35 89 38 20 77 14 33 67 52 96 60 71 37 97 30 80  8 58 28 72 41  1 68 53 64"
    .asciiz "Card  30: 81 45 73 37 48 13 16 18 58 54 | 56 48 41 32 18 13 81 16 52 45  6 27 12 73 62  5 33 36 37 70 54 64  4 58 95"
    .asciiz "Card  31: 33 21 74 11 63 14 47 22 83  8 | 79 24 22 20 60 26 21  1 31 61 11 45 72 59 91 69 63 94 14 47  8 97 49  7 34"
    .asciiz "Card  32: 48 99 47 86 67 39 50 84 60 12 | 76 77 67 47 28  4 20 71 60  8 21 84 78 91 30 79 88  2 31 16 14 39 74 26 33"
    .asciiz "Card  33:  2 74 96 24 70 73 37  3 39 64 | 13 18 89 32 39 21 71 24 51 76  5 70 38 15 17  6 43 27  8 81 91 55 25 49 52"
    .asciiz "Card  34: 51 77  1 25 79 59  6 23 98 88 | 62 24 58 67 43 64 54 85 28 76 44 15 81 48 98 80 73 40 53 84  8 42 86 87 16"
    .asciiz "Card  35: 60 72 53 73 10 17 88  6 91  8 |  6 25 31 93 97 22 76 43 84 63 78 23 86 12 40 77 21 20 73 13 38 46 47 56 57"
    .asciiz "Card  36:  5 87 56 90 74 94  6 57 41 73 | 88 98 35 31 59 53 56 30 85 66 40 16 95 14 21 11 73 64 86 10  3 26 55 90 87"
    .asciiz "Card  37: 89 92 85 40 67 50 26 37 49 68 |  3 23 69 53 19 31 95 14 58 79 82 22 62 65 52 68 33 57  4 99 92 89 67 21 54"
    .asciiz "Card  38:  9 97 60  3 13 82 54 42 83 40 | 42 98 10 97 92 84 68 46 75  1 13 62 53 36 24 72 95 45 14 37  6 78 38 23 19"
    .asciiz "Card  39: 46 60 95 83 18 38 29 47 74 86 | 34 78 77 99 83 52 23 96 46 97 14 20 88 62 36 98 37 64 82 59 86 49 93 40 65"
    .asciiz "Card  40: 14 25 41 36 91 58 31 20 57  3 | 71 46 86 22 30 63 96 42 43 66 18 35  2 67 54 59  7 16 97 69  5 50 89  4 53"
    .asciiz "Card  41: 78 93 75 66 13 81 26 20 49 27 | 21 63 33 79 14 89 32 15 18  2 59 47 80 69 74 95 40 34 50 12 94 65 62 17 68"
    .asciiz "Card  42: 43 46 47 80 38 45 34  7 53 98 | 77 36 19 14  2 48 69 62 56 16 70 58 97 87 63 76 31 29 59 94 26 15 72 57  5"
    .asciiz "Card  43: 16 93 58 31  6 57 68 91 35 72 | 55 23 47 10 51 38 99 41 27 46 42 30  9  4 54 73  3 89 12 95 50 40 11 98 53"
    .asciiz "Card  44: 24 17 51 82 96 32 45 25 99 87 | 99 29 60 64 25 46 87 75  6 53 74  1 24 70 82 37 78 76 32  3 22  4 69 44 86"
    .asciiz "Card  45:  8 12  5 56  2 10 24 87 45 78 | 79 50 87 19 95 96 17 22 14 36 77 81 69 54 66 30 20 37  2 68 34  1 10 92 56"
    .asciiz "Card  46: 14 35 28 26 61 20 33 59 86 85 | 29 35 36 73  5  8 24 14 88 61 19  9 97 82 89 91 28 20 15 34 59 30 87 83 84"
    .asciiz "Card  47:  4  9 24 39 11 40 82 70 87  2 | 51 70 13 79 56 23 24 73 62 28 39 11  2 58 17  9 82 27 78 40 37 12  5 43 69"
    .asciiz "Card  48: 60 91 22 79 97 21 86 74 44 75 | 75 44 85 41  8 60 74 19 86 25 37 71 47 33 97 82 36 54 43 38 21 56 79 91 22"
    .asciiz "Card  49: 52 41 36  9 83 92 34 37 79 14 | 36 41 50 15 47 70 57 38 84 62 22 94 63 27 39  9 85 78 82 56 53 90 88 40 87"
    .asciiz "Card  50: 86 60 91  4 33 25 46 83 38 97 | 29 54 63 85 46 70 25  6  1 15 89 36 21 93 49 28 73 65 77 84 71 74 42 82 76"
    .asciiz "Card  51: 60 56 33 57 65 22 72 51 82 53 | 70 85 79 54 41 26 87 61 21  3 81 71 94 34 92 47 77 50 25 19  1 10 88 55 42"
    .asciiz "Card  52: 33 87 57  5 77  9 60 73 12 92 | 99 67 45 65 25  7  1 64 73 19 60 48 76 75 68 57 62 85 79 72 55 63 77 17 87"
    .asciiz "Card  53: 11 44 51 20 77 64 49 83 84 28 | 32 10 85 15 45 53 99 24 55 37  6 33 64 11 84 25 91 36 58 21  7 83 29 49 52"
    .asciiz "Card  54:  4 15 29 19 16 42 97 90  3  6 | 40 59 63 41 19 61 95 83 31 29 86 71 69 96 47  9 52 42 22 81 18 60 79 89  3"
    .asciiz "Card  55: 34 45 40 36 50 37 72  5 95 33 | 51 55 41  1 74  3 11 84 72 54 78  8 71 38 62 94 91 10 27 76 21 31 17 47 35"
    .asciiz "Card  56: 19 45 18 13  7 88 40 56 12 30 |  6 55 96 20 73 23 31 78 16 79 57 76 35 64 82 86 49 92 41 59 25 60 91 21 70"
    .asciiz "Card  57: 17 45 10 89 54 19 24 86 13 34 |  6 33 69 42 26 51 73 27 62 93 94 14 43 46 87 68  9 80  4 61 65  5 52 12 95"
    .asciiz "Card  58: 73 72 85 69 30 16 78 13 38 34 | 65 12 91 22  1 66  2 15 27 96 94 18 48 17 75 46 40 63 39 14 90 77 56  4 23"
    .asciiz "Card  59: 64 29 70 58 74 68 59 99 83 95 | 68 29 70 78 24 91 96 46 92 93 95 23 43 60  5 69 66  6 51 33 28 45 65 31 61"
    .asciiz "Card  60: 15 38  3 56 96 93 70 35 48 62 | 59  3 76 65 40 12 55 95 16 24 97  2 23 61 41 31 89 20 68 82 38 43 70 46 80"
    .asciiz "Card  61: 21 96 73 10 62 64 28 24 48 41 | 10 46 24 58 45 25 53  4 78 41 90 64 26 33 56 36 21 55 28 80 96 82 83 74 91"
    .asciiz "Card  62: 10 68 28 76 71 89 51 97 41 79 | 61  5 99  4 52 74 10 57 59 76 40 68 82 79 65 84 51 17 41 71 28 89 97  1 64"
    .asciiz "Card  63:  3 92  2 69 42 29 11 87 49 79 |  3 77  2 15 93 42 71 96 45 49 59 90  7 99 69 16  4 26 58 11 27 22 92 87 79"
    .asciiz "Card  64: 56 63 16 57 53 43 30 48 74 72 | 77 87 36 27 21 18 42 25 70 15 81 34  9 44 82 10 45 99  4 84 46 62 47 61 57"
    .asciiz "Card  65: 23 40 28 75 43 82 88 51 46 33 | 67 74 11 90 82 94 51 12 53 78  8 23 56 18 44 19 42 29 43 63 70 28 21 37  2"
    .asciiz "Card  66: 97 40 80 41 13 60 15 45 24 78 |  2 15 78 97 67 90 51 24 77  7 58 47 60 62 80 13 53 19 84 74 81 45 40 41 30"
    .asciiz "Card  67:  9 17 47 46 20  7 36 32 29 94 |  7 32 44 47 11 59 81  9 76 96 20 56 71 50 43 46 94 62 29 92 17 31 36 55 91"
    .asciiz "Card  68: 22 72 60 86 49  1 96 89 78 19 | 25 93  1 95 17 12 70  9 89 78 20 60 53 49 19 86 51 72 73 44 97 71 96 22 74"
    .asciiz "Card  69: 12 53 67 30 65 41 92 80 42  5 | 84 78 12 31 90 80 47 42 67 76 19 65 92  8  5 75 89 53 18 52 15 30 41 88 91"
    .asciiz "Card  70: 43 83 27 60 36 38 15 63 18 47 |  6 94 25 47 17  1  2 27  9 98 11 69 42 43 87 59 83  5 81 48 86 18 36 22 60"
    .asciiz "Card  71: 71 46 90  3 24 41 80  5  7  6 | 70 63 74 88 98 87 97 61 21 86 18  2 48 27 77 81 79 43 29 13 66 26 37  1 95"
    .asciiz "Card  72: 16  5 84 22 70  2 46 65 35 52 |  9 20 40 23 80 82  8  4 38 45  6 87 55 53 14  5 32 37 56 51 57 61 16 65 48"
    .asciiz "Card  73: 61 65 99 78 52  7 64 44 53  3 |  6 23 41 92 74 17 54 84 96 29 27 58 35 36 86 51  5 62 87 76  2  9 85 39 81"
    .asciiz "Card  74: 91 62 63 12 90 27 93 98 84 68 | 25 31 91 69 98 62 18 74 82 48 15 36  3 95 27 63 53 23 43  4 46 90 39 76 68"
    .asciiz "Card  75: 80 47 42 96 28 39 71 52 58 21 | 49 73  4 18 10 12 87 93 29  8 46 50 99 94 21 63  2 45 86 95 59 69 44 58 83"
    .asciiz "Card  76: 28 13 94 21 26 99 97 52 91 57 | 45 81  4 62 90  5 66 23 29 19 70 39 41 75 76 54 72 46 28 65 36 51 95 47 31"
    .asciiz "Card  77: 53 33 56 44 78 17 64 16 25 28 | 93 32 82 96 49 35 81 67 73 10 68 21 50 43 80 89 41 33 98 97 78  4 66 42 24"
    .asciiz "Card  78: 45 65 44 80 19  2 87 61 30 74 | 76 11 48 98 97 74 21 37 50 33 75 87 45  8 34 67 55 86 25 32 93 62 41 39  5"
    .asciiz "Card  79: 20 23 59 53 50 73 30 87 22 48 | 72 45 33 47 29 32 89 65 79 64  5 41 49 69  7 62  6 57 14  9 31 48 61 23 75"
    .asciiz "Card  80: 25 48  7 89 93 32 98 80 75 41 | 90  1 54 81 43 40 22 60 14 86 99 55  5 21 56 30 50 92 44 87 59 45 29 19 18"
    .asciiz "Card  81: 65 42 66 68 69 64 87 17 32 22 | 13 19  6 24 35 45 21 98 16 20 67  1 26 95 33 59 55 14 29 93 61 84 83 99 89"
    .asciiz "Card  82: 58  2 11 55 69 89 78 70 30 43 | 15 54 24 28 14  2  9 37 34 79 43 11 58 89 70 27 30 69 94 55 78 75 87 86 48"
    .asciiz "Card  83:  3 51 75 92 98 65  9 50 95 53 |  9 24 72 53  1 68 98 50 59 60 89 75  4 48 51 95  3 66 54 58 70 65 73 63 92"
    .asciiz "Card  84: 39 98 33 99 44 64 37 68 59 72 | 65 33 53 52  6 20 46 16 96 44 82  4 78 84 58 74 17 85 24 55 28 77 79 38 99"
    .asciiz "Card  85: 37 91 78 34 23 32 84 90 68 45 | 15 23 25  8 36 90 13 17  2 37 57 84 78 68 75 33 10  1  6 45 16 88 32 91 34"
    .asciiz "Card  86: 77 83 46 88 11 64 24 79 14  6 | 73 79 10 86 26 76 87 32 42 48 58 16 88  8 18 37 77 54 47 64 46 49 31  6 68"
    .asciiz "Card  87:  8 19 64 68 51 78 79 34 59 95 | 94 68 49  6 51 69 37 24 95 77 79 35  8 81 52 14 97 96 62 78  5 29  4 42 18"
    .asciiz "Card  88: 72 63 39 73 77 11 83 17 87 99 | 75 92 48 73 71 30 72 39 66 33 87 10 16 11 90 17 99 83 67 89 77 50 24 27 63"
    .asciiz "Card  89: 48 33 27 86 64 15 45  6 18 12 | 15 45  5 80 59 13 28 18 26 33 75 99 82 72 37  6 12 11 19 97 31 32 88  8 54"
    .asciiz "Card  90: 63 90 32 36 76 67 79 78 69 37 | 20 63 41 50 13 64 81 22 25 46 91 12  3 30  6  9 76 34 16 90 65  7 42 26 68"
    .asciiz "Card  91: 30 61 19 92 69 14 78 55 15 89 | 99  6 30 41 40 97 69 48 83 21 29  9 81 28  7 34 55 66 49 15 19 42 12 89 74"
    .asciiz "Card  92: 87 24 74 68 86 66 64 22 78 98 | 57 68  6 97 78  4 44 79 65 21 80 34 85 87 10 56 22 91 86 39 95 63 48 37 77"
    .asciiz "Card  93: 78 30 24 11 89 83 17 93 48 23 | 69 78 77 84 67 56 99 51 62 36 18 30 68 79 42 10 89 53 97 43 82 21 48 80 20"
    .asciiz "Card  94: 45 25 91 43 70 86 39 52 56 50 | 81 69  2 77 63 50 10 13 91 56 94 45 26 99 20 34 25 30  1 39 64 15  8 43 98"
    .asciiz "Card  95:  6 82 38 27 32 46 97  9 28 73 | 77 40  8 64  6 67 14  1 89 73 97  2 54 88 48 47 29 84 90 69 46 31 12 79 71"
    .asciiz "Card  96: 78 87  5 28 59 49 21 17  9 18 | 84 60 27 61 41  1 88 70 94 32 34 66 75 46 33 65 37 22 36 92 83 89 99 67 48"
    .asciiz "Card  97: 13 51  2 66 89  1 18 17  7 40 | 99 74 81 94 39 12  9 82 79 43 77 84 62 87 71 95 98 34 57 48 16 52 45 83 64"
    .asciiz "Card  98: 12 88  9 78 64 14  2 80  6 87 | 75 95 61 99 39 76 89 60 57  4 41 93 30 45 25 82  7 81 34 21 27 86 54 18 13"
    .asciiz "Card  99: 97 59 19 58 48 42 49 95 39 86 | 80 99  1 56  9 24 83 88 78 35  4 66 31 92 84 32 17 36 13 65 73  6 51 96 34"
    .asciiz "Card 100: 42 61 26 14 66 81 98 48 13 19 |  1 92 82 36  6 69 89 70 35 31 76 55 29 56 46 85 75 84 71 65 78  5 80 58 99"
    .asciiz "Card 101: 88 61 42 18 23 11 73 72 12  1 | 80 32 57 93 35 70 21 44 92 87 55 71 22 99 98 77 36 40 54 47 53 64 29 67 65"
    .asciiz "Card 102: 53 24 65 75 35 80 13 22 98 14 | 13 46  3 80 97 75 85 22 43  7 53 28 98  1 49 24 35 14 93  8 45 50 30 68 65"
    .asciiz "Card 103: 94 39 46 24 64 34 10 29 54  1 | 23 60 86 55 71 56  5 52  1 94 69 40 95 19 80 26 72 64  6 24  3 67 84 18 81"
    .asciiz "Card 104:  3 82 86 60 32 35 75 94 39 55 | 37 21 64 20 92 85 59 94  1 86 35 43 56 32 50 72 28  3 75  7 82 39  4 60 55"
    .asciiz "Card 105: 87 70 72 25  8 88  5 15 40 11 | 67  5 41 25 40 61 75 56 11 15 66 88 72 47 31 87 97 85 70 43  8 98 23 95 46"
    .asciiz "Card 106: 20 28 80 56 54 63 96  8 16 95 | 56 74 32 36 92 78 96 79  2 76  6 62 24 87  8 93  3  4 59 54 80 77 95 58 28"
    .asciiz "Card 107: 64 75 22 29 30 63 98 28  5 95 | 38 68 96 79 90 30  3  5 91 31 34 66 83 16 46 75 35  7 48  6  8 18 10 54 20"
    .asciiz "Card 108: 34 95  1 70 37 38 74 60  8 23 | 30 84 35 16 66 67 31 20 13 53 98 14 56 80 47 73 96 86 87 44 85 93 49 43 55"
    .asciiz "Card 109: 59  3 78 98  6 51 44 72 90 47 | 19 15 90 37 52 39 51 29 66 74 47  4 85  6 27 75 82  5 32 55 77 21 78 72 88"
    .asciiz "Card 110:  4 97 60 52 22 43 14 42 31 30 | 19  6 96 37 42 86 81 72 48 45 92  7 97 13 78 63 17 35 59 38 64 99  4 98  1"
    .asciiz "Card 111: 45  9 43 76 40 56 22 27 77 71 | 75 37 51  1 92 65 59 40 58 39 29 91 70 83 54 86 74 97 42 50 73  4 61 23 57"
    .asciiz "Card 112: 97 64 16 37  6 70 35 18 10 14 | 41 88 95 57 34 90  2 69  9 30 11 78 92 60 86 80 89 37 65 68 58  8 72 13 74"
    .asciiz "Card 113: 46 98 31 39 63 64 58 33  5 36 | 81 91 29 20 52 61 77 82 98 96 97 19 72 67 32 45  1 22 40  3 27 89 71  7 37"
    .asciiz "Card 114: 89 40 82 24 39 45 74 17 15 47 | 78 21 79  3 68 56 52 30 40 97 71 67 90 34 16 32 55 42 85  6 45 41 84 13 35"
    .asciiz "Card 115: 25 67 21 27 93 84 40 16  8 57 | 74 77 24 14 39 97 78 73 52 19 31 10 23 76 58 38 11 42 34 63 45 27 17 64 41"
    .asciiz "Card 116: 46 27 38 53 18 29 95 40 96 58 | 66 97 13  3 87 25 41 24 98 49 69 45  5 94 59  7  6 36 32 10 17 31 42 84 75"
    .asciiz "Card 117: 87 43 58 55 92 45 94 24 67 25 | 37 73 36 13 86 63 14 69 88 87 40 95 70  4 90 84 89 96 39 60 54 50 17 61 66"
    .asciiz "Card 118: 40 11 89 16 10 45 51 90 64 18 | 50 61 64 83  9 90 11 10 44 97 30 60 32 14 40 51 45 18 16 29 99 79 36 24 89"
    .asciiz "Card 119: 27 78 72 35  5 20 53 40 49 77 | 38 14 20 56 78 69 88 35 92 77 70 34 95  2 74 72 29 91 99 96 49 18  5 27 52"
    .asciiz "Card 120: 51 25 23  8  7 89 21 56 82 41 | 79 47  2 41 50 39 86 51 61 17 21 28 85  7 25 68 89 19 87 23 40  8 56 11 82"
    .asciiz "Card 121: 35 45 14 58 40 83  4 28 69 92 | 22 64 50 55 78 36 66 74 42 12 23 70 11 49  5 15 48 21 79 53 87 72 76 68 82"
    .asciiz "Card 122: 86  5 49 22 93 54 78  4 23 10 | 92 29 80 22 55  5 13  6 87 78  4 20 25 81 86 19 54 23 93 96 94 10 16 49 38"
    .asciiz "Card 123: 12 58 15  7 79 86 33 39 78 28 | 25 94  1 81 39 78 61 93 86 45 19 60 83  2 15 33 28 58  7 51 82 67 12 79 52"
    .asciiz "Card 124: 64 81 69 71 37 66 20 33  2 24 | 10  2 90 74 33 81 87 37 36 69 49 71  6 68 21 66 64 44 24 88 43 29 20 94 47"
    .asciiz "Card 125: 13 62 34 47 51 49 97 41 32 40 |  2 54 97 79 14 35 40 51 75 91 76 10 72 57 78 49 60 98  9 13 28 65 70 25 50"
    .asciiz "Card 126: 69 26 74  4 70  3 34 65 48 16 | 47 20 52 36 66 59 77 41  6 51 15 19 28 72 14 35 39 10 55 40 45 33 42 90 79"
    .asciiz "Card 127: 13 84 29 23 70 77 89 75 83 51 | 79  5 85 25 91 75 64 57 83 89 73 69 39 56  6 70 13 33 32 84 60 68 23 77 29"
    .asciiz "Card 128: 92 48 56  8 69 72 43 11 17 98 | 48 17  8 72 23 93 82 68 36 15  6 56 43 69 92 73 11 98 75  2 49 74  1 20 29"
    .asciiz "Card 129: 86 55 77 27 48 50  3 12 23 97 | 38 84 71  5  8 70 99 78 96 90 69 34 93 40 36  6 59 74 81 15 83 52 94 82 18"
    .asciiz "Card 130: 36 61 95 38 65 76 84 24 58 51 | 92 82 38 73 16 67 87 84 34 58 63 54 65 99 61 93  8 13 21 66 24  3 31 64 62"
    .asciiz "Card 131: 93 27 24 39 25  6 47 86 45 95 | 25 99 69 35 51  9 24 60 46 28 64 95 74 36 30 44  8 12 18 42 52 27 22 39 43"
    .asciiz "Card 132:  5 33 58 17 92 51 99 49 28 82 | 94 33 58 11 81 63 82 39 48  3 53  5 31 47 77 10 17 61 51 80 92 45 85 59 49"
    .asciiz "Card 133: 11 82 92 35 33 94 70 53 98  5 | 52 12 50 41 86 66 36 76 25 72 10 81 71 63 96 60 83 55 61 48 14 85 16 97 28"
    .asciiz "Card 134: 31 13 39 66 47 40 11 34 41 29 |  9 80 66 47 76 44 41 71 35 93 45 67 34 39 52 21 29 31 53 23 30 57 63 65 20"
    .asciiz "Card 135:  8 19 59 77 25 62 84 67 86 39 | 32 60 18  6 30 22 20 47 28 46 72 91 52 71 83 35 49 66 11 80 14 90 16 87 44"
    .asciiz "Card 136: 59 29 20 44 26 15 54 51 76 83 | 94 26 46 92 12 38 37 75 84 48 22 55 34 43 79  3 16 70 64 80 68 58 13  8 28"
    .asciiz "Card 137: 45 30 32 91 57 61 43 93  5 94 | 34 16 59 72 66 58 77 80 54 84 44 25 55 49 48 23 69 14 85 51  6 42 13 41 20"
    .asciiz "Card 138: 44 94  8 27 58 67 10 53 59 25 |  9 44 11 13 49 23 72 41 94 64 25 95 74 85 43 37 32 69 96 18 17 98 56 29 45"
    .asciiz "Card 139: 38 49  5 91 53 27 17 44 96 32 | 71 97  3 84 48 90 88 35 14 70 94 62 40 87 86 53 43 15 21 83 16 28 79 33 72"
    .asciiz "Card 140: 15 47  6 40 21 45 23 69  3 20 | 72 65 96 71 19 87 42 86 62 77  8 97 57 33 22 95 55 74 73 12 79 27 60 90 18"
    .asciiz "Card 141: 92 18 65 62 38 34 48 57 67 20 | 41  4  8 10 40 29 88  6 59 89 24 98 26 70  3 23 61 25 64  1 82 52 46 16 30"
    .asciiz "Card 142: 76 43 72 60 88 34 65 74 84 10 | 60 58  5 84 20 10 77 74 65 23 38 24 34 44 33 83 88 41 43 76 35 50 28 13 72"
    .asciiz "Card 143: 91 51 38 29 88 10 90 96 70 49 | 38 59 90 20 29  7 35 13 51 88 14 86 47 91 80 28 12 49 96 70 43 10 65 37  5"
    .asciiz "Card 144: 51 89 31 27 50 44 17 59 24 16 | 74 27 77 89 44 53 52 31 14  6 16 51 17  2 59 69 83 57  4 15 79 75 13 78 26"
    .asciiz "Card 145: 23 40 50 80 79 56 84 81 82  1 | 34 85 79 10 75 11 48 47  3 24 91 50 60 62 51 98 63 15 17 82 69 52  6 54 21"
    .asciiz "Card 146: 80 16 41 55 53 64 10 96 33 65 | 71 27 64 77 18 55 66 41 78 96 24 80 33 11 65 88 13 57 99 10 30 31 84 20 53"
    .asciiz "Card 147: 55 15 61 46 86  2 45 17  5 32 | 10 75  8 20 69  7  4 34 72 13 92 28 78 17 48 27 55 15 90 11 66 61 46 86 21"
    .asciiz "Card 148: 52 90 71 33 34 88 75 63 99 76 | 71 31 99 74 32 34 52 63 59 87 42 88 90 75  5 38 12 13  3 96 76 25 49 33 56"
    .asciiz "Card 149: 65 98 39 11 57  7 80 95 12 53 |  7 47 72 65 57 11 80 29 53 94 28 41 19  3 50 55 23 95 66 43 39 21 45 12 91"
    .asciiz "Card 150: 47 43  6 94 78 81 91  9 97 56 | 99 18 68 94 49 39 40 79 64 37 56  7 85 32 80  6 23  9 38 52 92 81 67 91 97"
    .asciiz "Card 151: 79 62 61 82 73 78 83 74 12 51 | 26  6 73 63 83 49 25 61 87 40 96 74 38  2 62 18 78 91 90 82 84 12 51 79  3"
    .asciiz "Card 152: 93  7  5 39 52 70 95 27 26 41 | 91 79 26  7 41 70 52 67 93 71 95 10 39 15 27 54  5 62 74  9 88 73 80 38 97"
    .asciiz "Card 153: 95 42 37 86 44 21 59 93 63  6 | 96 45 58 16 98 17 69 97  7 18 72 71 86 38 22 33 28 13 56 50 41 78 57 48 24"
    .asciiz "Card 154: 91 55 94 22 90 18 56 81 45 43 | 80 84 47 23 26 70  8 14 15 66 22  2 12 40 44 85 93 58 39  3 17 71 68 65 52"
    .asciiz "Card 155: 65 15 24 75 10 50 96 86 69 11 |  7 43 21 57 82 16 53 90 39 84 60 49 91 79 66 94 25 54  5 93 97 70  1 30 28"
    .asciiz "Card 156: 83 43 19 68 70 71 65 89 26 66 | 34 67 60 87 97 22 96 33 62 99  5 71 37 35 58  1 86 14 55 21 82 91 44 17 24"
    .asciiz "Card 157: 67 50  3 60 34 39 84 18 31 58 | 60 27 82 61 94 75 30 45 72 85 10 48 76 34 79 32 17 18 67 35 70 38 93 29 12"
    .asciiz "Card 158: 35 33 92 31 34 58 94 60 95  6 | 31 69 97 92 98 85 53 81 87 84 58 28  4 93 22 44 35 55 27 13 95 41 88 89 36"
    .asciiz "Card 159: 10 65 42 20 67 84 32  6  7 86 | 56  4 97 50  9 12 53 10 39 84 43 77 61 68 32 91 36 87 22 15 60  7 11 24 49"
    .asciiz "Card 160: 54 48 50 52  7 51 24 58 31 85 | 45 81 28 56 88 20 43 76 36  4 25 99 30 18 98 49 71 95 60 35 91 70 51 33 55"
    .asciiz "Card 161: 20 97 89 66 48 23 14 46 80 57 | 83 74 19 13 87 28  5 94 35 81 56 58 65 55 45 90 39 29 14 12 22 59 57 95 67"
    .asciiz "Card 162: 95 26 51 56 83 41 19 66 79 25 | 84 95 37 71 18 27 87 33  3 16 51 47 66 86 49 48 55  7 28 50 20 43 75  9 85"
    .asciiz "Card 163: 79 24 49 72 70 61 18 84 68 86 | 88  3 73 69 21 83 76 51  1 47 45 43 82 33 14 15 16 93 22  7 31 50 19 94 99"
    .asciiz "Card 164: 81 80 24 59 30 55 73 94  7 70 | 89 72 62 43 58 14 47 71 41 92  5 36 46  3 96 33 30 18 63 64 12 44 86  9 76"
    .asciiz "Card 165: 10 83  1 18  5 82 81 29 67 92 | 65 17 74 88  3 11 54 80  4 42  8 91 99 59  6 58 62 30 96 63  2 41 90 43 38"
    .asciiz "Card 166: 59 36 88 19 99 93 81 53 62 30 | 12 88 36 85  4 22 55 96 68 63 83 15 14 40 93 81 97  9 75  6 94  5 44 31 23"
    .asciiz "Card 167: 34 22 98 78 19 30  6 88 53 41 |  7 26 47 84 22 30 99 73 93 98 90 89  6 54 18 72 74 41 69  9 39 44 32 59 70"
    .asciiz "Card 168: 32 31 53 65 64 85 36 19 95 12 | 82 60 69 84 55 76 30 83 14 81 35 57 59  4 72 40 15 97 47 92 11 39 50  8 38"
    .asciiz "Card 169: 58 66 14 82 42 97 86 64 40 57 | 58 64 87 97 89 85 91 66 77 53 86 50 26 13  3 45 14 33 40 11 17 82 99 49 24"
    .asciiz "Card 170: 43 68 96 70 98 14 63 53 29 67 | 17 10 29 46 78 75 38 41 50 37  5 92 74 26 83  1 33 71 67 88 87 44 25 60 95"
    .asciiz "Card 171: 85 86 81 15 67 50 52 92 72 30 | 23 52  3 12 57 35 83 84 54 97 43 18  1  8 86  6 67 92 51 93 15 91 55 47  7"
    .asciiz "Card 172: 25 15 48 85 17 51 36 27 88 18 | 37 23 48 55 16 42 20 64 95 75 78 28 98 74 68 97 58 45 26 14 57 46  3 90 62"
    .asciiz "Card 173: 85 61 27 99 65 24 43 13 33 71 | 44 23 32 84 80 65 68 18 72 69 99 55 13 33 89 62 24 43 59  7 19 83 85 79 56"
    .asciiz "Card 174: 28 24 96 72 92 30 10 55 87  2 | 53 96 75 62 44 33  5 79 50 23 55 87 26 47 13 28 41 39 52 42 14  7 16 71 86"
    .asciiz "Card 175: 27 55 99 66 20 68 24 98 82 56 | 87 62 85 15  2 52 50 11 37 93 90 98 57 33  6 20 96 71 66 73 68 80 86 92 39"
    .asciiz "Card 176: 47  1 83 14 21 66 73 87 95 63 | 77 14 94 80 61 88 52 86 24  8  5 69 42 12 78 79 30 60 76 46 55 34 65  9 51"
    .asciiz "Card 177: 98 74 54 15 83 86 64 35 91 19 |  7 64 65 49 18 84 24 12  9 43 86 96 33 15  5 47 13 92 35 70 69 61 40 68 82"
    .asciiz "Card 178: 74 82 22  4 77 79 99 39 11 72 | 90 64 27 44 53 15 19 55 75 43 78 88 93 17 38 41 25 18 20 63  6 82 67 91 24"
    .asciiz "Card 179: 73 67 27 18 86 17 35  2 56 51 | 14 12 75 49 31 52  9 57 43 25 82 32 59 56 40 67 74 24 10 46 66  6 58 13 39"
    .asciiz "Card 180: 71  9 76 19 38  1 23 63 45 89 | 14 20 83 65 88 50  3 16 47 77 48 59 55 98 97  8 53 39 82 73 62 11  4 28 56"
    .asciiz "Card 181:  8 79 95 19 56 64 51 10 92 66 | 29 33 57 77  9 98 90 76 42 89 52 94 47 15 70 78 80 32 71 75 14 93 11 16  4"
    .asciiz "Card 182: 41 13 46 42 45 61 40 70 21 80 | 84 21 69 80 29 25 13 43 45 70 57 99 41 39 50 42 40 46 11 66 61 20 74 75 26"
    .asciiz "Card 183: 78 12  3 97 22 21 53 83 82 75 | 33 21  3 36 42 60 10 56 40 87 88 69 97 65 50 83 12 78 53 22 61 75 25 92 82"
    .asciiz "Card 184: 47  1 26 10 90 17 22  7 49 16 | 10  5 16 53 40 81  1  7 76 26  9 74 49 44 59 56 47 14 82 30 17 22 65 90 15"
    .asciiz "Card 185: 63  5 84 69 73 44 94 86 75 79 | 17 22 98 88 50 93 96 87 38 54 81  6 83 64 99 48 18 82 52 11  4 33 72 37 60"
    .asciiz "Card 186: 37 74 76  3 68 97 55 59 42 23 | 67 47 82 55 53  3 68 13 44 60 62 37 42 63 75 61 93 87 76 51 59 97 84 74 99"
    .asciiz "Card 187: 25 62 26 41 91 55 89 58 90 50 | 43  5 32 26 91 62 89 41 87 94 48 60 58 16 44 24 90 28 11 10 66 50 85 55 25"
    .asciiz "Card 188: 82 46 29 70 17 49 31 71 61 42 | 80  3  7 66 87 71 82 21 99 67 29 96  5 31 13 17 69 47 32 42 46 92 70 22 49"
    .asciiz "Card 189: 68 86 63  6 56 55 53 87 18  4 |  9 74 53 90 20 73 26 86 76 79 91 63 92 50  6  4 68 35 56 48 21 46 44 62 80"
    .asciiz "Card 190: 85 16 79 27 67 93 66 90 14 15 | 27 84 99 16 40 55 97 95 89 38 28 46 88 13 63 60 96 92 30  6  2 64 43 69 10"
    .asciiz "Card 191: 61 69 58 10 63 29 92 70 57 65 | 88 79 86 89 75 52 92 70 25 26 73 71 29 10 93 57  7 58 51 84  8 67 21 85  5"
    .asciiz "Card 192: 57 33  7 82 64 81 61 23 58 12 | 80 58 81 82 75 50 92 33 20 95 61 53 56 40 19 62 13 79 57 73 60 18 54 85  8"
    .asciiz "Card 193:  3 19 86 33 83 58 27 68 53 96 | 72 33 51 93  1 81 25 68 85 37 73 63 27  4 65 60  6 79 17 43 36 41  3 67 28"
    .asciiz "Card 194: 54 33 59 27  9 25 69 80 48 37 | 37 86 38 79 44 48 57 84  5 73 20  4 31 85  2 25 19 33 61 32 89 91 76 72 45"
    .asciiz "Card 195: 63 23 43 87 14 85 82 46 19 54 | 91 19 79 59 56 67  6 20 70 26 37 63 53 32 42 18 46 17 35 94 69 84 96 72 13"
    .asciiz "Card 196: 11 86 29 39 65 76 95 40 26 98 | 51 88 69 75 46 79 37 14 48 43 41 70 64 58 55 95  6 26 60 80 17 85  8 57 38"
    .asciiz "Card 197: 94 22 97  6 26 74 51 90  9 45 | 72 63 80 58 59 64 81 96 24 91 69 82 29 86 47 35 76 27  4 38 36 42 67 62 93"
    .asciiz "Card 198: 76 46  7 94 90  2 95 25 29 26 | 17 13 62 43 24  4 56 30  5 20 65 40 10 45 91 15  9 93 73 53 42 68 75 55 51"
    .byte $ED
