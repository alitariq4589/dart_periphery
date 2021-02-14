// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:dart_periphery/dart_periphery.dart';

/// https://wiki.seeedstudio.com/Grove-Barometer_Sensor-BME280/
/// Grove - Temp&Humi&Barometer Sensor (BME280) is a breakout board for Bosch BMP280 high-precision,
/// low-power combined humidity, pressure, and temperature sensor
void main() {
  // Select the right I2C bus number /dev/i2c-0
  // 1 for Raspbery Pi, 0 for NanoPi
  var i2c = I2C(1);
  try {
    print('I2C info:' + i2c.getI2Cinfo());
    var bme280 = BME280(i2c);
    var r = bme280.getValues();
    print('Temperature [°] ' + r.temperature.toStringAsFixed(1));
    print('Humidity [%] ' + r.humidity.toStringAsFixed(1));
    print('Pressure [hPa] ' + r.pressure.toStringAsFixed(1));
  } finally {
    i2c.dispose();
  }
}
