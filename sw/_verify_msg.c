#include <stdio.h>
#include <string.h>
#include "../include/scloudplus_hal.h"
int main() {
    hal_init("sw");
    uint8_t msg[8] = {0x12, 0x34, 0x56, 0x78, 0x9A, 0xBC, 0xDE, 0xF0};
    
    /* SW roundtrip */
    uint16_t sw_q[32], sw_rq[32];
    uint8_t sw_dec[8];
    hal_msgencode_block(msg, 3, sw_q);
    hal_msgdecode_block(sw_q, 3, sw_rq, sw_dec);
    printf("SW roundtrip: %s\n", memcmp(msg, sw_dec, 8)==0 ? "PASS" : "FAIL");
    
    /* HW roundtrip */
    FILE *f0 = fopen("../tb/kem/vec_q_hw0.mem", "r");
    FILE *f1 = fopen("../tb/kem/vec_q_hw1.mem", "r");
    uint16_t hw_q[32], hw_rq[32];
    uint8_t hw_dec[8];
    for (int i = 0; i < 16; i++) {
        unsigned int v;
        if (fscanf(f0, "%x", &v)==1) hw_q[i] = v & 0xFFF;
        if (fscanf(f1, "%x", &v)==1) hw_q[16+i] = v & 0xFFF;
    }
    fclose(f0); fclose(f1);
    
    /* HW decode via SW BDD (cross-check) */
    hal_msgdecode_block(hw_q, 3, hw_rq, hw_dec);
    printf("HW→SW BDD roundtrip: %s\n", memcmp(msg, hw_dec, 8)==0 ? "PASS" : "FAIL");
    
    /* Read HW decoded msg from RTL output */
    FILE *fm = fopen("../tb/kem/vec_msg_hw.mem", "r");
    uint8_t hw_raw[8];
    for (int i=0;i<8;i++) { unsigned int v; fscanf(fm,"%x",&v); hw_raw[i]=v&0xFF; }
    fclose(fm);
    printf("RTL decoded msg: %02x %02x %02x %02x %02x %02x %02x %02x\n",
           hw_raw[0],hw_raw[1],hw_raw[2],hw_raw[3],hw_raw[4],hw_raw[5],hw_raw[6],hw_raw[7]);
    printf("RTL roundtrip: %s\n", memcmp(msg, hw_raw, 8)==0 ? "PASS" : "FAIL");
    
    hal_deinit();
    return 0;
}
