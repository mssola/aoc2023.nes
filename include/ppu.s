.segment "CODE"

.scope PPU
    CONTROL = $2000
    MASK    = $2001
    STATUS  = $2002
    SCROLL  = $2005
    ADDRESS = $2006
    DATA    = $2007
.endscope

.macro PPU_ADDR address
    lda #.HIBYTE(address)
    sta PPU::ADDRESS
    lda #.LOBYTE(address)
    sta PPU::ADDRESS
.endmacro

;; WRITE_PPU_DATA is a macro that will write into PPU::ADDRESS the given address
;; and into PPU::DATA the given byte value.
.macro WRITE_PPU_DATA address, value
    bit PPU::STATUS

    PPU_ADDR address
    lda #value
    sta PPU::DATA
.endmacro
