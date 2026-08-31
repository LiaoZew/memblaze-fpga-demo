/*
 * MemBlaze xc7k325tffg900-2 - MicroBlaze LED demo (Vitis standalone)
 *
 * Minimal AXI example: the MicroBlaze soft-core writes the AXI GPIO
 * register through the AXI-Lite interface to control the 3 LEDs.
 *
 * LED mapping (hardware):  gpio bit0 -> LED_G (R24)
 *                          gpio bit1 -> LED_Y (T20)
 *                          gpio bit2 -> LED_R (T21)
 * 1 = on (if polarity is inverted on the board, flip the values).
 */
#include "xparameters.h"
#include "xgpio.h"
#include "xil_printf.h"
#include "sleep.h"

#define GPIO_DEVICE_ID  XPAR_AXI_GPIO_0_DEVICE_ID
#define LED_CHANNEL     1   /* AXI GPIO channel 1 */

static XGpio gpio;

int main(void)
{
    u32 value = 0;

    XGpio_Initialize(&gpio, GPIO_DEVICE_ID);
    XGpio_SetDataDirection(&gpio, LED_CHANNEL, 0x0);   /* all outputs */

    xil_printf("MicroBlaze LED demo: writing AXI GPIO...\r\n");

    while (1) {
        /* all three LEDs on */
        XGpio_DiscreteWrite(&gpio, LED_CHANNEL, 0x7);
        usleep(500000);

        /* all off */
        XGpio_DiscreteWrite(&gpio, LED_CHANNEL, 0x0);
        usleep(500000);

        /* G + R (bit0|bit2) */
        XGpio_DiscreteWrite(&gpio, LED_CHANNEL, 0x5);
        usleep(500000);
    }

    return 0;
}