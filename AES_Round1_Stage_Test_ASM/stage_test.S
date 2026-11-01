/* Functional test, classic Arduino Uno / ATmega328P at 16 MHz.
 * One uppercase 'S' -> one new plaintext -> initial XOR + first AES round.
 * All state transitions and snapshots are assembly; Arduino handles Serial.
 * No measurement trigger, repeated encryption, or 10 ms measurement delays.
 * r1 remains zero; only AVR-GCC call-clobbered registers are changed.
 */
#if !defined(__AVR_ATmega328P__) || F_CPU != 16000000L
#error "Select classic Arduino Uno: ATmega328P at 16 MHz."
#endif

.section .bss
.global state, pt, round_keys, stage_states
state:        .skip 16
pt:           .skip 16
round_keys:   .skip 32
/* Blocks 0..4: initial AddRoundKey, SubBytes, ShiftRows, MixColumns, key 1. */
stage_states: .skip 80

.section .data
.global xorshift_state
xorshift_state: .long 12345

.section .text
.macro PRINT label
    ldi r24, lo8(\label)
    ldi r25, hi8(\label)
    call fw_print_flash
.endm
.macro OUTPUT label, data
    PRINT \label
    ldi r24, lo8(\data)
    ldi r25, hi8(\data)
    call print_hex16_asm
    call fw_newline
.endm

.global stage_test_setup
.type stage_test_setup, @function
stage_test_setup:
    call fw_serial_begin
    /* Load only the given master key. Derive round 1 below. */
    ldi r30, lo8(master_key)
    ldi r31, hi8(master_key)
    ldi r26, lo8(round_keys)
    ldi r27, hi8(round_keys)
    ldi r18, 16
1:  lpm r19, Z+
    st X+, r19
    dec r18
    brne 1b
    call expand_round1_key_asm
    PRINT msg_ready
    PRINT msg_prompt
    ret
.size stage_test_setup, .-stage_test_setup

.global stage_test_loop
.type stage_test_loop, @function
stage_test_loop:
    call fw_serial_available
    tst r24
    brne 1f
    ret
1:  call fw_serial_read
    cpi r24, 'S'
    breq 2f
    ret
2:  /* PRNG state is never reset here: each S consumes the next 16 bytes. */
    ldi r26, lo8(pt)
    ldi r27, hi8(pt)
    ldi r18, 16
.Lnew_plaintext:
    push r26
    push r27
    push r18
    call xorshift32_asm
    pop r18
    pop r27
    pop r26
    st X+, r24
    dec r18
    brne .Lnew_plaintext
    ldi r26, lo8(pt)
    ldi r27, hi8(pt)
    ldi r30, lo8(state)
    ldi r31, hi8(state)
    ldi r18, 16
3:  ld r19, X+
    st Z+, r19
    dec r18
    brne 3b
    call run_round_with_snapshots_asm

    /* Print saved blocks after the complete round; no Serial calls in AES. */
    PRINT msg_header
    OUTPUT msg_plaintext, pt
    OUTPUT msg_key0, round_keys
    OUTPUT msg_key1, round_keys+16
    OUTPUT msg_initial, stage_states
    OUTPUT msg_subbytes, stage_states+16
    OUTPUT msg_shiftrows, stage_states+32
    OUTPUT msg_mixcolumns, stage_states+48
    OUTPUT msg_final, stage_states+64
    PRINT msg_done
    ret
.size stage_test_loop, .-stage_test_loop

.global run_round_with_snapshots_asm
.type run_round_with_snapshots_asm, @function
run_round_with_snapshots_asm:
    clr r24
    call add_round_key_asm
    clr r24
    call save_stage_asm
    call sub_bytes_asm
    ldi r24, 1
    call save_stage_asm
    call shift_rows_asm
    ldi r24, 2
    call save_stage_asm
    call mix_columns_asm
    ldi r24, 3
    call save_stage_asm
    ldi r24, 1
    call add_round_key_asm
    ldi r24, 4
    jmp save_stage_asm
.size run_round_with_snapshots_asm, .-run_round_with_snapshots_asm

/* r24=0..4: copy the current state to a separate 16-byte snapshot. */
.type save_stage_asm, @function
save_stage_asm:
    lsl r24
    lsl r24
    lsl r24
    lsl r24
    ldi r30, lo8(stage_states)
    ldi r31, hi8(stage_states)
    add r30, r24
    adc r31, r1
    ldi r26, lo8(state)
    ldi r27, hi8(state)
    ldi r18, 16
1:  ld r19, X+
    st Z+, r19
    dec r18
    brne 1b
    ret
.size save_stage_asm, .-save_stage_asm

/* AES-128 key schedule: K1 = K0 expanded once, Rcon = 0x01.
 * First word = K0[0..3] XOR SubWord(RotWord(K0[12..15])) XOR Rcon.
 * Remaining bytes K1[i] = K0[i] XOR K1[i-4].
 */
.type expand_round1_key_asm, @function
expand_round1_key_asm:
    lds r24, round_keys+13
    call lookup_sbox_asm
    lds r18, round_keys
    eor r24, r18
    ldi r18, 0x01
    eor r24, r18
    sts round_keys+16, r24
    lds r24, round_keys+14
    call lookup_sbox_asm
    lds r18, round_keys+1
    eor r24, r18
    sts round_keys+17, r24
    lds r24, round_keys+15
    call lookup_sbox_asm
    lds r18, round_keys+2
    eor r24, r18
    sts round_keys+18, r24
    lds r24, round_keys+12
    call lookup_sbox_asm
    lds r18, round_keys+3
    eor r24, r18
    sts round_keys+19, r24
    .irp index,4,5,6,7,8,9,10,11,12,13,14,15
        lds r18, round_keys+\index
        lds r19, round_keys+12+\index
        eor r18, r19
        sts round_keys+16+\index, r18
    .endr
    ret
.size expand_round1_key_asm, .-expand_round1_key_asm

/* r24 = input byte; return S-Box byte in r24. */
.type lookup_sbox_asm, @function
lookup_sbox_asm:
    ldi r30, lo8(sbox_std)
    ldi r31, hi8(sbox_std)
    add r30, r24
    adc r31, r1
    lpm r24, Z
    ret
.size lookup_sbox_asm, .-lookup_sbox_asm

/* r25:r24 = SRAM address. Print 16 uppercase bytes with spaces. */
.type print_hex16_asm, @function
print_hex16_asm:
    movw r26, r24
    ldi r18, 16
1:  ld r24, X+
    push r26
    push r27
    push r18
    push r24
    cpi r24, 0x10
    brsh 2f
    PRINT msg_zero
2:  pop r24
    call fw_print_hex
    pop r18
    pop r27
    pop r26
    dec r18
    breq 3f
    push r26
    push r27
    push r18
    PRINT msg_space
    pop r18
    pop r27
    pop r26
    rjmp 1b
3:  ret
.size print_hex16_asm, .-print_hex16_asm

.global xorshift32_asm
.type xorshift32_asm, @function
xorshift32_asm:
    lds r18, xorshift_state
    lds r19, xorshift_state+1
    lds r20, xorshift_state+2
    lds r21, xorshift_state+3
    movw r22, r18
    movw r24, r20
    ldi r26, 13
1:  lsl r22
    rol r23
    rol r24
    rol r25
    dec r26
    brne 1b
    eor r18, r22
    eor r19, r23
    eor r20, r24
    eor r21, r25
    movw r22, r18
    movw r24, r20
    ldi r26, 17
2:  lsr r25
    ror r24
    ror r23
    ror r22
    dec r26
    brne 2b
    eor r18, r22
    eor r19, r23
    eor r20, r24
    eor r21, r25
    movw r22, r18
    movw r24, r20
    ldi r26, 5
3:  lsl r22
    rol r23
    rol r24
    rol r25
    dec r26
    brne 3b
    eor r18, r22
    eor r19, r23
    eor r20, r24
    eor r21, r25
    sts xorshift_state, r18
    sts xorshift_state+1, r19
    sts xorshift_state+2, r20
    sts xorshift_state+3, r21
    mov r24, r18
    ret
.size xorshift32_asm, .-xorshift32_asm

/* Input r24 = round 0 or 1. Both keys remain in SRAM as in the original. */
.type add_round_key_asm, @function
add_round_key_asm:
    lsl r24
    lsl r24
    lsl r24
    lsl r24
    ldi r30, lo8(round_keys)
    ldi r31, hi8(round_keys)
    add r30, r24
    adc r31, r1
    ldi r26, lo8(state)
    ldi r27, hi8(state)
    ldi r20, 16
1:  ld r18, X
    ld r19, Z+
    eor r18, r19
    st X+, r18
    dec r20
    brne 1b
    ret
.size add_round_key_asm, .-add_round_key_asm

.type sub_bytes_asm, @function
sub_bytes_asm:
    ldi r26, lo8(state)
    ldi r27, hi8(state)
    ldi r20, 16
1:  ld r18, X
    ldi r30, lo8(sbox_std)
    ldi r31, hi8(sbox_std)
    add r30, r18
    adc r31, r1
    lpm r19, Z
    st X+, r19
    dec r20
    brne 1b
    ret
.size sub_bytes_asm, .-sub_bytes_asm

.type shift_rows_asm, @function
shift_rows_asm:
    lds r18, state+1
    lds r19, state+5
    sts state+1, r19
    lds r19, state+9
    sts state+5, r19
    lds r19, state+13
    sts state+9, r19
    sts state+13, r18
    lds r18, state+2
    lds r19, state+10
    sts state+2, r19
    sts state+10, r18
    lds r18, state+6
    lds r19, state+14
    sts state+6, r19
    sts state+14, r18
    lds r18, state+15
    lds r19, state+11
    sts state+15, r19
    lds r19, state+7
    sts state+11, r19
    lds r19, state+3
    sts state+7, r19
    sts state+3, r18
    ret
.size shift_rows_asm, .-shift_rows_asm

.macro XTIME value, scratch
    mov \scratch, \value
    lsl \value
    sbrc \scratch, 7
    eor \value, r25
.endm

/* Equivalent AES column: out[i] = a[i] ^ t ^ xtime(a[i]^a[i+1]). */
.type mix_columns_asm, @function
mix_columns_asm:
    ldi r26, lo8(state)
    ldi r27, hi8(state)
    ldi r31, 4
    ldi r25, 0x1b
1:  ld r18, X+
    ld r19, X+
    ld r20, X+
    ld r21, X+
    sbiw r26, 4
    mov r22, r18
    eor r22, r19
    eor r22, r20
    eor r22, r21
    mov r23, r18
    eor r23, r19
    XTIME r23, r24
    eor r23, r18
    eor r23, r22
    st X+, r23
    mov r23, r19
    eor r23, r20
    XTIME r23, r24
    eor r23, r19
    eor r23, r22
    st X+, r23
    mov r23, r20
    eor r23, r21
    XTIME r23, r24
    eor r23, r20
    eor r23, r22
    st X+, r23
    mov r23, r21
    eor r23, r18
    XTIME r23, r24
    eor r23, r21
    eor r23, r22
    st X+, r23
    dec r31
    brne 1b
    ret
.size mix_columns_asm, .-mix_columns_asm


.section .progmem.data, "a", @progbits
master_key:
    .byte 0x2b,0x7e,0x15,0x16,0x28,0xae,0xd2,0xa6
    .byte 0xab,0xf7,0x15,0x88,0x09,0xcf,0x4f,0x3c
sbox_std:
    .byte 0x63,0x7c,0x77,0x7b,0xf2,0x6b,0x6f,0xc5,0x30,0x01,0x67,0x2b,0xfe,0xd7,0xab,0x76
    .byte 0xca,0x82,0xc9,0x7d,0xfa,0x59,0x47,0xf0,0xad,0xd4,0xa2,0xaf,0x9c,0xa4,0x72,0xc0
    .byte 0xb7,0xfd,0x93,0x26,0x36,0x3f,0xf7,0xcc,0x34,0xa5,0xe5,0xf1,0x71,0xd8,0x31,0x15
    .byte 0x04,0xc7,0x23,0xc3,0x18,0x96,0x05,0x9a,0x07,0x12,0x80,0xe2,0xeb,0x27,0xb2,0x75
    .byte 0x09,0x83,0x2c,0x1a,0x1b,0x6e,0x5a,0xa0,0x52,0x3b,0xd6,0xb3,0x29,0xe3,0x2f,0x84
    .byte 0x53,0xd1,0x00,0xed,0x20,0xfc,0xb1,0x5b,0x6a,0xcb,0xbe,0x39,0x4a,0x4c,0x58,0xcf
    .byte 0xd0,0xef,0xaa,0xfb,0x43,0x4d,0x33,0x85,0x45,0xf9,0x02,0x7f,0x50,0x3c,0x9f,0xa8
    .byte 0x51,0xa3,0x40,0x8f,0x92,0x9d,0x38,0xf5,0xbc,0xb6,0xda,0x21,0x10,0xff,0xf3,0xd2
    .byte 0xcd,0x0c,0x13,0xec,0x5f,0x97,0x44,0x17,0xc4,0xa7,0x7e,0x3d,0x64,0x5d,0x19,0x73
    .byte 0x60,0x81,0x4f,0xdc,0x22,0x2a,0x90,0x88,0x46,0xee,0xb8,0x14,0xde,0x5e,0x0b,0xdb
    .byte 0xe0,0x32,0x3a,0x0a,0x49,0x06,0x24,0x5c,0xc2,0xd3,0xac,0x62,0x91,0x95,0xe4,0x79
    .byte 0xe7,0xc8,0x37,0x6d,0x8d,0xd5,0x4e,0xa9,0x6c,0x56,0xf4,0xea,0x65,0x7a,0xae,0x08
    .byte 0xba,0x78,0x25,0x2e,0x1c,0xa6,0xb4,0xc6,0xe8,0xdd,0x74,0x1f,0x4b,0xbd,0x8b,0x8a
    .byte 0x70,0x3e,0xb5,0x66,0x48,0x03,0xf6,0x0e,0x61,0x35,0x57,0xb9,0x86,0xc1,0x1d,0x9e
    .byte 0xe1,0xf8,0x98,0x11,0x69,0xd9,0x8e,0x94,0x9b,0x1e,0x87,0xe9,0xce,0x55,0x28,0xdf
    .byte 0x8c,0xa1,0x89,0x0d,0xbf,0xe6,0x42,0x68,0x41,0x99,0x2d,0x0f,0xb0,0x54,0xbb,0x16
msg_ready:     .asciz "AES first-round stage test (AVR assembly).\r\n"
msg_prompt:    .asciz "Send 'S' for one new plaintext. Reset repeats the initial sequence.\r\n"
msg_header:    .asciz "\r\n=== AES-128 Round 1: one plaintext ===\r\n"
msg_plaintext: .asciz "Plaintext                : "
msg_key0:      .asciz "Key (Round 0)            : "
msg_key1:      .asciz "Key (Round 1)            : "
msg_initial:   .asciz "Initial AddRoundKey (R0) : "
msg_subbytes:  .asciz "SubBytes (R1)            : "
msg_shiftrows: .asciz "ShiftRows (R1)           : "
msg_mixcolumns:.asciz "MixColumns (R1)          : "
msg_final:     .asciz "AddRoundKey (R1)         : "
msg_done:      .asciz "Done. Send 'S' for a new plaintext.\r\n"
msg_zero:      .asciz "0"
msg_space:     .asciz " "
