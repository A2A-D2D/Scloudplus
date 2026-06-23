#include <stdio.h>
#include <string.h>
#include "../include/scloudplus_hal.h"
int main() {
    hal_init("sw");
    uint8_t msg[8] = {0x12, 0x34, 0x56, 0x78, 0x9A, 0xBC, 0xDE, 0xF0};
    uint16_t enc_q[32];
    hal_msgencode_block(msg, 3, enc_q);
    printf("SW encode Q values:\n");
    for (int i = 0; i < 32; i++) printf("  Q[%d] = %03x\n", i, enc_q[i]);
    /* Read RTL output */
    FILE *f0 = fopen("../tb/kem/vec_q_hw0.mem", "r");
    FILE *f1 = fopen("../tb/kem/vec_q_hw1.mem", "r");
    uint16_t hw_q[32];
    int ok = 1;
    for (int i = 0; i < 16; i++) {
        unsigned int v;
        if (fscanf(f0, "%x", &v) == 1) hw_q[i] = v & 0xFFF;
        if (fscanf(f1, "%x", &v) == 1) hw_q[16+i] = v & 0xFFF;
    }
    fclose(f0); fclose(f1);
    printf("\nRTL encode Q values:\n");
    for (int i = 0; i < 32; i++) printf("  Q[%d] = %03x\n", i, hw_q[i]);
    printf("\nComparison:\n");
    for (int i = 0; i < 32; i++) {
        if (enc_q[i] != hw_q[i]) {
            printf("  Q[%d]: SW=%03x HW=%03x MISMATCH!\n", i, enc_q[i], hw_q[i]);
            ok = 0;
        }
    }
    if (ok) printf("  ALL 32 Q VALUES MATCH! HW == SW\n");
    hal_deinit();
    return ok ? 0 : 1;
}
