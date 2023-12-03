.scope Globals
    ;;;
    ;; Temporary values.

    m_tmp_1  = $00
    m_tmp_2  = $01
    m_tmp_3  = $02
    m_tmp_4  = $03
    m_tmp_5  = $04

    ;; Bit map to be used as flags during execution.
    m_flags = $20

    ;; Initialize global variables.
    .proc init
        lda #0
        sta m_tmp_1
        sta m_tmp_2
        sta m_tmp_3
        sta m_tmp_4
        sta m_tmp_5
        sta m_flags
        rts
    .endproc
.endscope

;; SET_RENDER_FLAG sets the render bit on Globals::m_flags to 1.
.macro SET_RENDER_FLAG
  lda #%10000000
  ora Globals::m_flags
  sta Globals::m_flags
.endmacro

;; UNSET_RENDER_FLAG sets the render bit on Globals::m_flags to 0.
.macro UNSET_RENDER_FLAG
  lda #%01111111
  and Globals::m_flags
  sta Globals::m_flags
.endmacro
