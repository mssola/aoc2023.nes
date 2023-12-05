.scope Print
    ;; Print a "Please wait..." message to the screen. This message will be centered
    ;; horizontally and slightly at the top of the screen. This function assumes
    ;; that alphanumerical tiles are located in a similar fashion as for the
    ;; `assets/alphanum.chr` file.
    .proc show_wait_message
        WRITE_PPU_DATA $2129, $2A
        WRITE_PPU_DATA $212A, $26
        WRITE_PPU_DATA $212B, $1F
        WRITE_PPU_DATA $212C, $1B
        WRITE_PPU_DATA $212D, $2D
        WRITE_PPU_DATA $212E, $1F

        WRITE_PPU_DATA $2130, $31
        WRITE_PPU_DATA $2131, $1B
        WRITE_PPU_DATA $2132, $23
        WRITE_PPU_DATA $2133, $2E
        WRITE_PPU_DATA $2134, $36
        WRITE_PPU_DATA $2135, $36
        WRITE_PPU_DATA $2136, $36

        rts
    .endproc

    ;; TODO
    .proc show_bcd_16_number
        ;; Clear tiles that were written by `show_wait_message` and that are not re-used
        ;; here.
        WRITE_PPU_DATA $2129, $00
        WRITE_PPU_DATA $212A, $00
        WRITE_PPU_DATA $212B, $00
        WRITE_PPU_DATA $212C, $00
        WRITE_PPU_DATA $212D, $00
        WRITE_PPU_DATA $2133, $00
        WRITE_PPU_DATA $2134, $00
        WRITE_PPU_DATA $2135, $00
        WRITE_PPU_DATA $2136, $00

        ;; And loop so PPU::ADDRESS $2E21-$2E32 has the data as stored on bcdResult,
        ;; which is the binary to decimal conversion result when the final
        ;; computation was done.
        ldx #4
        ldy #$2E
    @loop:
        ;; PPU address.
        bit PPU::STATUS
        lda #$21
        sta PPU::ADDRESS
        sty PPU::ADDRESS

        ;; PPU data.
        lda bcdResult, x
        clc
        adc #$10
        sta PPU::DATA
        dex
        iny
        cpy #$33
        bne @loop

        rts
    .endproc

    ;; Copies basic palettes into the proper PPU address.
    .proc load_basic_palettes
        PPU_ADDR $3F00

        ldx #0
        @load_palettes_loop:
        lda palettes, x
        sta PPU::DATA
        inx
        cpx #$20
        bne @load_palettes_loop
        rts
    palettes:
        ;; Background (only first one used)
        .byte $0F, $30, $10, $00
        .byte $0F, $00, $00, $00
        .byte $0F, $00, $00, $00
        .byte $0F, $00, $00, $00

        ;; Foreground (unused)
        .byte $0F, $00, $00, $00
        .byte $0F, $00, $00, $00
        .byte $0F, $00, $00, $00
        .byte $0F, $00, $00, $00
    .endproc
.endscope
