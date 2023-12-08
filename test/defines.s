RUN_TESTS = 0

.macro CALL_TESTS_ON_DONE
    .ifdef RUN_TESTS
        bit Globals::m_flags
        bvc :+
    @test:
        nop
    :
    .endif
.endmacro
