;;;
;; Day 2 https://adventofcode.com/2023/day/2
;;
;; The enunciate has two parts and this program gives an answer to both parts
;; in a single iteration.
;;
;;  - Part 1: the answer will be printed on screen and the value is stored in
;;            RAM address: $00-$01 (`Vars::m_sum` in the code).
;;  - Part 2: the answer is bigger than what a 16-bit number can hold. For this
;;            reason I am not printing it on screen and instead you will have to
;;            inspect the 32-bit number stored in RAM address: $0B-$0E
;;            (`Vars::m_sum_2` in the code).

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

;; "Variables" used by this program.
.scope Vars
    ;; Maximum number for each color according to Part 1.
    RED = 12
    GREEN = 13
    BLUE = 14

    ;; The answer on part 1 will be accumulated on this address on each
    ;; iteration.
    ;;
    ;; NOTE: 16-bit ($00-$01).
    m_sum = $00

    ;; Single byte temporary values. Named like this because they are mostly
    ;; used on converting a three-sized string into a numerical value.
    m_num_1 = $02
    m_num_2 = $03
    m_num_3 = $04

    ;; The address where the current data row is located. This address will be
    ;; incremented on each loop iteration so it always points to the first item
    ;; of the needed row.
    ;;
    ;; NOTE: this is a full address and, therefore, is 16-bit. Because of this
    ;; this is actually stored at $05-$06.
    m_address = $05

    ;; The ID of the current game being evaluated. This is actually not needed,
    ;; but it's done this way for readability purposes.
    m_game_id = $07

    ;; This is a three-sized array that stores the maximum value that has been
    ;; seen on each color on the current iteration (sorted by "rgb").
    ;;
    ;; NOTE: memory addresses being used: $08 (red), $09 (green), $0A (blue).
    m_rgb_max = $08

    ;; The answer on part 2 will be accumulated on this address on each
    ;; iteration.
    ;;
    ;; NOTE: 32-bit ($0B-$0E). Note that 24-bit is enough, but tools like FCEUX
    ;; go from 16-bit digits to 32-bit directly. Since we have a lot of spare
    ;; memory, we don't care.
    m_sum_2 = $0B

    ;; Initialize some of the variables.
    .proc init
        lda #0
        sta m_sum
        sta m_sum + 1
        sta m_sum_2
        sta m_sum_2 + 1
        sta m_sum_2 + 2
        sta m_sum_2 + 3

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
    ;;   - 0 (`possible`): whether the last evaluated combination is
    ;;                     possible or not.
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
    jsr compute_next
    jmp @loop
.endproc

;; Compute the next game if needed.
.proc compute_next
    ;; Skip everything if the `done` flag is set.
    bit Globals::m_flags
    bvs @end

    jsr compute_row

    ;; `compute_row` will actually move `y` to the end of the string. At this
    ;; point, advance one byte more and we are at the start of the next one.
    ;; With this, move the base address here since we don't want the poor 8-bit
    ;; `y` register to overflow over time.
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
    lda Vars::m_sum + 1
    sta bcdNum
    lda Vars::m_sum
    sta bcdNum + 1
    jsr bcdConvert

    ;; Because of the previous, we can set the `render` flag again.
    SET_RENDER_FLAG
@end:
    rts
.endproc

;; Compute a given row (game). This will move the `y` register to the end of the
;; string so the caller can take advantage of it.
.proc compute_row
    ;; Set the `possible` flag to true always. This will be set to false if it's
    ;; found to be impossible.
    lda #%00000001
    ora Globals::m_flags
    sta Globals::m_flags

    ;; Initialize the `Vars::m_rgb_max` array by giving each color a maximum of
    ;; exactly 1. Note that in all games each color always appears at least
    ;; once.
    lda #1
    sta Vars::m_rgb_max
    sta Vars::m_rgb_max + 1
    sta Vars::m_rgb_max + 2

    ;; NOTE: the following is actually not needed, but I find it more "formal"
    ;; to actually parse the game ID than just increase a given number. That is,
    ;; in the input all games are given sequentally. Thus, one could just
    ;; increase a value on each iteration and assume that as the game ID.

    ;; The format is "Game X: <whatever>". Thus, before the game ID there is
    ;; always a space. Loop until we find it.
    ldy #$FF
@wait_until_space:
    iny
    lda (Vars::m_address), y
    cmp #32
    bne @wait_until_space
    iny

    ;; Now we are guaranteed to point to the game ID. Parse the number and store
    ;; it. It will be used at the end.
    jsr parse_number
    sta Vars::m_game_id

    ;; This is the main evaluation loop.
@loop:
    ;; Load the current byte. If this is a zero byte, then we are at the end of
    ;; the string and we can go to the `@done` section. Otherwise, we should
    ;; loop until we find a space character, because before the number for each
    ;; color we are guaranteed to have a space character.
    lda (Vars::m_address), y
    beq @done
    iny
    cmp #32
    bne @loop

    ;; We can now parse the number we have ahead, and we will store it into
    ;; `Vars::m_num_1`, which will act as a temporary value.
    jsr parse_number
    sta Vars::m_num_1

    ;; `parse_number` will leave `y` to the character just after the last
    ;; numerical digit. We are guaranteed to have this format `<number><1
    ;; space><color identifier>`. Thus, we just need to increase `y` once to get
    ;; into the first byte of the color identifier.
    ;;
    ;; Whenever we do this, we will compare the caracter with 'r', 'g', 'b' and
    ;; jump to each color accordingly. Each color will do the same:
    ;;
    ;;   1. Set 'x' to the color index on the `Vars::m_rgb_max` array so it can
    ;;      be picked by the `set_max` function. This will set the maximum value
    ;;      by comparing whatever we have on this array and the value we have
    ;;      stored on `Vars::m_num_1` (stored when we parsed the number).
    ;;   2. According to Part 1, we have to check whether the combination was
    ;;      possible. Thus, we need to compare the number we found for the color
    ;;      with the maximum that is allowed for it. If the value is lesser than
    ;;      what we have, then we go back at the beginning of the loop.
    ;;      Otherwise we do a final check on `@check_equal`.
    iny
    lda (Vars::m_address), y
    cmp #114
    beq @red
    cmp #103
    beq @green

    ;; Blue
    ldx #2
    jsr set_max
    lda Vars::m_num_1
    cmp #Vars::BLUE
    bcs @check_equal
    jmp @loop
@red:
    ldx #0
    jsr set_max
    lda Vars::m_num_1
    cmp #Vars::RED
    bcs @check_equal
    jmp @loop
@green:
    ldx #1
    jsr set_max
    lda Vars::m_num_1
    cmp #Vars::GREEN
    bcs @check_equal
    jmp @loop

    ;; We are coming from evaluating a color and realizing that the value is not
    ;; strictly lesser than what we expected.
@check_equal:
    ;; Was it just equal? If so, we are on the safe side and we can go into the
    ;; next iteration of the loop.
    beq @loop

    ;; No, the number is simply larger than what we expected! At this point set
    ;; the `possible` flag to 0, so to mark that this game is actually
    ;; impossible according to the enunciate of Part 1. After this, just go into
    ;; the next iteration of the loop, since Part 2 requires us to check every
    ;; single value of the game (before part 2 was unveiled, at this point we
    ;; returned earlier).
    lda #%11111110
    and Globals::m_flags
    sta Globals::m_flags
    jmp @loop

    ;; The loop is done, let's evaluate what we have found.
@done:
    ;; Regardless of whether the combination was possible according to Part 1,
    ;; we still have to sum up the "powers" according to Part 2. Let's do this
    ;; now.
    jsr add_powers

    ;; Was the game marked as not possible at any point of the loop. If that is
    ;; the case, we don't have to do anything more and we return early.
    lda Globals::m_flags
    and #%00000001
    beq @done_for_good

    ;; The game was possible. Thus, according to Part 1 of the enunciate, we add
    ;; the game ID to the 16-bit number that we are accumulating over for this.
    lda Vars::m_game_id
    clc
    adc Vars::m_sum + 1
    sta Vars::m_sum + 1
    lda #0
    adc Vars::m_sum
    sta Vars::m_sum
@done_for_good:
    rts
.endproc

;; Parse the number that is currently pointed by `Vars::m_address` plus `y`. The
;; evaluated number will be returned into the `a` register.
.proc parse_number
    ;; Initialize with a guard value.
    lda #$FF
    sta Vars::m_num_1
    sta Vars::m_num_2
    sta Vars::m_num_3

@loop:
    ;; Load the given byte. If this is not a numerical value, just go to @done.
    lda (Vars::m_address), y
    sec
    sbc #48
    bcc @done
    cmp #10
    bcs @done

    ;; This is a numerical value! At this point we will set the number on
    ;; `Vars::m_num_{1, 2, 3}` in order.
    ldx Vars::m_num_1
    cpx #$FF
    beq @first
    ldx Vars::m_num_2
    cpx #$FF
    beq @second
    sta Vars::m_num_3
    iny
    jmp @done
@first:
    sta Vars::m_num_1
    iny
    jmp @loop
@second:
    sta Vars::m_num_2
    iny
    jmp @loop

    ;; There are no more numerical digits, let's evaluate what we have parsed.
@done:
    ;; If we actually found three digits, we are guaranteed to have a value of
    ;; exactly `100`. Let's set that and leave early.
    lda Vars::m_num_3
    cmp #$FF
    beq @check_tenth
    lda #100
    rts
@check_tenth:
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

;; Set the maximum value from the given parameters into the `m_rgb_max` array on
;; the given index. The value to be compared is expected to be stored at
;; `m_num_1`, and `x` is expected to be initialized as the index from the
;; `m_rgb_max` array to be used for both comparison and set.
.proc set_max
    lda Vars::m_rgb_max, x
    cmp Vars::m_num_1
    bcs @done
    lda Vars::m_num_1
    sta Vars::m_rgb_max, x
@done:
    rts
.endproc

;; Multiply the values on `m_rgb_max` and add the resulting value into
;; `m_sum_2`. Note that `m_num_1` and `m_num_2` will change as a side-effect.
.proc add_powers
    ;; Initialize `m_num_1` and `m_num_2`, used as auxiliary values here.
    lda #0
    sta Vars::m_num_1
    sta Vars::m_num_2

    ;; Multiplying the values on `m_rgb_max` on a system with no `mul`
    ;; instructions or anything like that is as simple as adding the same value
    ;; N times. On this first loop, we will add the value on 'red' as many times
    ;; as 'green'. The resulting value will be stored at `m_num_1` plus
    ;; `m_num_2` on overflows (thus having a 16-bit result).
    ldx Vars::m_rgb_max + 1
@loop1:
    lda Vars::m_rgb_max
    clc
    adc Vars::m_num_1
    sta Vars::m_num_1
    lda #0
    adc Vars::m_num_2
    sta Vars::m_num_2
    dex
    bne @loop1

    ;; On the next loop we will multiply on factors of the previous result,
    ;; which is a 16-bit value. We will temporarily store them into the `red`
    ;; and `green` positions since we will need `m_num_1` and `m_num_2` again
    ;; for multiplying a 16-bit integer.
    lda Vars::m_num_1
    sta Vars::m_rgb_max
    lda Vars::m_num_2
    sta Vars::m_rgb_max + 1

    ;; Now we are selecting `blue`, which is the color we have not touched yet.
    ldx Vars::m_rgb_max + 2
    dex
    ;; NOTE: if `blue` was simply '1', we are done. Note that we could not do
    ;; this on the previous loop because of how initialization on the 16-bit
    ;; integer had to happen.
    beq @done
@loop2:
    lda Vars::m_rgb_max
    clc
    adc Vars::m_num_1
    sta Vars::m_num_1
    lda Vars::m_rgb_max + 1
    adc Vars::m_num_2
    sta Vars::m_num_2
    dex
    bne @loop2

@done:
    ;; At this point we are done: store each computed value into the proper
    ;; memory addresses and that's it. Note that +3 and +2 positions are our
    ;; actual value, while +1 is only meaningful for adding the carry (we expect
    ;; the end result the be just a bit above the 16-bit limit). For this same
    ;; reason we can guarantee that the most significant byte on this 32-bit
    ;; number will always be zero, so we set it directly accordingly.
    lda Vars::m_num_1
    clc
    adc Vars::m_sum_2 + 3
    sta Vars::m_sum_2 + 3

    lda Vars::m_num_2
    adc Vars::m_sum_2 + 2
    sta Vars::m_sum_2 + 2

    lda #0
    adc Vars::m_sum_2 + 1
    sta Vars::m_sum_2 + 1

    lda #0
    sta Vars::m_sum_2

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
    .asciiz "Game 1: 19 blue, 12 red; 19 blue, 2 green, 1 red; 13 red, 11 blue"
    .asciiz "Game 2: 1 green, 1 blue, 1 red; 11 red, 3 blue; 1 blue, 18 red; 9 red, 1 green; 2 blue, 11 red, 1 green; 1 green, 2 blue, 10 red"
    .asciiz "Game 3: 3 blue, 2 red, 6 green; 4 blue, 6 green, 1 red; 11 green, 12 blue; 2 red, 6 green, 4 blue; 4 green"
    .asciiz "Game 4: 10 red, 5 green, 5 blue; 3 red, 3 blue, 6 green; 2 blue, 9 red, 6 green; 8 green, 10 red, 4 blue; 9 red, 2 green, 3 blue; 1 blue, 5 red, 15 green"
    .asciiz "Game 5: 11 green, 7 blue; 5 green, 5 red, 1 blue; 1 green, 1 red, 4 blue; 1 red, 1 blue, 4 green; 4 blue, 1 red, 10 green; 5 red, 6 green"
    .asciiz "Game 6: 1 green, 1 red, 11 blue; 1 blue, 2 green; 1 red, 5 green, 9 blue; 7 blue; 1 red, 2 green, 9 blue; 12 blue, 1 red, 2 green"
    .asciiz "Game 7: 1 blue, 10 red, 7 green; 14 blue, 10 green; 12 red, 2 green; 16 red, 13 blue, 1 green; 12 green, 10 red, 3 blue; 9 red, 19 blue, 11 green"
    .asciiz "Game 8: 3 blue, 1 green, 3 red; 4 blue, 10 red, 6 green; 1 green, 10 red, 9 blue; 9 blue, 7 red, 8 green; 8 green, 12 red, 8 blue; 6 blue, 1 green, 13 red"
    .asciiz "Game 9: 10 green, 2 blue, 11 red; 2 green, 2 red; 6 blue, 8 red, 13 green"
    .asciiz "Game 10: 8 red, 3 blue, 5 green; 5 green, 7 blue, 1 red; 3 red, 10 blue, 6 green; 2 red, 6 green, 7 blue; 3 blue, 11 red, 4 green; 8 red, 8 blue, 4 green"
    .asciiz "Game 11: 14 green, 9 red; 3 blue, 6 green, 8 red; 14 green"
    .asciiz "Game 12: 10 red, 5 blue, 1 green; 4 blue, 8 red; 5 blue, 1 green, 6 red; 14 red, 4 blue; 1 green, 11 red, 3 blue"
    .asciiz "Game 13: 1 blue, 16 green, 1 red; 6 red, 2 blue, 5 green; 2 blue, 12 red, 10 green; 3 red, 4 blue, 13 green; 14 red, 4 blue, 12 green; 7 red, 2 green"
    .asciiz "Game 14: 17 red, 11 blue, 3 green; 16 red, 3 blue, 8 green; 3 green, 9 red, 13 blue; 4 green, 15 red, 14 blue"
    .asciiz "Game 15: 7 blue, 2 red, 2 green; 1 green, 5 red, 6 blue; 3 green, 6 red, 2 blue"
    .asciiz "Game 16: 3 red, 3 green; 6 green, 4 red, 3 blue; 3 red, 4 blue; 4 blue, 2 red, 4 green"
    .asciiz "Game 17: 6 red, 1 blue, 5 green; 3 red, 1 green, 12 blue; 13 green, 1 blue; 5 blue, 7 green, 6 red; 5 blue, 14 green, 2 red; 4 green, 6 red, 10 blue"
    .asciiz "Game 18: 4 red, 8 blue; 8 blue, 4 red; 12 blue, 1 green"
    .asciiz "Game 19: 1 blue, 15 green, 9 red; 1 red, 3 green; 4 blue, 2 green, 1 red"
    .asciiz "Game 20: 7 blue, 4 green, 12 red; 1 red, 9 green, 8 blue; 4 blue, 2 green; 13 green, 8 blue; 3 red, 4 green, 1 blue; 6 green, 7 red, 3 blue"
    .asciiz "Game 21: 9 green, 4 blue, 8 red; 5 blue; 7 red, 8 blue, 1 green"
    .asciiz "Game 22: 3 green, 4 red; 6 red, 3 green; 4 red, 1 blue, 1 green; 11 red, 3 green, 1 blue; 7 red, 1 blue"
    .asciiz "Game 23: 3 blue, 4 green; 3 green, 1 red; 1 red, 2 blue, 4 green"
    .asciiz "Game 24: 2 blue, 3 green; 9 red, 4 green; 2 blue, 9 red; 2 green, 10 red, 1 blue; 1 blue, 1 red, 5 green"
    .asciiz "Game 25: 8 green, 4 blue; 9 blue, 7 red; 5 green, 15 blue, 11 red; 11 green, 14 red, 10 blue"
    .asciiz "Game 26: 3 blue; 2 red, 1 green; 2 red, 3 blue; 10 blue, 1 red, 3 green; 1 green, 2 red; 1 green, 6 blue"
    .asciiz "Game 27: 1 green, 6 blue; 2 green, 1 red, 6 blue; 1 red, 2 blue, 1 green"
    .asciiz "Game 28: 8 blue, 1 red, 5 green; 1 red; 3 green, 4 red, 2 blue; 4 green, 2 red, 4 blue; 5 blue, 3 red, 7 green"
    .asciiz "Game 29: 2 green, 4 blue; 7 blue, 4 red, 10 green; 7 blue, 9 green; 14 green, 7 red, 5 blue"
    .asciiz "Game 30: 19 green, 3 red; 19 green; 1 blue, 14 green; 2 blue, 5 green; 3 red, 19 green"
    .asciiz "Game 31: 3 red, 1 green, 4 blue; 10 blue; 3 red, 4 green, 5 blue; 10 blue, 1 red, 6 green"
    .asciiz "Game 32: 19 red, 1 green, 2 blue; 1 blue, 6 green, 13 red; 10 green, 9 red; 11 red, 2 blue, 6 green; 8 green, 5 red"
    .asciiz "Game 33: 2 red, 8 blue, 2 green; 1 red, 3 green; 9 red, 9 blue, 1 green; 6 red, 1 green; 9 blue, 1 green, 8 red; 5 green, 10 red, 8 blue"
    .asciiz "Game 34: 1 red, 6 blue, 2 green; 7 red; 14 red, 13 blue; 13 red, 12 blue; 1 green, 9 red, 13 blue; 2 green, 15 blue"
    .asciiz "Game 35: 8 blue, 2 red, 3 green; 2 green, 2 red; 3 red, 6 blue, 2 green; 2 green, 6 blue; 1 green, 5 blue, 4 red; 3 green, 6 blue"
    .asciiz "Game 36: 3 red, 5 blue, 10 green; 1 red, 1 green, 7 blue; 2 blue, 2 green, 1 red"
    .asciiz "Game 37: 8 red, 7 green; 5 green, 1 blue, 6 red; 7 red, 6 blue, 11 green"
    .asciiz "Game 38: 4 green, 10 red, 9 blue; 12 green, 2 blue, 2 red; 6 red, 6 blue, 9 green; 1 blue, 1 green, 6 red; 3 blue, 1 red, 5 green; 5 blue, 2 red, 12 green"
    .asciiz "Game 39: 1 blue, 2 red; 7 blue, 2 green, 1 red; 7 blue, 11 green, 3 red; 8 blue, 13 green, 1 red; 6 green, 6 blue, 3 red"
    .asciiz "Game 40: 8 green, 5 blue; 5 green, 1 blue, 10 red; 9 green, 3 blue; 3 green, 7 red; 2 green, 3 blue, 5 red"
    .asciiz "Game 41: 7 green, 8 red; 3 blue, 15 green, 7 red; 2 red, 2 green, 4 blue; 10 green, 4 red, 5 blue; 3 red, 8 blue, 9 green; 7 red, 8 green"
    .asciiz "Game 42: 6 blue, 12 green; 3 red, 1 green; 1 red, 12 green, 3 blue; 10 red, 9 green; 9 red, 4 green, 5 blue"
    .asciiz "Game 43: 11 red, 6 green; 2 blue, 11 red; 3 red, 1 blue; 3 green, 11 red, 2 blue; 4 red, 5 green, 1 blue; 8 green, 2 blue, 17 red"
    .asciiz "Game 44: 2 green, 9 blue, 3 red; 7 blue, 1 green, 4 red; 1 green"
    .asciiz "Game 45: 1 green, 10 red; 5 red, 10 green, 1 blue; 11 red, 3 green, 2 blue; 2 blue, 3 green, 4 red; 7 green, 3 red, 2 blue; 1 blue, 10 red"
    .asciiz "Game 46: 1 green, 4 blue, 7 red; 13 blue, 2 green, 9 red; 7 blue, 3 red, 1 green"
    .asciiz "Game 47: 4 blue; 2 green, 2 red, 1 blue; 1 green, 1 red, 4 blue; 1 green, 2 red, 2 blue; 2 blue, 2 red"
    .asciiz "Game 48: 5 green, 10 red; 7 red, 5 green; 1 green, 11 red; 12 red, 11 green; 11 red, 1 blue, 1 green"
    .asciiz "Game 49: 2 green, 1 red, 1 blue; 1 blue, 2 red; 2 green, 1 red, 2 blue; 1 blue, 1 red, 1 green"
    .asciiz "Game 50: 5 green, 2 blue; 4 green, 4 blue, 3 red; 1 red, 7 green, 3 blue"
    .asciiz "Game 51: 9 green, 1 red, 2 blue; 7 red, 3 blue, 6 green; 5 green, 4 blue, 5 red"
    .asciiz "Game 52: 2 green, 4 blue, 1 red; 2 blue, 2 red, 13 green; 8 blue, 3 green; 3 green, 4 blue, 2 red; 2 green"
    .asciiz "Game 53: 3 red; 4 blue, 4 red; 2 blue, 2 red; 6 blue, 1 red, 2 green; 1 red, 1 green, 6 blue; 2 blue, 4 red"
    .asciiz "Game 54: 3 blue, 3 green, 18 red; 4 blue, 18 red, 3 green; 7 blue, 4 green"
    .asciiz "Game 55: 1 green, 2 red, 3 blue; 1 red, 4 blue, 1 green; 3 blue, 2 red; 2 blue, 1 green; 3 blue, 2 red; 1 blue, 1 green, 1 red"
    .asciiz "Game 56: 12 green, 2 red, 1 blue; 11 green, 16 red, 13 blue; 7 red, 5 blue, 12 green; 4 blue, 16 red; 5 red, 1 blue, 3 green"
    .asciiz "Game 57: 5 green, 17 blue, 11 red; 6 blue, 1 green; 1 green, 5 blue, 8 red; 9 green, 11 red, 1 blue; 9 green, 11 blue, 7 red; 8 green, 4 blue"
    .asciiz "Game 58: 5 red, 10 blue, 6 green; 5 green, 11 blue, 5 red; 9 green; 4 red, 2 green"
    .asciiz "Game 59: 2 red, 6 blue, 1 green; 1 green, 12 blue; 2 red"
    .asciiz "Game 60: 6 blue, 10 green, 9 red; 8 red, 19 blue, 2 green; 16 red, 10 green, 12 blue; 13 red, 12 blue, 6 green"
    .asciiz "Game 61: 12 green, 1 red, 3 blue; 3 red, 4 blue, 19 green; 1 blue, 7 green"
    .asciiz "Game 62: 7 red, 6 blue, 8 green; 10 blue, 3 green, 17 red; 13 blue, 3 red, 10 green; 13 red, 5 blue, 9 green; 12 blue, 4 red; 10 red, 4 green"
    .asciiz "Game 63: 19 green, 4 red; 5 blue, 4 red, 1 green; 4 red, 2 blue, 15 green; 5 green, 4 red, 5 blue"
    .asciiz "Game 64: 6 red, 3 green; 6 green, 3 red, 3 blue; 3 blue, 8 red, 5 green; 3 blue, 7 red, 1 green; 1 blue, 6 red, 6 green"
    .asciiz "Game 65: 1 green, 9 blue; 6 blue, 4 green, 6 red; 6 blue, 5 green; 3 red, 1 blue, 4 green"
    .asciiz "Game 66: 1 blue, 2 red; 2 green, 1 blue; 2 red, 1 blue, 1 green; 1 blue, 1 green"
    .asciiz "Game 67: 16 blue, 1 green; 1 blue, 2 green, 2 red; 1 red, 9 blue; 12 blue, 4 green, 1 red; 6 green, 11 blue, 3 red"
    .asciiz "Game 68: 6 blue, 2 red, 1 green; 2 blue, 2 green; 1 green, 7 red, 15 blue; 14 blue, 12 green, 3 red; 13 green, 10 red, 6 blue; 2 green, 5 blue, 1 red"
    .asciiz "Game 69: 2 red, 1 blue, 2 green; 1 blue, 7 green, 1 red; 3 blue, 1 red, 7 green; 2 red, 1 blue, 11 green"
    .asciiz "Game 70: 2 green, 9 red, 3 blue; 12 blue, 1 green, 13 red; 6 red, 1 green, 5 blue; 1 red, 17 blue"
    .asciiz "Game 71: 7 red, 5 green, 6 blue; 5 blue, 5 green; 7 green, 4 blue; 2 green, 4 blue, 8 red; 10 red, 8 green; 3 blue, 13 red, 7 green"
    .asciiz "Game 72: 13 red, 17 green; 9 red, 20 green, 3 blue; 1 green, 3 blue, 8 red"
    .asciiz "Game 73: 1 blue, 7 red, 2 green; 2 green, 1 blue, 8 red; 1 blue, 2 red; 4 red, 7 green; 4 red, 5 green; 3 green, 7 red"
    .asciiz "Game 74: 2 green, 14 blue; 1 red, 1 blue, 7 green; 1 red, 8 green, 11 blue; 4 green, 12 blue; 1 green, 5 blue"
    .asciiz "Game 75: 12 blue, 1 red; 1 red, 7 blue, 4 green; 4 blue, 6 green; 4 green, 3 blue, 1 red"
    .asciiz "Game 76: 7 green, 5 red, 6 blue; 18 red, 1 green; 14 green, 4 red, 15 blue; 4 blue, 6 red"
    .asciiz "Game 77: 2 blue, 2 green, 2 red; 2 blue, 1 red, 1 green; 2 green, 1 red; 6 blue, 4 green; 1 red, 1 blue, 6 green"
    .asciiz "Game 78: 5 red, 16 blue, 12 green; 11 blue, 3 red, 2 green; 13 blue, 4 red"
    .asciiz "Game 79: 9 red, 11 green, 6 blue; 1 red, 3 green; 7 blue, 7 red, 11 green; 8 red, 9 blue, 11 green; 7 red, 11 green, 4 blue"
    .asciiz "Game 80: 7 green, 5 red, 2 blue; 1 blue, 7 green, 1 red; 2 red, 2 blue; 1 red, 4 blue, 12 green; 4 green, 2 blue"
    .asciiz "Game 81: 5 blue, 2 green, 12 red; 2 green, 1 blue, 5 red; 3 blue, 13 red, 3 green; 3 green, 9 blue, 3 red; 10 blue, 4 red, 3 green"
    .asciiz "Game 82: 11 blue, 1 red, 9 green; 11 green, 1 blue, 12 red; 13 red, 6 blue, 19 green"
    .asciiz "Game 83: 6 red, 5 blue, 16 green; 4 green, 17 blue, 9 red; 15 red, 2 green, 9 blue"
    .asciiz "Game 84: 19 green, 11 blue, 3 red; 1 blue, 18 green, 6 red; 17 blue, 5 green, 4 red; 18 blue, 7 green, 3 red"
    .asciiz "Game 85: 3 green, 15 blue; 12 blue; 2 green, 1 red; 1 red, 9 blue, 1 green; 12 blue, 3 red, 1 green"
    .asciiz "Game 86: 3 green, 4 blue, 5 red; 9 red, 4 green, 1 blue; 6 green, 1 blue, 8 red; 3 green, 2 blue, 5 red"
    .asciiz "Game 87: 2 red, 8 blue, 5 green; 3 red, 5 blue, 10 green; 2 red, 3 green"
    .asciiz "Game 88: 16 green, 13 red; 7 green, 1 blue, 2 red; 7 red, 12 green; 5 red, 7 green, 2 blue; 2 blue, 10 green, 7 red; 8 red, 16 green"
    .asciiz "Game 89: 1 blue, 8 red; 2 green, 10 red, 12 blue; 13 green, 14 blue; 10 blue, 15 red, 13 green; 2 green, 5 red, 13 blue"
    .asciiz "Game 90: 16 blue, 7 red, 4 green; 4 green, 6 red, 11 blue; 2 red, 8 blue, 2 green; 5 green, 8 red, 10 blue; 4 red, 2 green, 7 blue; 4 green, 5 blue, 5 red"
    .asciiz "Game 91: 4 red, 4 green, 1 blue; 3 blue, 2 green; 6 blue, 4 green, 5 red; 2 red, 6 blue, 4 green; 6 blue, 1 green"
    .asciiz "Game 92: 1 red, 3 green; 3 blue, 6 green; 5 blue, 1 red, 11 green; 1 red; 3 green, 13 blue"
    .asciiz "Game 93: 1 red, 14 blue, 6 green; 10 blue, 6 red; 9 green, 15 red, 17 blue; 9 red, 1 green, 9 blue"
    .asciiz "Game 94: 3 red, 14 green; 3 blue, 15 green, 3 red; 2 red, 15 green"
    .asciiz "Game 95: 4 blue, 13 red; 5 blue, 1 green, 11 red; 3 green, 3 blue, 10 red; 13 red, 6 blue; 2 green, 5 blue; 3 green, 11 red"
    .asciiz "Game 96: 7 blue, 1 green; 1 green, 4 blue; 1 green, 2 red, 5 blue; 1 red, 2 blue, 1 green; 1 blue"
    .asciiz "Game 97: 15 green, 9 blue; 14 blue, 14 red, 2 green; 18 red, 12 blue, 2 green"
    .asciiz "Game 98: 1 green, 9 red; 1 red, 2 green, 7 blue; 8 red, 1 blue; 6 red, 2 green; 1 green, 6 blue"
    .asciiz "Game 99: 1 green, 2 red, 6 blue; 6 red, 1 green, 5 blue; 11 blue, 6 red; 11 red, 1 green; 1 green, 11 red, 9 blue"
    .asciiz "Game 100: 12 green, 8 blue, 2 red; 7 blue, 14 red, 8 green; 14 red, 1 blue, 4 green"
    .byte $ED
