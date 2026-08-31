/*
 * MemBlaze xc7k325tffg900-2 - MicroBlaze LED demo with JTAG UART console
 *
 * The MicroBlaze listens on the JTAG UART (built into the MDM, a virtual
 * serial console over the USB-JTAG cable) and changes the LEDs through the
 * AXI GPIO (AXI-Lite) interface.
 *
 * LED mapping:  bit0 -> LED_G (R24), bit1 -> LED_Y (T20), bit2 -> LED_R (T21)
 *
 * Commands (one character):
 *   '0'..'7'  set LED[2:0] to that value, e.g. '5' = bit0|bit2 = G+R on
 *   'G' 'g'   toggle LED_G
 *   'Y' 'y'   toggle LED_Y
 *   'R' 'r'   toggle LED_R
 *   'h' 'H'   print this help
 *
 * How to open the console (host side):
 *   Vitis / xsct -> Serial Terminal (JTAG UART / MDM), or xsdb:
 *     connect ; target ; terminal
 */
#include "xparameters.h"
#include "xgpio.h"
#include "xuartlite.h"
#include "xil_printf.h"
#include "sleep.h"

#define GPIO_DEVICE_ID   XPAR_AXI_GPIO_0_DEVICE_ID
#define UART_DEVICE_ID   XPAR_UARTLITE_0_DEVICE_ID
#define LED_CHANNEL      1

static XGpio    gpio;
static XUartLite uart;

static void set_leds(u32 v)
{
    XGpio_DiscreteWrite(&gpio, LED_CHANNEL, v);
}

static void show(u32 leds)
{
    xil_printf("LED[G Y R]=%d%d%d (0x%X)\r\n",
               (leds>>0)&1, (leds>>1)&1, (leds>>2)&1, leds);
}

static void help(void)
{
    xil_printf("\r\nMicroBlaze LED console\r\n");
    xil_printf("  '0'-'7' : set all LEDs to that value (bit0=G, bit1=Y, bit2=R)\r\n");
    xil_printf("  'G'     : toggle green LED\r\n");
    xil_printf("  'Y'     : toggle yellow LED\r\n");
    xil_printf("  'R'     : toggle red LED\r\n");
    xil_printf("  'h'     : this help\r\n\r\n");
}

int main(void)
{
    u32 leds = 0;
    u8 c;

    XGpio_Initialize(&gpio, GPIO_DEVICE_ID);
    XGpio_SetDataDirection(&gpio, LED_CHANNEL, 0x0);   /* all outputs */

    XUartLite_Initialize(&uart, UART_DEVICE_ID);
    XUartLite_ResetFifos(&uart);

    set_leds(0);
    xil_printf("\r\nMicroBlaze LED console ready (type 'h' for help)\r\n");
    show(leds);

    while (1) {
        /* uartlite status register: bit0 = receive data valid */
        if (XUartLite_GetSR(&uart) & 0x01) {
            u8 b[1];
            if (XUartLite_Recv(&uart, b, 1) == 1) {
                c = b[0];
                if (c >= '0' && c <= '7') {
                    leds = c - '0';
                    set_leds(leds);
                    show(leds);
                } else if (c == 'G' || c == 'g') {
                    leds ^= 1; set_leds(leds); show(leds);
                } else if (c == 'Y' || c == 'y') {
                    leds ^= 2; set_leds(leds); show(leds);
                } else if (c == 'R' || c == 'r') {
                    leds ^= 4; set_leds(leds); show(leds);
                } else if (c == 'h' || c == 'H') {
                    help(); show(leds);
                } else if (c != '\r' && c != '\n') {
                    xil_printf("unknown cmd '%c' ('h' for help)\r\n", c);
                }
            }
        }
        usleep(10000);
    }

    return 0;
}