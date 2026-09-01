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

static int run_capture(u32 sel)
{
    s32 i;

    /* reset controls */
    ctrl_write(0x00);
    /* start the 400 MHz generator: en=1, sel, start rising edge */
    ctrl_write(0x01 | (sel << 1));
    ctrl_write(0x01 | (sel << 1) | 0x04);
    wait_sts(0);                       /* wave_done */
    ctrl_write(0x00);                  /* drop en/start */

    /* stream out: rd_en */
    ctrl_write(0x08);
    wait_sts(1);                       /* rd_done */
    ctrl_write(0x00);

    /* DMA S2MM: move the FIFO data into the acquisition BRAM */
    if (XAxiDma_SimpleTransfer(&dma, (u32)ACQ_BASE, N * 2u, XAXIDMA_DEVICE_TO_DMA)
            != XST_SUCCESS) {
        xil_printf("DMA start failed\r\n");
        return -1;
    }
    while (XAxiDma_Busy(&dma, XAXIDMA_DEVICE_TO_DMA)) { }   /* wait done */

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

    /* demo: one sine cycle automatically on start (host only needs to watch) */
    xil_printf("=== sine (auto) ===\r\n");
    run_capture(0);

    while (1) {
        if (XUartLite_GetSR(&uart) & 0x01) {
            u8 b[1];
            if (XUartLite_Recv(&uart, b, 1) == 1) {
                c = b[0];
                if (c == 'S' || c == 's') {
                    xil_printf("=== sine ===\r\n");
                    run_capture(0);
                } else if (c == 'R' || c == 'r') {
                    xil_printf("=== ramp ===\r\n");
                    run_capture(1);
                } else if (c == 'h' || c == 'H') {
                    help();
                }
            }
        }
    }

    return 0;
}