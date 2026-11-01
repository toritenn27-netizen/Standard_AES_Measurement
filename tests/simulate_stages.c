// Host-side simavr test; never compiled into the Arduino sketch.
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "sim_avr.h"
#include "sim_elf.h"
#include "sim_io.h"
#include "avr_uart.h"

typedef struct {
    avr_t *avr;
    avr_irq_t *input;
    FILE *output;
    char line[512];
    size_t used;
    unsigned completed, requested, target, entered;
    int done, known_vector;
} context_t;

static uint16_t symbol(elf_firmware_t *fw, const char *name) {
    for (uint32_t i = 0; i < fw->symbolcount; ++i)
        if (!strcmp(fw->symbol[i]->symbol, name))
            return fw->symbol[i]->addr & 0xffff;
    fprintf(stderr, "Missing symbol: %s\n", name);
    exit(2);
}

static void send_command(context_t *ctx, int first) {
    // Only uppercase S must start a test. Other characters must be ignored.
    const char *bytes = first ? "sX\r\nS" : "S";
    while (*bytes) avr_raise_irq(ctx->input, (uint8_t)*bytes++);
    ++ctx->requested;
}

static void output_byte(struct avr_irq_t *irq, uint32_t value, void *param) {
    (void)irq;
    context_t *ctx = param;
    fputc(value & 255, ctx->output);
    if (ctx->used + 1 >= sizeof(ctx->line)) {
        fprintf(stderr, "Serial line overflow\n"); exit(2);
    }
    ctx->line[ctx->used++] = value & 255;
    ctx->line[ctx->used] = 0;
    if ((value & 255) != '\n') return;
    if (!strcmp(ctx->line, "Send 'S' for one new plaintext. Reset repeats the initial sequence.\r\n"))
        send_command(ctx, 1);
    if (!strcmp(ctx->line, "Done. Send 'S' for a new plaintext.\r\n")) {
        ++ctx->completed;
        if (ctx->completed == ctx->target) ctx->done = 1;
        else send_command(ctx, 0);
    }
    ctx->used = 0;
}

int main(int argc, char **argv) {
    if (argc != 4 && !(argc == 5 && !strcmp(argv[4], "--known-vector"))) {
        fprintf(stderr, "Usage: %s firmware.elf serial.log stats.json [--known-vector]\n", argv[0]);
        return 2;
    }
    elf_firmware_t fw = {0};
    if (elf_read_firmware(argv[1], &fw)) return 2;
    avr_t *avr = avr_make_mcu_by_name("atmega328p");
    if (!avr || avr_init(avr)) return 2;
    avr->frequency = 16000000;
    avr->log = LOG_ERROR;
    avr_load_firmware(avr, &fw);
    uint32_t flags = 0;
    avr_ioctl(avr, AVR_IOCTL_UART_SET_FLAGS('0'), &flags);
    context_t ctx = {.avr=avr, .known_vector=argc==5, .target=argc==5?1:100};
    ctx.output = fopen(argv[2], "wb");
    if (!ctx.output) return 2;
    ctx.input = avr_io_getirq(avr, AVR_IOCTL_UART_GETIRQ('0'), UART_IRQ_INPUT);
    avr_irq_register_notify(avr_io_getirq(avr, AVR_IOCTL_UART_GETIRQ('0'), UART_IRQ_OUTPUT), output_byte, &ctx);
    uint16_t round_pc = symbol(&fw, "run_round_with_snapshots_asm");
    uint16_t state_address = symbol(&fw, "state");
    uint16_t pt_address = symbol(&fw, "pt");
    const uint8_t fips_plaintext[16] = {
        0x32,0x43,0xf6,0xa8,0x88,0x5a,0x30,0x8d,
        0x31,0x31,0x98,0xa2,0xe0,0x37,0x07,0x34
    };
    while (!ctx.done && avr->cycle < 400000000ULL) {
        if (avr->pc == round_pc) {
            ++ctx.entered;
            if (ctx.known_vector && ctx.entered == 1) {
                // Inject a published vector into SRAM at the round boundary.
                // The firmware bytes, UART protocol and AES routines are unchanged.
                memcpy(avr->data+state_address, fips_plaintext, 16);
                memcpy(avr->data+pt_address, fips_plaintext, 16);
            }
        }
        int status = avr_run(avr);
        if (status == cpu_Done || status == cpu_Crashed) {
            fprintf(stderr, "Unexpected MCU halt %d pc=%x\n", status, avr->pc);
            return 1;
        }
    }
    if (!ctx.done || ctx.completed != ctx.target || ctx.entered != ctx.target) {
        fprintf(stderr, "Wrong test count / cycle timeout: requested=%u entered=%u completed=%u\n",
                ctx.requested, ctx.entered, ctx.completed);
        return 1;
    }
    // Once the last test is complete, idle without commands and detect reruns.
    avr_cycle_count_t idle_until = avr->cycle + 200000;
    while (avr->cycle < idle_until) {
        if (avr->pc == round_pc) { fprintf(stderr, "Unexpected automatic rerun\n"); return 1; }
        int status = avr_run(avr);
        if (status == cpu_Done || status == cpu_Crashed) return 1;
    }
    fclose(ctx.output);
    FILE *stats = fopen(argv[3], "w");
    if (!stats) return 2;
    fprintf(stats, "{\"requested\":%u,\"round_entries\":%u,\"completed\":%u,\"known_vector\":%s}\n",
            ctx.requested, ctx.entered, ctx.completed, ctx.known_vector ? "true" : "false");
    fclose(stats);
    avr_terminate(avr);
    return 0;
}
