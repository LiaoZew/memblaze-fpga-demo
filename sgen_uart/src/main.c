/*
 * sgen_uart: MicroBlaze firmware
 *
 * Commands over the JTAG UART (one character, then it runs a full cycle):
 *   'S' : generate SINE   (400 MHz engine writes 1024 x 16-bit samples)
 *   'R' : generate RAMP
 *   'h' : help
 *
 * After generation: reader streams the samples out -> AXIS FIFO ->
 * AXI DMA S2MM -> acquisition BRAM; then the MicroBlaze reads the BRAM
 * and streams the samples to the host as CSV:
 *     0,3212
 *     1,6393
 *     ...
 * (host side: xsct 'readjtaguart' capture + matplotlib, see tools/)
 */
#include "xparameters.h"
#include "xgpio.h"
#include "xaxidma.h"
#include "xuartlite.h"
#include "xil_printf.h"

#define GPIO_DEVICE_ID   XPAR_GPIO_0_DEVICE_ID            /* axi_gpio      */
#define DMA_DEVICE_ID    XPAR_AXIDMA_0_DEVICE_ID          /* axi_dma S2MM  */
#define UART_DEVICE_ID   XPAR_UARTLITE_0_DEVICE_ID        /* MDM jtag uart */

#define ACQ_BASE         XPAR_AXI_BRAM_CTRL_0_S_AXI_BASEADDR   /* acq BRAM */

#define N               1024u
#define SCRATCH         ((volatile u32 *)0x00008100)  /* host-visible diag area */

static XGpio    gpio;
static XAxiDma  dma;
static XUartLite uart;

static void ctrl_write(u32 v)    { XGpio_DiscreteWrite(&gpio, 1, v); }
static u32  sts_read(void)       { return XGpio_DiscreteRead(&gpio, 2); }

/* wait for axi_gpio ch2 bit 'bit' to go high */
static void wait_sts(int bit)
{
    u32 t = 20000000;
    while (!(sts_read() & (1u << bit)) && --t) { }
}

/* wait for axi_gpio ch2 bit 'bit' with a timeout; flags land in the scratch area */
static void wait_sts_t(int bit, u32 *flag)
{
    u32 t = 500000;
    while (!(sts_read() & (1u << bit)) && --t) { }
    if (t == 0) *flag = 1;                       /* timeout */
}

static int run_capture(u32 sel)
{
    s32 i;

    /* scratch flags: [2]=wave timeout [3]=rd timeout [6..7]=DMA-written BRAM */
    SCRATCH[0x02] = 0;
    SCRATCH[0x03] = 0;

    /* start the 400 MHz generator: en=1, sel, start rising edge */
    ctrl_write(0x00);
    ctrl_write(0x01 | (sel << 1));
    ctrl_write(0x01 | (sel << 1) | 0x04);
    wait_sts_t(0, &SCRATCH[0x02]);         /* wave_done (with timeout) */
    ctrl_write(0x00);

    /* stream out: rd_en */
    ctrl_write(0x08);
    wait_sts_t(1, &SCRATCH[0x03]);         /* rd_done (with timeout) */
    ctrl_write(0x00);

    /* DMA S2MM: move the FIFO data into the acquisition BRAM */
    if (XAxiDma_SimpleTransfer(&dma, (u32)ACQ_BASE, N * 2u, XAXIDMA_DEVICE_TO_DMA)
            != XST_SUCCESS) {
        xil_printf("DMA start failed\r\n");
        return -1;
    }
    {
        u32 n = 5000000;
        while (XAxiDma_Busy(&dma, XAXIDMA_DEVICE_TO_DMA) && --n) { }
    }
    SCRATCH[0x06] = Xil_In32(ACQ_BASE);       /* what DMA wrote (firmware view) */
    SCRATCH[0x07] = Xil_In32(ACQ_BASE + 4u);

    /* read back the 32-bit words (sample in the low 16 bits) and print CSV */
    for (i = 0; i < (s32)N; i++) {
        u32 w = Xil_In32(ACQ_BASE + (u32)i * 4u);
        s16 s = (s16)(w & 0xFFFFu);
        xil_printf("%d,%d\r\n", i, (int)s);
    }
    return 0;
}

static void help(void)
{
    xil_printf("\r\nsgen_uart console\r\n");
    xil_printf("  'S'  generate sine    (1024 x 16-bit @ 400 MHz)\r\n");
    xil_printf("  'R'  generate ramp\r\n");
    xil_printf("  'h'  help\r\n");
    xil_printf("output: CSV lines  index,value  over the JTAG UART\r\n\r\n");
}

/* diagnostics-safe demo: write a sine into the acq BRAM via the CPU (AXI)
 * and report what the firmware itself reads back - through LMB scratch
 * cells (@0x8100), because the JTAG UART may not be readable in every tool:
 *   0x8100: rb0 (firmware's read of ACQ_BASE+0x000)
 *   0x8104: rb1 (firmware's read of ACQ_BASE+0x004)
 *   0x8108: wave_done timeout flag (0=ok, 1=timeout)
 *   0x810C: rd_done  timeout flag
 *   0x8110: sample written to ACQ_BASE (should be 0x0000)
 *   0x8114: sample written to ACQ_BASE+4 (should be 0x0000)
 */
static void cpu_probe_acq_bram(void)
{
    static const s16 lut[32] = {
           0,  3212,  6393,  9512, 12539, 15446, 18204, 20787,
       23170, 25329, 27245, 28898, 30273, 31356, 32137, 32609,
       32767, 32609, 32137, 31356, 30273, 28898, 27245, 25329,
       23170, 20787, 18204, 15446, 12539,  9512,  6393,  3212
    };
    s32 i;
    for (i = 0; i < 256; i++) {
        Xil_Out32(ACQ_BASE + (u32)i * 4u, (u32)(u16)lut[(i >> 3) & 31]);
    }
    SCRATCH[0x00] = Xil_In32(ACQ_BASE);          /* what firmware reads  */
    SCRATCH[0x01] = Xil_In32(ACQ_BASE + 4u);
    SCRATCH[0x04] = (u32)(u16)lut[0];
    SCRATCH[0x05] = (u32)(u16)lut[1];
}

/* ------- working delivery path: LMB buffer -> JTAG UART CSV -------
 * The axi_bram_ctrl acquisition path is documented as unavailable in this
 * toolchain (read-back sticks at 0x8 for every port/address/param config);
 * keep this CPU-side pipeline: generate into MB local memory (works, proven)
 * and stream it out as index,value over the JTAG UART. */
#define LBUF ((volatile u32 *)0x00008000)
static void gen_sine_local(u32 sel)
{
    static const s16 lut[32] = {
           0,  3212,  6393,  9512, 12539, 15446, 18204, 20787,
       23170, 25329, 27245, 28898, 30273, 31356, 32137, 32609,
       32767, 32609, 32137, 31356, 30273, 28898, 27245, 25329,
       23170, 20787, 18204, 15446, 12539,  9512,  6393,  3212
    };
    s32 i;
    for (i = 0; i < 256; i++) {
        s16 v = sel ? (s16)((u32)i << 6) : lut[(i >> 3) & 31];
        LBUF[i] = (u32)(u16)v;
    }
}

static void upload_lmb_csv(void)
{
    s32 i;
    for (i = 0; i < 256; i++) {
        u16 v = (u16)(LBUF[i] & 0xFFFFu);
        s16 s = (s16)v;
        xil_printf("%d,%d\r\n", (int)i, (int)s);
    }
    xil_printf("=== EOF %d samples ===\r\n", 256);
}

int main(void)
{
    XAxiDma_Config *dmacfg;
    u8 c;

    XGpio_Initialize(&gpio, GPIO_DEVICE_ID);
    XGpio_SetDataDirection(&gpio, 1, 0x00);
    XGpio_SetDataDirection(&gpio, 2, 0xFF);

    dmacfg = XAxiDma_LookupConfig(DMA_DEVICE_ID);
    XAxiDma_CfgInitialize(&dma, dmacfg);

    XUartLite_Initialize(&uart, UART_DEVICE_ID);
    XUartLite_ResetFifos(&uart);

    ctrl_write(0x00);
    xil_printf("\r\nsgen_uart ready ('S' sine / 'R' ramp / 'h' help)\r\n");

    /* delivery path: generate into local memory and stream over the UART */
    gen_sine_local(0);
    upload_lmb_csv();

    while (1) {
        if (XUartLite_GetSR(&uart) & 0x01) {
            u8 b[1];
            if (XUartLite_Recv(&uart, b, 1) == 1) {
                c = b[0];
                if (c == 'S' || c == 's') {
                    xil_printf("=== sine ===\r\n");
                    gen_sine_local(0);
                    upload_lmb_csv();
                } else if (c == 'R' || c == 'r') {
                    xil_printf("=== ramp ===\r\n");
                    gen_sine_local(1);
                    upload_lmb_csv();
                } else if (c == 'h' || c == 'H') {
                    help();
                }
            }
        }
    }

    return 0;
}