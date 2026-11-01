#include <Arduino.h>

// Arduino serial bridge only. AES, plaintext generation and sequencing are .S.
extern "C" {
void stage_test_setup();
void stage_test_loop();
// Explicit declarations also keep Arduino's auto-prototypes from changing linkage.
void fw_serial_begin();
uint8_t fw_serial_available();
int fw_serial_read();
void fw_print_flash(const char *text);
void fw_print_hex(uint8_t value);
void fw_newline();

void fw_serial_begin() { Serial.begin(115200); }
uint8_t fw_serial_available() { return Serial.available() > 0; }
int fw_serial_read() { return Serial.read(); }
void fw_print_flash(const char *text) {
  Serial.print(reinterpret_cast<const __FlashStringHelper *>(text));
}
void fw_print_hex(uint8_t value) { Serial.print(value, HEX); }
void fw_newline() { Serial.println(); }
}

void setup() { stage_test_setup(); }
void loop() { stage_test_loop(); }
