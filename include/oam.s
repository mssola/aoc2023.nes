.segment "CODE"

.scope OAM
    ADDR = $2003
    DMA  = $4014
.endscope

.macro OAM_WRITE_SPRITES
    lda #$00
    sta OAM::ADDR
    lda #$02
    sta OAM::DMA
.endmacro
