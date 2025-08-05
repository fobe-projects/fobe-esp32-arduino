#include "esp32-hal-gpio.h"
#include "pins_arduino.h"

extern "C" {

void initVariant(void) {
  pinMode(PIN_PERI_EN, OUTPUT);
  digitalWrite(PIN_PERI_EN, HIGH);

  pinMode(PIN_OLED_EN, OUTPUT);
  digitalWrite(PIN_OLED_EN, HIGH);
}
}
