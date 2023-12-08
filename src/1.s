;;;
;; Day 1 https://adventofcode.com/2023/day/1
;;
;; This program iterates over the array on `data` and computes the value on each
;; row, then accumulating it into a sum variable. The end result will be printed
;; to the screen, which must be `54953`.

;; Luckily for us, good ol' NROM can fit the data set for this exercise :D
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
    ;; After each iteration, this will hold the tenth of the number that has
    ;; been computed.
    m_tenth = $00

    ;; After each iteration, this will hold the unit of the number that has been
    ;; computed.
    m_unit = $01

    ;; The address where the current data row is located. This address will be
    ;; incremented on each loop iteration so it always points to the first item
    ;; of the needed row.
    ;;
    ;; NOTE: this is a full address and, therefore, is 16-bit. Because of this
    ;; this is actually stored at $03-$04.
    m_address = $03

    ;; Used for temporary computations.
    m_tmp = $05

    ;; $08-$09 is a 16-bit number that accumulates the value being computed by
    ;; this program.
    m_sum = $08

    ;; Zeroes out all variables and sets the base address for the data on
    ;; `m_address`.
    .proc init
        lda #0
        sta Vars::m_tenth
        sta Vars::m_unit
        sta Vars::m_tmp
        sta Vars::m_sum
        sta Vars::m_sum + 1

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
    jsr init_palettes
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
    CALL_TESTS_ON_DONE
@halt:
    jmp @halt
.endproc

;; Iterate over the row pointed by `m_address` and compute its value. The tenth
;; of the number will be stored into `m_tenth` and the unit on `m_unit`.
.proc compute
    ;; $FF is the safeguard value, which simply means "not set yet". See code
    ;; below.
    ldy #$FF
    sty Vars::m_tenth
    sty Vars::m_unit
@loop:
    ;; `m_address` has the base address for the current row and `y` is the index
    ;; on it. Thus, the byte for this iteration is located by loading the base
    ;; address plus the index. Each row is guaranteed to end with a zero value.
    ;; Hence, if the load instruction sets the zero flag, then it means that we
    ;; are done.
    iny
    lda (Vars::m_address), y
    bne @do
    rts
@do:
    ;; The data is stored in plain ASCII. Thus, a numeric value must be between
    ;; 48 to 57 exactly. The value is therefore computed by subtracting 48 and
    ;; ensuring the it holds a value of 0-9 when doing so. If this is not the
    ;; case, then we can go into the next iteration.
    sec
    sbc #48
    bcc @loop
    cmp #10
    bcs @loop

    ;; Hey, this is actually a numeric value! Now check if `m_tenth` had already
    ;; been set by a previous iteration (see $FF as a safeguard at the start of
    ;; this function). If this is not the case, then we need to set this value
    ;; as both the unit and the tenth (if only one number is seen on a row, then
    ;; it has to be computed as both the unit and the tenth according to the
    ;; enunciate). Otherwise, if the tenth had already been set, then just set
    ;; the unit.
    ldx Vars::m_tenth
    cpx #$FF
    bne @unit
    sta Vars::m_tenth
@unit:
    sta Vars::m_unit
    jmp @loop
.endproc

;; Compute the value from the row pointed by the address on `m_address`. After
;; that, accumulate this value into `m_sum` and finally move the `m_address`
;; address to the next row. This function will also set the `done` flag whenever
;; we reach the $ED control byte.
.proc compute_next
    ;; Call `compute` and `accumulate_number`, which work in tandem in order to
    ;; fetch the value for the current row and add it into the `m_sum`
    ;; accumulator.
    jsr compute
    jsr accumulate_number

    ;; The `compute` routine has set `y` to the amount of bytes that were
    ;; traversed for the current row. Hence, if we want to move into the next
    ;; row, just increase this value by one and add it to the 16-bit address on
    ;; `m_address`. During the next iteration, `m_address` will already point to
    ;; the first byte from the next row after this.
    iny
    tya
    clc
    adc Vars::m_address
    sta Vars::m_address
    lda #0
    adc Vars::m_address + 1
    sta Vars::m_address + 1

    ;; Speaking of which: after computing our new 16-bit address, did we get a
    ;; value of `$ED` which signals the end of input? If so, then set the `done`
    ;; flag, so next iterations won't get into any of this logic.
    ldy #0
    lda (Vars::m_address), y
    cmp #$ED
    bne @end

    lda #%01000000
    ora Globals::m_flags
    sta Globals::m_flags

    ;; Now that we are done, convert the 16-bit number into separate bytes so it
    ;; can be rendered on NMI-code.
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

;; Assuming that `m_tenth` contains the current tenth of the number to be added
;; and `m_unit` the unit, assemble this number and add it to the `m_sum`
;; accumulator.
.proc accumulate_number
    ;; First of all multiply the value on `m_tenth` by 10 (done by adding
    ;; m_tenth*2 + m_tenth*8).
    lda Vars::m_tenth
    asl
    sta Vars::m_tmp
    asl
    asl
    clc
    adc Vars::m_tmp

    ;; And now just add this value with the units on `m_unit`. After this `a`
    ;; holds the value to be accumulated.
    clc
    adc Vars::m_unit

    ;; Finally, add the computed value into the 16-bit sum value.
    clc
    adc Vars::m_sum + 1
    sta Vars::m_sum + 1
    lda #0
    adc Vars::m_sum
    sta Vars::m_sum

    rts
.endproc

;; init_palettes copies all the palettes into the proper PPU address.
.proc init_palettes
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
    .asciiz "9cbncbxclbvkmfzdnldc"
    .asciiz "jjn1drdffhs"
    .asciiz "3six7"
    .asciiz "38rgtnqqxtc"
    .asciiz "rxszdkkv3j8kjhbm"
    .asciiz "54nzzddht8ninelrkkseightseven6"
    .asciiz "6fourmnvkgnthjtnjqkr"
    .asciiz "nineninezsstmkone4sjnlbldcrj4eight"
    .asciiz "3rdnfkvrx4twoqgeightqkgmn"
    .asciiz "6mlhponeglrzrvbsseven"
    .asciiz "five8spgxz8"
    .asciiz "3three2dfourfour58"
    .asciiz "9q"
    .asciiz "two45"
    .asciiz "five8mpkpdfiveeightfourseven"
    .asciiz "93threefive3three92"
    .asciiz "6jdzeightnineone1sclhzrnrjxfive"
    .asciiz "6nseven16lbztpbbzthree8five"
    .asciiz "eight6mntljvbfrmftsffchsix4"
    .asciiz "4twosixvnhjl"
    .asciiz "8d"
    .asciiz "eightsevenvqvzlqxkbm6rqhsgqpnine7twonex"
    .asciiz "seven96"
    .asciiz "ck8tv6"
    .asciiz "2mcddqpnbxssmrc6"
    .asciiz "zsfbkrjjqpbbone6six2"
    .asciiz "fourone8hfrkxrr"
    .asciiz "7ninetphdpcx"
    .asciiz "9gcn9six4mfnjgtcdc"
    .asciiz "6onevsevenseven4three"
    .asciiz "ldssggpknine7"
    .asciiz "twolltbfkhltwo892jngx"
    .asciiz "rsh1five3ninefourmfk"
    .asciiz "xtrh534nqxr"
    .asciiz "ggllvfjthreefcckbninekspmf6bnpkvt2"
    .asciiz "kng16"
    .asciiz "kqgthcleightsixeight96nine69"
    .asciiz "nchcdqbsxmeighttwo65onevtqrznxmnl"
    .asciiz "chphzzqb6threeqhspbgkrn6"
    .asciiz "8threevbqxl4"
    .asciiz "99eight2hgdvcqdqxsnmkxctskvxxvqxjt"
    .asciiz "9qb95oneightsf"
    .asciiz "tfmpcthbdbnzhldnbj96"
    .asciiz "9mzbn"
    .asciiz "twoseven9rmssixbvbjpsbjbh3two"
    .asciiz "7fcmfjjrtz5six4"
    .asciiz "hpspsgtfxvxtmdsqcninelcjhfb2mhffpvxkdxdlvkqxnine"
    .asciiz "fivexrhxhtfivesevenone3d"
    .asciiz "jvc6twofourbgfgrthree9fourmhz"
    .asciiz "8xfvjdqlgfrlhzds4"
    .asciiz "5271ninexfthree"
    .asciiz "fbm1jd3onenine"
    .asciiz "2jm7fchdklthreedzfg"
    .asciiz "6lgrrzfkj"
    .asciiz "eight6sixthree"
    .asciiz "eightsixzng8dxxnfbqdjkjt1two"
    .asciiz "fivesix92j"
    .asciiz "1kfrjjq"
    .asciiz "tjjthblvjfspbcshfivesix5fivesixf"
    .asciiz "nrlx5vqzcfive"
    .asciiz "doneightthtpmjlzhgpxdc18229twofive"
    .asciiz "6shtlqlbsxnine7snthree"
    .asciiz "oneonengtbjmlq4"
    .asciiz "sixhxvzpshrhbbk3qdxrbq"
    .asciiz "23onezbvbrlnseven239"
    .asciiz "one883mztbhfvqqq3srfptz"
    .asciiz "zxlglzxgkltc8four6kzmqf5eightstzlqcvxt"
    .asciiz "3four452jclt"
    .asciiz "sixmone3phrxxdninetwosix"
    .asciiz "3nine39"
    .asciiz "578nine4"
    .asciiz "442ffhxfrxb"
    .asciiz "shnnn3nqcgfbgpzzfrtchbseven5dk3"
    .asciiz "ninenine5xrxrhcr"
    .asciiz "ninefourdlckvqzz6oneseven"
    .asciiz "fivetwoqcnqhbs9"
    .asciiz "2sevenbgp8one"
    .asciiz "twohqbp7fnndbjpn"
    .asciiz "2nctn1pbbxmns"
    .asciiz "46fourhjppdlkr"
    .asciiz "cbfour3seven7dctlone"
    .asciiz "sevenjxbbplfour488trzv"
    .asciiz "5qqfb9twooneonethree"
    .asciiz "7zzlgxrfmlpxrbbnjt7five5mxhd4"
    .asciiz "99vdnnzcdsqxgbonefoursevenjjjgc1"
    .asciiz "4threeeighttkqdxnkrgblvnine5"
    .asciiz "sevendtlm5onetwo"
    .asciiz "threeonejvxqb15nnjndprnn5cdxb9"
    .asciiz "hkr1mtcmqqqsixxbfjnlqqlb"
    .asciiz "six2five3jkknzf5"
    .asciiz "9xgkspdhrfivesix15zj"
    .asciiz "nsztwo4jxfzxbtrsjjnj8"
    .asciiz "1twofive2sixqxxrjpgbdfive"
    .asciiz "41sixgmgxzdseveneightmnmxj3"
    .asciiz "8qrvxvfourseven1"
    .asciiz "lms268eight"
    .asciiz "7ninethreeksjz"
    .asciiz "qeightwobrfvcssthreeeight3167"
    .asciiz "ninetwoone532fqhggszllnfcmfs6"
    .asciiz "838lcrhzs2"
    .asciiz "ninedjpteighthqrgvklln3cxbt"
    .asciiz "8lfxxeightone4526six"
    .asciiz "1lmvvbl"
    .asciiz "fvkxpcjm7tzzgkxfqoneeightone7nbxzskngd5"
    .asciiz "twompjtfbt2"
    .asciiz "twoeight4six"
    .asciiz "zmpml5six54fourfour"
    .asciiz "pndklmzmsseven9pncxgjrnine1three7pkjvv"
    .asciiz "88kggbsqnfjngqffkbp5fivetwo5"
    .asciiz "1xrvkpqvspt"
    .asciiz "1eightxhpd5bsctj3three"
    .asciiz "twothreexjvsxklsxeight4twofour"
    .asciiz "tvqsngkbl7eightzxhxjmrhgs"
    .asciiz "5zkxqxx"
    .asciiz "7eightfour"
    .asciiz "3pjsrdp"
    .asciiz "fivermk75ninetghvdrltz"
    .asciiz "prfthbhsftpmfcn7ronesix"
    .asciiz "three9pvxmhkscqv"
    .asciiz "sixninetqhj5two"
    .asciiz "nsoneight3eight"
    .asciiz "nineqdprvhtqb4fbone98nineeight"
    .asciiz "ktfgnssfourdqktfflninephpntvmmm139"
    .asciiz "qvxfzrdnineonenkpgxnnmqpsxrlcvjq5onehx"
    .asciiz "cq57sixeightwosvx"
    .asciiz "225vntfqdzqjgmtkdgbxrsr6three"
    .asciiz "56981stx6xdjkhnvgq"
    .asciiz "xksevendzeight2sixone"
    .asciiz "863"
    .asciiz "onethreetwofive5sevenfdmrmczlqs"
    .asciiz "28qcdzgrbdkh"
    .asciiz "6two43four"
    .asciiz "fourseven4"
    .asciiz "1jgone"
    .asciiz "qmpsfscxxtsix872"
    .asciiz "6sixthreeeight"
    .asciiz "1bzxjhv2x"
    .asciiz "onecs5one7five"
    .asciiz "vr4phpdtmk3fivebtltwom"
    .asciiz "4onefourqqrpvxn1two"
    .asciiz "3sixsixjkfssevennpjfzhhsg1eightgj"
    .asciiz "seven1eightsevennspvrr9"
    .asciiz "5fiveseven7ninepkzzj"
    .asciiz "xkjpxsqsfiveeightjgv2onelhdqjd2"
    .asciiz "sone7rhbtvlttsix"
    .asciiz "vrc6five6"
    .asciiz "twoseven7"
    .asciiz "onetwo9onehndznine"
    .asciiz "5six6sixr"
    .asciiz "vfiveeight6hdxnpfktttstnvhjks46"
    .asciiz "fiveninefour8zpptwoonefjzvmnhnvq"
    .asciiz "five53"
    .asciiz "seventpfztfccgm8bxjsjxgmz"
    .asciiz "eighttwo4tktgpbj"
    .asciiz "6426"
    .asciiz "jjkfournqbdqkddhlninekvd56bdshtbvn"
    .asciiz "onefive1onehkhsix"
    .asciiz "7sevenm9twofourqp"
    .asciiz "26sevenseven3twonelq"
    .asciiz "46threethree9seven"
    .asciiz "9pnzsix648kgngnpxttzlqlmnine"
    .asciiz "seven7onenine"
    .asciiz "two3mtklsvrrbthtxsrgrtwo"
    .asciiz "gkpfrq4vfddfqxzppmvthree733"
    .asciiz "fq2qbmone"
    .asciiz "threecvone7eightsevenxnmfbtp"
    .asciiz "fivetmbnqlchhtqmbcsssvxjzvlxdvznlbfive7"
    .asciiz "fvqzlcp5"
    .asciiz "qhgjmzntonefnlxfqqrxx5three7twofr"
    .asciiz "rczhlkcqpfkgcjmcggztjlqsgxmdxstwo88bdxmqjvlfl"
    .asciiz "npqxcdnhltbjmpjvdvfvvthreennsnbfljq2"
    .asciiz "four9gl"
    .asciiz "gjrf94three14"
    .asciiz "5xrpnzlneightsevenlkkltrpsqgzbzffpjhrkc"
    .asciiz "twozmxqcsgkvjtkshttglxcx234xtzhht5"
    .asciiz "fournine3rkxhdvjlzfour"
    .asciiz "4onesnfive1sixeightwof"
    .asciiz "threeone6sjnfive"
    .asciiz "4ninefournrphscbjjc"
    .asciiz "6xsvn6twofourseven4four"
    .asciiz "khbqhgqpph5krdsrs35kfbnqdbb6"
    .asciiz "7kdn5"
    .asciiz "4scmksvgl8twoltonetwofivejl"
    .asciiz "mmmkthreedmflzpmxqtccfz7"
    .asciiz "lbkdqjfcf58hpdtgjnnvhsixfive"
    .asciiz "chfbqldb52qkpzlkx"
    .asciiz "98gbxklnbcb"
    .asciiz "ghqrqplpone2ljzseven9"
    .asciiz "fxqfour2njrxrz79"
    .asciiz "rcbcmlvqc57btvhphxqbxvxxkjtlcvjffgxsdtjfb"
    .asciiz "crgvfkklfivesixsevenngm52jl"
    .asciiz "8rhvh5gdvx24"
    .asciiz "qcnlc62"
    .asciiz "pmcdbsvzgtqgczdvzln6"
    .asciiz "fivernine29"
    .asciiz "skslcfqkgk47four"
    .asciiz "9twonine5sevenone"
    .asciiz "ccltdxdfksnninekpzccsvtgrtseighteight9pgvlbkvs"
    .asciiz "1nine7dqxdgknlz75"
    .asciiz "fourninebbpthvqntf6759foursix"
    .asciiz "qsvpn4mvhxgmzsevenpnkmtzrg"
    .asciiz "82fqxx6oneg"
    .asciiz "sixhnrk34"
    .asciiz "nine5five6dkqxmnc"
    .asciiz "qhdzhhqfbfjnfmglvxctkjm59"
    .asciiz "1threeeightbchlm"
    .asciiz "1drjnqoneninennhqt"
    .asciiz "56six6two76bs"
    .asciiz "7onefoursixhkhpdns"
    .asciiz "4threectphcxfmmksdcsvhgfx"
    .asciiz "5jsqbninelphjdmsnjl9eightql"
    .asciiz "5vkkmjkrxpntmgfkfxmg4"
    .asciiz "6sjxrtfnjkthree"
    .asciiz "pmeight418"
    .asciiz "vgldhpczvgr2twofour784"
    .asciiz "5ndkknqfjjxfiveddfiveb"
    .asciiz "five1tmv"
    .asciiz "four37fourninethree34"
    .asciiz "rcnvxqrsevenjttxd9fiverqzblpnrcjhbc4"
    .asciiz "tdhvhhjxbbmjnls1vn8six"
    .asciiz "two4three9"
    .asciiz "2ckvlpznbqbqblqbr"
    .asciiz "6nineseven8zfqfptcjxtfmmkqpj"
    .asciiz "2jdxnqttrjvhmbbxqqmeight"
    .asciiz "zloneightjzsxtsxhbgtwokdfour2pqmfkkqksxlfv"
    .asciiz "8sixfive3"
    .asciiz "qxgzh3gdjmdqlpdnfgdxvbblpnqtsevenseveneighthvmqqdmr"
    .asciiz "8jjmbqnfive3bbxdzctxxn9five"
    .asciiz "fivethree38four"
    .asciiz "pdzbkmcvhbvfivexv5five5hzvvg4"
    .asciiz "4eightkmsrlqsfcnmzvprdf4rcxxqtvpqcfjfptmk"
    .asciiz "twortrlbqqkrnqgxhgseven5"
    .asciiz "8sevenltzbjsfjxdkdjncm"
    .asciiz "1nineqqbjsoneeightmzvfn"
    .asciiz "threeeightsevenfour3jhkcthree"
    .asciiz "nine265sixthree"
    .asciiz "nnmbqhf6three"
    .asciiz "4one5fivefivehbfktxgrdkdrgp"
    .asciiz "twothreetwoseventwo8"
    .asciiz "bkggrdbngtjfmhone6fmvfzpjldzb"
    .asciiz "bpbg4tjqnine56zklbtkzlrs3"
    .asciiz "4twokmxgqbgqgsseven8oneseven"
    .asciiz "hvdv74ninej"
    .asciiz "dfknvxfmczqrgdbqsph823"
    .asciiz "3twoeightnine"
    .asciiz "foursixeightbfhlczrpjfxfive7two"
    .asciiz "fcpkrvmtzxkrfsmqcbzeight7gfourfbkthreeoneightvm"
    .asciiz "four18vgkmj2gxmtxsbnvxthree"
    .asciiz "415threecshnzmmx"
    .asciiz "sevenseven44lkfourgmqtrs"
    .asciiz "jnzsqsgznvcnjjfbblkteight8"
    .asciiz "497three5eight8d"
    .asciiz "88onethreexzsbgprp1"
    .asciiz "eightszseven9htqlxb"
    .asciiz "1lqqgzdrxt4qlqklftlsqzm"
    .asciiz "rqbjqpfhzfeight6oneonelllcmbrdxqhmttptg"
    .asciiz "fpqxqfourthreefqgdsmhjfk2rmb4"
    .asciiz "qnshr9threeonefour"
    .asciiz "xshsbkqxpltjsd2fivexvtrmnlpvtwo"
    .asciiz "446"
    .asciiz "nine2pvn12five7"
    .asciiz "fourfourninemvfvztpkbb9nine"
    .asciiz "3fhtlpone7965four"
    .asciiz "qkpdgtrfprttrzc69"
    .asciiz "1mfsltcsxvlcxfzdh3"
    .asciiz "fgjfltjcsnps8three"
    .asciiz "tbeightdsdtzmncv5pdcsk"
    .asciiz "rsjvlhxtn7six"
    .asciiz "7mdtl"
    .asciiz "four3three6sgxdtdmtnfive3"
    .asciiz "3eightninenineeightlxtqtspmklrxbknftrbh"
    .asciiz "onenine92sixrnine6tggjndsrfd"
    .asciiz "oneqdfhrfzlteighttftvfcrmmzz43lbmlbg"
    .asciiz "35bthreernjskthzrs1two"
    .asciiz "threesixeight7rjpcxnzmzfgngjpkk6eight"
    .asciiz "six9ninerxfnldpsevenone1threenine"
    .asciiz "5sixhjzkknthreenxklxbvgxfouroneseven"
    .asciiz "1zkx93two9sixseven8"
    .asciiz "sixtwocdnqdn2vdbnblzlvffmrninetzdtdpjjsrsix"
    .asciiz "twoeighteight437nrscj"
    .asciiz "six31vtcphkpltgbcprdhvdfivefoureightwonvh"
    .asciiz "8pz"
    .asciiz "hzrggpcmpnqzzgnxjfqrlllgnqks496five"
    .asciiz "7glkjtgbsnqhnplzcp9rllkkznffnznngthree4seven"
    .asciiz "one7fivetwo45"
    .asciiz "4nxzxtnhb5foureighttwo"
    .asciiz "threeone56lgzgdklhtwo"
    .asciiz "rjnmxbflvn5oneightpj"
    .asciiz "fs7tpvvf"
    .asciiz "fhfkcx1hnzzjjh"
    .asciiz "6onexqrfvldeightfourkcvpngj"
    .asciiz "1threeeightxxcnjfl3zbxfgmfsx"
    .asciiz "9327six"
    .asciiz "three5p86sixcxdsjjvn9eight"
    .asciiz "four1cfrxsdgnjtwo"
    .asciiz "rxjmtgsixone87"
    .asciiz "49sevennbgqf"
    .asciiz "sixone42"
    .asciiz "three3jblhchr"
    .asciiz "hlroneight3hsjhkl"
    .asciiz "sgtrvtcq22"
    .asciiz "8seven985"
    .asciiz "qrhnjnkstwo4fourthree"
    .asciiz "8phnkkdrghbmtql"
    .asciiz "two9sixncgqpsseventhreefourthree"
    .asciiz "one3six3"
    .asciiz "1nine4rtvxxgddzhf2"
    .asciiz "2cfp84"
    .asciiz "khgkvntthree2"
    .asciiz "vsznj15ninehhlfiveone"
    .asciiz "mmrxqjbjmrtwo7"
    .asciiz "oneone7ninekmzgq"
    .asciiz "eightone84lzktckgrbkzjzkqqxlgqn"
    .asciiz "btzdblrrpfxljsix69"
    .asciiz "82sixseven"
    .asciiz "two5nineseveneight2eighttlmvfkf"
    .asciiz "vlbnccpl1"
    .asciiz "four5gsbz7"
    .asciiz "418ncqrk651"
    .asciiz "bkbbncm9eight6eightnine"
    .asciiz "3sksvljxpkz4vcxsdnztfxeight8"
    .asciiz "fivecfrlnh51glx2dsjqseven"
    .asciiz "hnflgpth64threefour"
    .asciiz "mjxthlr1six4tdplzrnhklnz"
    .asciiz "ddrkrnssxtlkhbrjvkxpb39"
    .asciiz "2tfoureightgvnl"
    .asciiz "79six"
    .asciiz "sixvktfvkmv5xhfgnine"
    .asciiz "86szmzzfntxxltmkffnczrjvthreethreethree4"
    .asciiz "threethree1sixdkmjpmxtwoonezktwo"
    .asciiz "tlp189jnmskmcnkhvmn65"
    .asciiz "41nqvvc"
    .asciiz "4xrlpc7c82oneightk"
    .asciiz "six1threecxxtttdthreeeightjc"
    .asciiz "gbhkzvnrxfourndtfc6"
    .asciiz "fivesevengjmnbpdvcdeight6vj6"
    .asciiz "vfjdp8"
    .asciiz "8dfrttfrtrtfour35"
    .asciiz "887"
    .asciiz "714eight1tdnt29"
    .asciiz "xbmhsbn3"
    .asciiz "gjktjcn3kf"
    .asciiz "1327five1eighttwobfhtqcjjms"
    .asciiz "pc615"
    .asciiz "one1rthreefive"
    .asciiz "fcjsktwo9"
    .asciiz "lhgqvtxcntrljlnhdllthree1"
    .asciiz "5xxmtwo1dkjpchmzfz9mndbrcbzkh6"
    .asciiz "6zxdxzxt62three37"
    .asciiz "cveightwo6"
    .asciiz "ninezdvzbkggh4one63"
    .asciiz "three7fivesix"
    .asciiz "3vcdrd881vlmglkfone"
    .asciiz "2ninenjcvq4"
    .asciiz "5jltkfhl5onehthree3"
    .asciiz "8eight4rgfrhseven"
    .asciiz "6vqjgxltqd18two7onelkmc"
    .asciiz "xffld1jjlqxfz7xjvxfspzrkztsdtsone"
    .asciiz "9szzhnfpssevenoneeightfour42two"
    .asciiz "four91mfnrxkcckd6vbhtxvvmzhpqqrkzxv"
    .asciiz "eight2three6ksfive"
    .asciiz "94eightslkpbf5zc5tm"
    .asciiz "4twottthree91sevenone"
    .asciiz "kjgfgq226fiveseven2"
    .asciiz "kjrrgfmthree36ck"
    .asciiz "sevensixfour24one8"
    .asciiz "dqj8eightthreeqzcz8"
    .asciiz "xtwo5pcdl3eight7"
    .asciiz "one131xnghfczdpvsczkrxhjt3"
    .asciiz "j4qqx"
    .asciiz "hncrcntcmmpkn6sixzvjzkgr7"
    .asciiz "9nnzltv7mclrhhgnmq2nine2"
    .asciiz "6sixeight9"
    .asciiz "5jgnhjmdc6xsdsl1five"
    .asciiz "onerdtqzhpbdflxvrhnpjqdqzn39"
    .asciiz "rcroneighttvnfcngrfblvmeight7sevenonevknxtpfour3"
    .asciiz "mcfjn569"
    .asciiz "44"
    .asciiz "84six"
    .asciiz "nineeight3"
    .asciiz "one916"
    .asciiz "eightfourseven5four"
    .asciiz "nine1gpmqdxkzmr6six"
    .asciiz "two4fouronesevensix1nscgll1"
    .asciiz "eightthree44vxbjmvbpfleightvgbjxcgrjonesix"
    .asciiz "6vmgscbtpsnkktmbdjpmmlv"
    .asciiz "1one1"
    .asciiz "ttwo9sevenninetwothreephpfrtjztn"
    .asciiz "cxlzcpdd32dhvvcsgdcc49rhhrqpkxtwo"
    .asciiz "8fourkkrbjsqt"
    .asciiz "rxndgg4lhkcphmtmjvtqkc9qsevenpcmftwo"
    .asciiz "jpgrzfvdx3858fourthreesix7"
    .asciiz "7krxc9mjhgtonetqd"
    .asciiz "eight2qhspjfm"
    .asciiz "gsxplbone2pffltsp4two"
    .asciiz "hqtwonethree939zknfxrqjpn4x"
    .asciiz "eightsevenone4sevenmhxbbqrtwopgvvgn"
    .asciiz "6three5tlffrcdszg384"
    .asciiz "frqhjmqntneightxgtldk9qpdnncxgnmqzbzkqsxz5"
    .asciiz "vsf42twolzmftmbbb346"
    .asciiz "7eight47"
    .asciiz "9four94kpmvbtblbxthreefourone"
    .asciiz "2eightctvgglxjgxvghmsbbfivedbnn"
    .asciiz "qxkvzrpkj79lkqtt"
    .asciiz "jfjgzhrkpc77nine4nine8"
    .asciiz "prqrpms3ninefiveqnhtngpbsix"
    .asciiz "gqxbtbtvdoneznqsfpf9threelmhn"
    .asciiz "four7sixjrrpqdjtbsfivetvcngclhrprmhftwo"
    .asciiz "9sevenntmbflxvf1eight3nine9four"
    .asciiz "twoqgxklrmdzntrbtvcfsix6"
    .asciiz "zzt8kt2"
    .asciiz "ninethddninexszntlm9jnqnbpb4"
    .asciiz "lcsfourxdsk9297"
    .asciiz "f2v96nqfour"
    .asciiz "2tqsdl"
    .asciiz "7onethreegeight"
    .asciiz "47q667gtgj2sm"
    .asciiz "8four7sevenfseveneightninettlqkc"
    .asciiz "5ppkgf"
    .asciiz "61threetwohxlxzbrlfjk"
    .asciiz "6fcfbvhpzgl57"
    .asciiz "five2tjkc5three5onepqlgv7"
    .asciiz "five925ltvrgpzm"
    .asciiz "jjstljfs47threebcg"
    .asciiz "37seven"
    .asciiz "8three47eight2pqxcvbn9"
    .asciiz "threeeightrdndbtfpbszscbqzlhtq84"
    .asciiz "xvqtwoeight4twoone2seven"
    .asciiz "fourpcqvbcfvz8onefivev7xvtxdpbnone"
    .asciiz "3956fivethree"
    .asciiz "sevenlmsksix55"
    .asciiz "eightnine17"
    .asciiz "5hgqmlb"
    .asciiz "eight91pfnngffzl8dxvlnnninektlmqq6"
    .asciiz "5one8two9hh7"
    .asciiz "qfourlvclhf8four"
    .asciiz "9cfgrkdmeight"
    .asciiz "foursevennvxcmjzzpjtwoone4onezlht"
    .asciiz "njpjsceighthqqeight33two8ppjf"
    .asciiz "four5djlmjfive99eightonefour"
    .asciiz "jcf2s6gmzrnjrjkvfkgone6kbhjc"
    .asciiz "threeninedbskzbqlb8jpnine7"
    .asciiz "onekbddzcdx5eighttwo3"
    .asciiz "3xms"
    .asciiz "mmvvxmpthreesixone96"
    .asciiz "3djjfsixtwo7threeeight1"
    .asciiz "339"
    .asciiz "3seven6"
    .asciiz "six48nine533oneightv"
    .asciiz "dkvvxngfrvhktzx3sixvqtkpqztzs49"
    .asciiz "1three5ldzvllvqeight"
    .asciiz "9hn8mdcpvzqlzctwo922"
    .asciiz "164k7"
    .asciiz "sixsix4c1tnkmzkqconejvdkcdfntpfkpsdm"
    .asciiz "31qvdnvdqthreetwofour8two"
    .asciiz "htwone6fkzkrdfcpqlnxlone"
    .asciiz "2875"
    .asciiz "6eighthj"
    .asciiz "7lcchpx3x96fivefoursix"
    .asciiz "kone1ptnkjhks65sixrsseight"
    .asciiz "23sixninefour5"
    .asciiz "xdnzfbpq2"
    .asciiz "hbznxkpmktwo3six6sevenfourfive"
    .asciiz "tbbcrzdtfive42eightsixfourthree"
    .asciiz "5mjgvsrrdlnrvlr6ninevlzrksfj2five"
    .asciiz "cftlmrsptdjtsndl2eight"
    .asciiz "snmkjqprhk57ninetm383six"
    .asciiz "krxqxdgdp7fkgtmdtbx11fivenqncrnhcone"
    .asciiz "3sixmcfnf"
    .asciiz "7jkfgvjlbkfvlmf9"
    .asciiz "sixgljmbvxoneseveneightpfvvnl8"
    .asciiz "523eight6"
    .asciiz "seventwoone3rnxghtb9sixbkqch"
    .asciiz "5hjzzvkbls9qrcqtrrk19hbrhszxfive"
    .asciiz "8kbhdp483four"
    .asciiz "seven7five1"
    .asciiz "dklfjdmzc15zchbgmbqkgzgkn1sixsixeightwovz"
    .asciiz "8sixqbpgkppjktwooneninethree"
    .asciiz "seven16"
    .asciiz "sdqvhfour2glrqkmj5fiveonegzqsdtgqskjcmgg"
    .asciiz "twofiveoneseven1rqjvrrxtwonen"
    .asciiz "rmgdlx9cskhdjlmtwobvpnjrcxbfftd5"
    .asciiz "93mcfoursix4"
    .asciiz "gst66jphtlbtngqdqdnonefoursevenseven"
    .asciiz "seventwotntksixjrczhp557"
    .asciiz "svjgzfkbj3five"
    .asciiz "threeninetgqdgnmr1xxnxfxlninertwo"
    .asciiz "jjhpnine33hjnine"
    .asciiz "twojgcp9"
    .asciiz "vgkbmkzrbbvlhv267"
    .asciiz "fournine1eightfourcdvvdgkmkndbkrheightone"
    .asciiz "1onefourthreecqbffjdvtzbxdc"
    .asciiz "mmgvhrmftnmtdkqgf29"
    .asciiz "7qnsfqj3one"
    .asciiz "qhr933three5"
    .asciiz "pqblftsix3"
    .asciiz "one7sgsqvszkd6ztwovcrmqbjthdthree"
    .asciiz "1qgqtnfive487czvxsjk"
    .asciiz "37jrggmdknnine"
    .asciiz "3sevenfour7sblhjqg9fourgchqkdg"
    .asciiz "nfxdxlssvgxxvzgksrkxqtwoffpphxdqjzh9seven"
    .asciiz "4qjhllxzdb8sgbgksxbblsmftd"
    .asciiz "twofivegddmhcplptf13five"
    .asciiz "twosix55"
    .asciiz "3zcftpvkbmzpffpjrfouroneseven"
    .asciiz "6vpsixhprqhzthree"
    .asciiz "eight7ninemsmfbnqkzmqfd"
    .asciiz "nbrtxpkpb1733"
    .asciiz "nine33jbrkqlnf1"
    .asciiz "14lgl"
    .asciiz "eightjjvclfxp9"
    .asciiz "fivetnmksk8cp6"
    .asciiz "dpxcqhbkvlhccb1fntmcrjjgccnszct"
    .asciiz "lbjppg3hrgpzstfqgbcrzbmn66two"
    .asciiz "dxbxkzmpzzthreestcvtvhftgzctnvnshzgqtbgxlrqkthreefgxdrfmm7"
    .asciiz "31lklpfour"
    .asciiz "nineonezcmrfppsvbg7seven316"
    .asciiz "9cxgcgjsd8ctgbh7"
    .asciiz "9vdnine4five"
    .asciiz "2jfkrtdxvzq"
    .asciiz "qgzgclpt8jltqzkpvddtm"
    .asciiz "614two"
    .asciiz "pjb92two5sevenfkb6three"
    .asciiz "twosix766five71"
    .asciiz "86vbnpsixthreetwonevng"
    .asciiz "onel2one"
    .asciiz "4ninesevenpgbqgpfgkfzdsixmmfive4"
    .asciiz "7xgcmqfqmk7twothreeninepdt5"
    .asciiz "sdonefour77one"
    .asciiz "fourmfhmsznxffzpgdonegck6nine6"
    .asciiz "rxjspvttx6nine1knbsl"
    .asciiz "pljd3fourone8"
    .asciiz "8onevhpeightz94seven"
    .asciiz "jtmdhqjn5eight"
    .asciiz "onefshb1sixone2b"
    .asciiz "seventwo4gnrsrpnfppseven2"
    .asciiz "147fourfour"
    .asciiz "9hfjjmgrzntssjpxcvbzpvmqzgsd54twonine"
    .asciiz "mprnmlhxsdtntbknine1"
    .asciiz "98onefivethreesix"
    .asciiz "gd6ninejhsrhsevenksvkcone5"
    .asciiz "fourd9xkcsrncpdsbqhcqg34twoneb"
    .asciiz "pbx74kfivefourvmslqvfbml"
    .asciiz "dmxmpl71"
    .asciiz "594shxctmq6qkmnbrm"
    .asciiz "5qrhd8jmmthjkdzhrxf6two"
    .asciiz "four4six4three"
    .asciiz "hlrsmmjjvshzztxrnznmseveneightfive9sjddhlfvftbtd"
    .asciiz "fivesbcklfdrvz4pcxsvdcqpeightgj1tqkfnv8"
    .asciiz "tthree4one9"
    .asciiz "nine4sevensixone"
    .asciiz "eight5threethreesevendrctkthree2"
    .asciiz "4ngzcbtwo451bpvbtqdvk"
    .asciiz "9two1tdjdlrflshfourjlkdctfp"
    .asciiz "sevenseven6132sxqfspmvxjfvh"
    .asciiz "fourfour28562"
    .asciiz "seven6gsevenrtcsldgztqthree"
    .asciiz "sixtfmvfnkqxlp3sfsmdlfgh5nine"
    .asciiz "tjeightwornmddbpcsckjrzdtvzrxfivef4"
    .asciiz "gcv42jfcdftseven1"
    .asciiz "166eight73"
    .asciiz "5tlcxlscsgmrznhlgfgkqdpksjllz"
    .asciiz "2one7twofivesevenqxrdvbczfmt"
    .asciiz "1bdqfdmtfrtx2svdltfzknnqssvxvsdkzvd3six"
    .asciiz "rzztvfourfive754fournine"
    .asciiz "71vfsixrjhdqqj"
    .asciiz "one63csbsvkqmkjt"
    .asciiz "3seven4fourthreeseven36"
    .asciiz "bmkr6threefour"
    .asciiz "5fmr6four6mxqj"
    .asciiz "3five1one93"
    .asciiz "5nrtfrdhfv4mkkhnine4"
    .asciiz "mklgxhrpp3two"
    .asciiz "hpfrfpkddsdqfgbhtgfourthreetvdvjrfr5"
    .asciiz "five6ttmzjcs"
    .asciiz "tlbzoneninesixsevenpddssz2"
    .asciiz "prceightwo1"
    .asciiz "vvktl7eightltmtpfcrkndtkglhndhvrbtfv6tjgrzqv2"
    .asciiz "sjpzgmvmddttrcmnvzseventwocgzc4"
    .asciiz "seventvxrsbbbzrkfbkbcrbdsdtv456"
    .asciiz "ttwone12threesix"
    .asciiz "85nine"
    .asciiz "hdgxncxv83"
    .asciiz "58sqpgnine"
    .asciiz "65mpmptlg"
    .asciiz "threefourxvmdkhlqd2three8xfphd8"
    .asciiz "rdptwo22threergcfdntchfqbsseven"
    .asciiz "98jbmmhznxvrqkdxseven1onem9"
    .asciiz "eighttwo1twothree3sixjbjqgzx9"
    .asciiz "9klnfhhx"
    .asciiz "7three7five"
    .asciiz "jlvrcqflvfivenine7cnx"
    .asciiz "fourrr2ktmdqhsteightwot"
    .asciiz "bkjgtqxg9fivenrsktmkmxcfbg4"
    .asciiz "eightjj95six"
    .asciiz "6threeonebmpqrnqgdqlkkqc"
    .asciiz "seven5bbzlsnvjchbjgxh"
    .asciiz "lbsptf1threefour9"
    .asciiz "37threeeightcgfxdonebhkrdnfive4"
    .asciiz "379263"
    .asciiz "24vmbb"
    .asciiz "9v"
    .asciiz "1seven15"
    .asciiz "slxpsix3threeeight64jlrnkmkrqr"
    .asciiz "ninedjlvkxqh24"
    .asciiz "sneightpssteightpdfzqjcjgsmseven7one"
    .asciiz "sevenninehf6bxjtfntwo"
    .asciiz "four2cknjgdkbqdvl4"
    .asciiz "qxrzdhsjjkmtggt42"
    .asciiz "tgsjddrgtkthreefzlvgrsix32onetwo"
    .asciiz "3zldxonenrghfnhhmptbpgcl973"
    .asciiz "8ckzrgrzbone4sixdspxtwo"
    .asciiz "xvxzprh1mbpspkrv"
    .asciiz "lgchfzs6sixthreeksix3khvhldq"
    .asciiz "sixonefour2mxslvpdhk7"
    .asciiz "6sixsixbghxppnztxfive"
    .asciiz "jpdbbeight57seven"
    .asciiz "2onethree61jtnjjcq"
    .asciiz "63lfsznprjddqpfourcrkthree"
    .asciiz "ninepqmvc2xtwotcjcfcvht"
    .asciiz "1bcrpone"
    .asciiz "pntsrhj725xblt2seven"
    .asciiz "12nine1"
    .asciiz "8twooneseven22"
    .asciiz "hfrbxdlfzmjvdslseventhmtqzbtcmsqbeight5fiveqlglhclrh"
    .asciiz "three6htff5nlzslroneightxm"
    .asciiz "hzcdc6threeseveneightmckdvg4"
    .asciiz "tgpjgvlq6nineseven8six2foureightwozbz"
    .asciiz "three83bbbfsg"
    .asciiz "75bpmqvdseventwo9four"
    .asciiz "2nine8vjdcgvfns"
    .asciiz "rjndbbfmppgd67eight3hztlrqv6"
    .asciiz "onefourfour6"
    .asciiz "two5six1"
    .asciiz "954ninetghsfnnine12cmp"
    .asciiz "6one8nfzstqlfive"
    .asciiz "seven1sevenjrslmhrfivexsk"
    .asciiz "nineqjgmh1onekqblsvjkdn2five"
    .asciiz "eight94mzsevenvtkkv1cdqgv"
    .asciiz "xsix4sixnine"
    .asciiz "3pbxzxrsd"
    .asciiz "77four9"
    .asciiz "8zcthreethreeninettdb"
    .asciiz "c4eightsevenxqnhvclfour"
    .asciiz "gxbkjmfhhzlzrbzcmjmmnqxlsevenninefour4jcbgttq"
    .asciiz "9zptjlhzkls1fdfzxvpssleightsdcmfour"
    .asciiz "8oneone9one"
    .asciiz "1threefive4zkslknvmr"
    .asciiz "9seven4jninesix834"
    .asciiz "sixdpgkdnnt4kjzgrjtcqlqq"
    .asciiz "1qmcgnclrdqrc"
    .asciiz "5xhlzgzpzbgzjcsthreefive"
    .asciiz "mrgcpmnnsixeightfrtjfourjlbcdt3"
    .asciiz "129twokqmtmdj"
    .asciiz "fourskzt382mnznt17eightwocx"
    .asciiz "9hnx914mtsnhnxtgn6"
    .asciiz "81psmkhzk3fiveltthree"
    .asciiz "lhbtwonetwo3dvrtmpjxk"
    .asciiz "x859zhjsbzjpjrtrp6"
    .asciiz "73mqrrpdrs"
    .asciiz "43d73rbddvrz"
    .asciiz "rnmrrcndm6"
    .asciiz "x6rrnsmpgqmp3three1"
    .asciiz "pbtnndfj2onetrvmvcftf4"
    .asciiz "four6rfoursixfour5three"
    .asciiz "69nine2szkcnjbmcvjtbjbgnmssghfdlninetwo"
    .asciiz "one92phhclzfsfxqg"
    .asciiz "hzc2"
    .asciiz "fivethree8threedttx"
    .asciiz "pjdkcdbxt5"
    .asciiz "trgggsgx92six"
    .asciiz "9ninethreeknlvmb"
    .asciiz "eighttbbxhxcmrjqxkbjrdcjv5nineeighttffour"
    .asciiz "9cghvbkpmkt"
    .asciiz "sevenzhlcljtqcntthp7rr2"
    .asciiz "3fxgjqpbp"
    .asciiz "7nineqxqvhgf1plh4"
    .asciiz "2fivethreeeightsixfiveqz"
    .asciiz "twoeight8"
    .asciiz "fvvjphpmqffqjchvtfivemseven8jmlrk6troneightvf"
    .asciiz "three46"
    .asciiz "tktkqsqskrpxl7thfrqnpdkzcjxvfmmbfourone"
    .asciiz "9twosxgk"
    .asciiz "g3scthxjb33nppgcone"
    .asciiz "mxmr17fvcgh4nine"
    .asciiz "vz82"
    .asciiz "2threefivenineeightqmjlcsbqrcg4"
    .asciiz "xptfourthree7mcfeight"
    .asciiz "bdthlfbqbczmlh56"
    .asciiz "onesixlpqxqlkxxkqldhd5twop36"
    .asciiz "seventvptphkhhjvslhtphntwo2cfnn358"
    .asciiz "shjlthfxpfive4rzm6eight"
    .asciiz "three565nine4"
    .asciiz "xfjoneightsix47sevendvtxtfive6"
    .asciiz "9717one"
    .asciiz "rkmhlxzpxgfourthree7qhh69pfds"
    .asciiz "3threepvknzvbmbrvljtcx13three2"
    .asciiz "1zbhchxzlccgfvbdtlmfr"
    .asciiz "28hqpxjvxcmnqtxhhgninethree"
    .asciiz "eight3phxhpsxnz6nvgqznb9h9"
    .asciiz "2klvscxmt94fourthreekgmqgjbhnzrxtwo"
    .asciiz "7eighthmbvjlfseven5"
    .asciiz "k45ls"
    .asciiz "1qkvvbvsixsix8threeshqknine"
    .asciiz "4928plcrzs6"
    .asciiz "gsskhbkmfzq8"
    .asciiz "6crvcnine3six7eight1six"
    .asciiz "fourfive311"
    .asciiz "lqdjctn82sevenjdm6twoonesix"
    .asciiz "8three8pqhmjjc"
    .asciiz "hgn6mnpmdmcpzceighteightnxkvjjfrninejmpkrfzcgv3"
    .asciiz "ln7pqvg3sevenkqtztcpjrxeight"
    .asciiz "dqbrjj9fourseven"
    .asciiz "4sevenone16"
    .asciiz "9cxtchrmsd3fflmkdzdgp"
    .asciiz "6349"
    .asciiz "sixsevenlqgzcsvnd1"
    .asciiz "kjfcbgeightthreejvqgk874"
    .asciiz "2vkrvzpmfv4eightwob"
    .asciiz "mhjrqbvlmgsixthree74"
    .asciiz "fivekldbzshd37"
    .asciiz "seven11fourcgvnqr7four"
    .asciiz "fztzttvmx4vtwoone288"
    .asciiz "5fivevlbqczq1"
    .asciiz "twoncljq5"
    .asciiz "jljz388kklzbronetmmf"
    .asciiz "92twonmjmkhgqfhx66"
    .asciiz "2rh9nine14seven98"
    .asciiz "7hgzjblbxpkltmjmlpscd4svtwo1two"
    .asciiz "xcchzd8fourhkrstwo9three"
    .asciiz "lxgxlsdkvcfxsclj4cqzjgjgvtmkjlhxfnmfc3"
    .asciiz "86hzhn8eight6"
    .asciiz "qhsevenvpg4hzffldbrvpxxpthreeqpvvdndv"
    .asciiz "five6eight15"
    .asciiz "mhl8rcdkxx8"
    .asciiz "3sevenv"
    .asciiz "one131eight86fourk"
    .asciiz "7hsnjrnlcnb8twosevennineeight1"
    .asciiz "2khhfivejgbknv65"
    .asciiz "8lmfd298dlnmszrrfive"
    .asciiz "one5ppczgjzzsix"
    .asciiz "nine6fchgqxsdjhqtwoqpqffhn6ncjxx"
    .asciiz "bfivehtndrmm62"
    .asciiz "829fourbjpmbfqkqgsixtwo"
    .asciiz "xvcdsix3five"
    .asciiz "sixhqthreeninethree7"
    .asciiz "gpsdvj3zpztgcndvcxz12"
    .asciiz "seven3fglvdzxzcqfive7four9five"
    .asciiz "3five4gzgjbpptwo"
    .asciiz "nine44four8"
    .asciiz "4143two"
    .asciiz "fourpcjhfjrxdhvzf2dkmszvtjx"
    .asciiz "ninecrxdkznbg8p72nine2"
    .asciiz "sevenrbzhktn7five7sixvklcksmb"
    .asciiz "rndrrfhvl4zscdjmxcbrfvrxxjxcc1jjfsjntxzqp6eight"
    .asciiz "sbnkdhrjrthreecvxqrfxccdpmqsix5jjpkrxfqlnxbzlzskcfgr"
    .asciiz "two4xdtsdjtneight"
    .asciiz "teightwo5k4eightmtheight"
    .asciiz "eightzlc6lgtgxsvckm56"
    .asciiz "qzrzhnchttjnjxjnine4seven611"
    .asciiz "ninefiveninefqtd37eighthzghljhhv9"
    .asciiz "bcbbbneight1rqjtnnzrv"
    .asciiz "ninegldjhplfthreetnqcbrllpvjtlthn9xkbqkfourthree"
    .asciiz "nineeight4"
    .asciiz "4zvghdrbl7onemsbffzkjrb265"
    .asciiz "lthreesix7two"
    .asciiz "vvkfivefmkdsbst66"
    .asciiz "3rxdgrfgdtwofourseven"
    .asciiz "onegzbdndnqkkckpsh1vftnlhnqjcvrm4"
    .asciiz "gpjld3lcvtzckpqrdghlpz"
    .asciiz "3ngvnzone3"
    .asciiz "sixfive8eightnine"
    .asciiz "tscdrcsvztsnktrj495sg"
    .asciiz "9twojbzsqv64smmhbqc"
    .asciiz "8ninefour"
    .asciiz "ttlrjjxm41four"
    .asciiz "qtwonekvlm9tnmzlvpzzs1"
    .asciiz "twotwo1fiveninelcl"
    .asciiz "8rfvffourtwotwosixpqmthjsrgj3"
    .asciiz "nineeight2seven"
    .asciiz "n9"
    .asciiz "two7fivenrgdqshs"
    .asciiz "nine5foureightwom"
    .asciiz "4tworvqpsxzhn"
    .asciiz "18ghsmdrjlq8rfpmvqtgcl3fournine"
    .asciiz "8three7qfskg"
    .asciiz "nine82"
    .asciiz "41zb5"
    .asciiz "5cdpnqzfbthree"
    .asciiz "247pgfzbhpbkxsk88three"
    .asciiz "xsnjsqrrpck8two7"
    .asciiz "qmlbtk79vqnzqv"
    .asciiz "pkcmsixjhqtfzvjv23"
    .asciiz "1nine1lnzeightlpxpssdgtsgbvqmftmnv2"
    .asciiz "threefourhkfckgvqn721"
    .asciiz "onethreegzninenineone31"
    .asciiz "kttwo4gcpxpvrp"
    .asciiz "4six4632"
    .asciiz "7vmkqlqfbbzkksix3"
    .asciiz "jsixpckt8six142nine"
    .asciiz "two753six22f"
    .asciiz "twotwokjgftjhnhp6onefour7hqzlcbkz8"
    .asciiz "ghmjbfv49pls68"
    .asciiz "three1889twogbcjkkzc6seven"
    .asciiz "twothreethreevkmlsplbgninenine4six"
    .asciiz "seven7vhjqfmklxsvc"
    .asciiz "pxnxlqg91"
    .asciiz "fzrbbvfsqrgcgsjjrd5"
    .asciiz "skcm59mfgkjvcffourhqzsbpt12five"
    .asciiz "three9eightvfksbfcf18vlvgsixnine"
    .asciiz "oneonefour9eight"
    .asciiz "zjrxbvxtjbqtqqeight75rf"
    .asciiz "flk6gjsixtwo74five"
    .asciiz "4jncmngfmqxs1four9"
    .asciiz "1fivefivefournine58"
    .asciiz "274"
    .asciiz "gjjzjfplnninetwofourlgpjfpnkhsixthree3"
    .asciiz "4jnthree75tdxnhpm7bv"
    .asciiz "three82jgvgjthreev"
    .asciiz "sevenfour8"
    .asciiz "threeqfrhnkfkj2jhzllpn"
    .asciiz "one859one"
    .asciiz "8xtnbtqqh41fourmgxzpdv957"
    .asciiz "37126"
    .asciiz "zzsixsevenfrszzvchj9hxhdcxmxqqckclmfm"
    .asciiz "sixsix79nine"
    .asciiz "s2mkfdqmcznztqtgddtwo"
    .asciiz "hpvpdczjvkf8two"
    .asciiz "6two73hdnbrkgblgfiveblgzksljjjskfpthree"
    .asciiz "7kndzrhvcnstgfxjlff9twoninervrknsffmfzmdhtth"
    .asciiz "three81kqcfplcf7"
    .asciiz "fivegtfbnspddkeightmmv4bzksixeighteight"
    .asciiz "596ninefqrfvpfs"
    .asciiz "sfpzkhxqp7"
    .asciiz "kqd5"
    .asciiz "1sevenljlmfh6"
    .asciiz "75sevenxpzv8ngffsnm8"
    .asciiz "rxqnshcskglgkrlhzone4"
    .asciiz "1threespckmrpdnxfoursgqsevennnrhjkcrlbnine"
    .asciiz "hffpvhxzznnkg86one61two"
    .asciiz "7bqm5sevenkdnmqpqfvvtbsct"
    .asciiz "3sevensixnineone5nine"
    .asciiz "two1five23dgmqsgzftflfmjseven"
    .asciiz "jzmltz1jtlnsbgtsix"
    .asciiz "nine1sevenjltnln8fivenine"
    .asciiz "svmzvnr8tfxqlxnc1"
    .asciiz "sixrmcsqtphlk5"
    .asciiz "fourjnpshskvmsqscq8threethree8six"
    .asciiz "3threetrqfhnbtsbckkvf"
    .asciiz "5fcmhxjhpr75zkcbqgltq93zcdm"
    .asciiz "eightlzjjtzk3xlbvgnsfoureight8"
    .asciiz "hrrxxnj6nine1two"
    .asciiz "zbnj6txxhqgdtq21fvcjxvkkrsrrdmkrmvtbjhs"
    .asciiz "threex86three"
    .asciiz "onesevenone6four6twogjtqp"
    .asciiz "92onethree52"
    .asciiz "qgzcfour9eightbsrseven5"
    .asciiz "rnrlmtqdqlb6"
    .asciiz "sixeightzgbf788five"
    .asciiz "sixgnlbxrfrc1jseightsixeight"
    .asciiz "nzxgkcfive44tkblnn58jbmdg"
    .asciiz "49fivefgsk"
    .asciiz "one8zqztmlmss6fiveznccsnnnzqk"
    .asciiz "6fivesevenfiveqrvlmdjvjxzvsix"
    .asciiz "sxdgthcx9"
    .asciiz "93qlthreefivezmk"
    .asciiz "xvsrgcsqbsqhdnqhbmcgn39ninesixszgtlslqb5"
    .asciiz "7sevenfourrpfqkkrm5"
    .asciiz "vcmfthdpkzsjpjt5six"
    .asciiz "zqtrk35lvsg1jkdfour5"
    .asciiz "7threegqzhcnxcmcrpgjkttbmxq5"
    .asciiz "2four25seveneight9"
    .asciiz "3h"
    .asciiz "xcspfcvfive37three7three"
    .asciiz "nbsnvhg197csnine8gfttndsf"
    .asciiz "xzztbq981vfbcmrv6ddrhrnprrnj"
    .asciiz "5kv672fpd"
    .asciiz "two2nine4fourl9foursix"
    .asciiz "ghngfb2four67qsfhpsb"
    .asciiz "4ninetwobcr49sixfive5"
    .asciiz "2threethree7onefour4"
    .asciiz "824zpsjjm"
    .asciiz "four6twosevenqbmzone4fourph"
    .asciiz "ctvmbrvksix18kz"
    .asciiz "eightfive9twokrpsltfhkjkjkdqlszzs4glxxtgktsx"
    .asciiz "2two7hxrncxqeight"
    .asciiz "6121two46"
    .asciiz "fivefourthreefivemkmb5fourmqfhmlrxmm"
    .asciiz "fiveonefivevbtbzrone9tsix"
    .asciiz "oneonethree5sgs9"
    .asciiz "cdvrrsm53qfvdzhvnlprvfjcx"
    .asciiz "jtflvmkdnineone62klbvbzzltscsvmbsbp7"
    .asciiz "3mjmrxl3fourqfqhrknblcthreelfmm"
    .asciiz "seven1vjlvfmh5flmnhfzsixfbdsjdkxqhvmj"
    .asciiz "sixfourninefiveoneklpsgrtthree5zcpxs"
    .asciiz "eight73pjvcbb"
    .asciiz "gdgbgzdlgjt9hklsxglkrtwo1nchtbvltmxnzn"
    .asciiz "87sixkfmrdmdx"
    .asciiz "jrpjxhqkleightttpkqqrtzvb5threerx"
    .asciiz "xdrjhrrnmnblnbtone8one"
    .asciiz "618gnvslkkmm8"
    .asciiz "tqrctvjjdone39"
    .asciiz "6zs9lninekjbrm1twosix"
    .asciiz "23mxsmvfthreefourkhvxmqg"
    .asciiz "onemkhn4seven3mtphqnqb"
    .asciiz "one5foursevenfivezpgvjmdhl"
    .asciiz "2mskpg1threevdjjlzbrbsevengfgmqvd"
    .asciiz "1hrrxgxgzhj2eightfive"
    .asciiz "rlleightwo2vfq"
    .asciiz "2gss"
    .asciiz "4lndrzf7vcfffcb"
    .asciiz "four5one"
    .asciiz "three5lxddbbpccp6kkpgxm"
    .asciiz "sixcbqfivesixzfgbzszq3tqcfqk"
    .asciiz "8xpsixrcfoursixfkxh"
    .asciiz "rqrtwojhcfive89fourthree"
    .asciiz "5ninesixknjmlcjmnsmv2"
    .asciiz "18zgjpthfsix2ncmdfkcsq3"
    .asciiz "tsxbfgzhjr55seventhreesxnnjhninefive"
    .asciiz "three61rqljxqdbch"
    .asciiz "threelhqzdvxnsgkmthmbd7"
    .asciiz "54two5dnhx5"
    .asciiz "btc4ggbfmtfscgzfourtwothreeqptmrn"
    .asciiz "rvqkbtvg331nine"
    .asciiz "2fourkrgdhvkgzrhvqonefive"
    .asciiz "7twoxkcpbfxthree"
    .asciiz "bmzczfl54oneeightqslllrcjkm"
    .asciiz "sbjgbkn89"
    .asciiz "9rpq83seven"
    .asciiz "fiveqmqklgxkqrrckkjqsxkkfjzzdml87seven"
    .asciiz "74one27"
    .asciiz "45four3"
    .asciiz "pbhcrscll27five5"
    .asciiz "7bbmjqlxv1dbdsvsc"
    .asciiz "sevenrhqt9sixthreethree"
    .asciiz "4sr8five"
    .asciiz "kc1"
    .asciiz "1eightlkjrvmpt4sixtwo"
    .asciiz "1oneddzcqhmgd6"
    .asciiz "feight6tmqcj4four"
    .asciiz "five9mj7mgjqfhshvhxskjsix8"
    .asciiz "six99eightg42"
    .asciiz "vfhvmxnvhxnonekrhfzqpseven27"
    .asciiz "866three"
    .asciiz "eight5one118"
    .asciiz "clqlseveneight8dbrqdlcf7"
    .asciiz "9mnlgvcfmlrsrxfp7six"
    .asciiz "8mzlgnnqddptwoone"
    .asciiz "3bqckbeighteightthreesevensltsixf"
    .asciiz "eightfive37688eighteightwof"
    .asciiz "sixfour2one4zzqtdp"
    .asciiz "mkx1twofourxseven67"
    .asciiz "1jhcktvgninethreexdmfqdbjxltzj7rhkdbvf3"
    .asciiz "two16"
    .asciiz "5443"
    .asciiz "1three52nine7threemszlkc"
    .asciiz "jsgqfbhmcmtjmxkq1brl9eight6"
    .asciiz "fzvgmbbeight8"
    .asciiz "861snhtzkvcpnr4"
    .asciiz "b6kpxgcv71six1"
    .asciiz "c5four7vcnqhd84threefsklxc"
    .asciiz "lcpdthree2three9three"
    .asciiz "kljtp912sevenctg"
    .asciiz "241zlv59sevenqdbvddmrhtfgrhxgxmb"
    .asciiz "hksp3gdmcldnvbts1"
    .asciiz "xvcpr86btlptpnphhsix5fivenine"
    .asciiz "fivehgtmtxtwothree1seven"
    .asciiz "fpjpnrtpthreegjmfsjpcsix4twoonejqrr9"
    .asciiz "2hsrckv4639six3"
    .asciiz "fourtwofour3"
    .asciiz "2kggzqfourfourseven"
    .asciiz "three526seven6gbmjbqkncg"
    .asciiz "crstsqhvt98rhzvhsshthreebj"
    .asciiz "xbhcfqvplfive9one77"
    .asciiz "7256hlnmqlhth"
    .asciiz "5rttvcfhbjzoneqdbhvtwoneb"
    .asciiz "7mxgmsvxzzsevenclzbcq3twos"
    .asciiz "xcmpjgk9"
    .asciiz "eight5cnntwopzjrmgbhq"
    .asciiz "rvbfnddhg25lpthcsfxfdkmseven"
    .asciiz "eight82cppmnpvkvthreesevenseven8h"
    .asciiz "fourhmpknkfdtwogfhrgthree84"
    .asciiz "6six3599fivejhmjzdzsr"
    .asciiz "sevenbngxnjljfivegcvtmnt5k1"
    .asciiz "twoone58nine"
    .asciiz "29jfctbqssvrtwothreeg"
    .asciiz "84kkjdjjp"
    .asciiz "threektqgtgcrccbsnsqpcfxtb3vxtdfour2hgvdg"
    .asciiz "6fivejttmkvvpntvqlfpbjbcfkcztltwosix"
    .asciiz "twoseven7qkhzqlx9four"
    .asciiz "ktnxrj2sixsevenrcnqbksgbgdfxrdqgz"
    .asciiz "236four"
    .asciiz "grbhpnjrtvrbslnfgthree47vbpncxqfourfp"
    .asciiz "5sevenkrlmnrjsix4"
    .asciiz "5fivekgsxtbvkk"
    .asciiz "2two4"
    .asciiz "lkrjlsz7mgv9525p1"
    .asciiz "nineonebmfdxxfqvvkrblrd9"
    .asciiz "5six6cvmqttbsxkzg"
    .asciiz "42seven13four4"
    .byte $ED
