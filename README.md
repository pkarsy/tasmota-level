# Tasmota-Level

A self-leveling/bubble level driver for Tasmota using Berry scripting and an IMU/accelerometer (QMI8658, MPU6050/9150/9250, LSM6DS3, ADXL345, BMI160 - more can be added easily).

## Overview

- **No recompilation required**: Install and configure without rebuilding Tasmota firmware. This is important as the support for MPU6050 and other IMUs exists but is not currently compiled in stock Tasmota builds.
- **Built-in calibration**: Calibrate the module (saved automatically to flash) to your specific mounting orientation. This makes the hardware installation much easier than bubble tilt sensors. You can mount the module in any orientation that is suitable.
- **Survives firmware updates**: Berry scripts persist across Tasmota updates

## Hardware Requirements

- ESP32-based module running Tasmota
- QMI8658, MPU6050/9150/9250, LSM6DS3, ADXL345, or BMI160 I2C accelerometer/gyroscope sensor. Only the accelerometer is used (so no gyro, DMP, interrupts etc).
- An enclosure or device where the ESP32 and the sensor are mounted. For example a heater(see below) or a fan.

## Warning for fake parts
Short answer: Use qmi8658.

Long answer: 
MPU6050 is EOL (for a long time) and most breakout boards on online stores have fake or recycled MPU6050 parts. The other parts can have similar problems (to a lesser degree, however), so purchasing through authorized distributors is a good strategy. The only part one can somewhat trust (no guarantees!) on Aliexpress/Ebay is QMI8658 because the original part is of very low cost, so the incentive of making LOWER cost fakes, is minimal (faking costs too!). To be fair I have purchased a lot of parts from Aliexpress (all the above brands), and seem to work OK.

## Wiring

| IMU breakout | ESP32 (WebInterface -> Config -> Module)|
|---------|-------|
| VCC     | 3.3V  or Config->Output Hi |
| GND     | GND or Config->Output Lo  |
| SCL     | I2C SCL |
| SDA     | I2C SDA |

It is very convenient to select pins on ESP that are nearby (Vcc-Gnd-Scl-Sda) using the Output Hi/Lo trick.

## Installation & Setup

### Step 1: Initial Setup (Interactive)

**First time only** - Tasmota Web Interface -> Tools -> Berry Console:
1. **Download the driver**:
   ```sh
   tasmota.urlfetch('https://raw.githubusercontent.com/pkarsy/tasmota-level/main/level.be')
   ```
2. **Load the driver interactively**:
   ```sh
   import level
   ```
   If a supported IMU is found, you'll see:
   ```
   LEVEL: MPU6050 found at 0x68
   LEVEL: No saved calibration found. Run: level.calibrate()
   ```
   If no IMU is found, you'll see:
   ```
   LEVEL: No supported IMU module found. Supported: QMI8658, MPU6050/9150/9250, LSM6DS3, ADXL345, BMI160
   ```

3. **Place your device in the "level" position** (the orientation you want to define as horizontal)
   The IMU must be well fixed inside the box, otherwise the calibration will not last.

4. **Calibrate**:
   ```sh
   level.calibrate()
   ```
   This measures the gravity vector and saves it to flash. The .calibrate() method is only for intercative use and is performed once. If however the internal orientation of the accellerometer changes due to hardware modifications, you have to recalibrate the device.

5. **Test the readings**:
   ```sh
   level.tilt()
   ```
   Should show 0 up to 1° when level, increasing as you tilt the device.

### Step 2: Auto-load on Boot
Having the driver loaded at boot and available as a global module helps to see possible problems early and to recalibrate the device if needed. Add to `autoexec.be`:

```sh
import level
```
OR even easier without leaving the Berry Console:
```sh
tasmota.urlfetch('https://raw.githubusercontent.com/pkarsy/tasmota-level/main/autoexec.be')
```

**Remember: The module must be calibrated to work properly.**

> **⚠️ IMPORTANT:** If no supported IMU is detected, `level` will be `nil`. Always check `if level != nil` before calling methods in production code.

On boot, the driver will:
- Scan for the accelerometer chip
- Load saved calibration from flash

## API Reference

### Main Functions

| Function | Returns | Description |
|----------|---------|-------------|
| `level.calibrate()` | `nil` | Calibrate device. Saves to flash. Prints the calibration vector. |
| `level.tilt()` | degrees or `nil` | Get tilt from vertical in degrees |
| `level.tilt_rad()` | radians or `nil` | Get tilt from vertical in radians |
| `level.set_calibration([cal_x, cal_y, cal_z])` | `true`/`false` | Apply calibration vector manually - probably you do not need this |

### Example Usage

```berry
# Get current tilt
var tilt = level.tilt()
if tilt != nil
  print('Tilt: ' + str(tilt) + ' degrees')
end

# Monitor the tilt and call a function when tilt() > 10deg
level.tilt_monitor(myfunction)
level.tilt_monitor(/->my.method())
# the heater app depends on this
```

## Heater Safety Controller

> **⚠️ WARNING:** Use of the Heater Safety Controller is at your own risk. See [LICENSE](LICENSE) for full disclaimer. The developer assumes no liability for any damages or injuries.

See `heater/` for a complete working example that uses this driver for heater safety (also fans etc):

- Stops the heater/prevents starting if tilted >10°
- 1-hour auto-timeout
- on/off pushbutton
- Please follow the safety caveats included in the heater README

## Contributing

This is a hobbyist project. Contributions welcome! Please test thoroughly and report issues.

## Tips
- Inside the box, make the USB port accessible (for easier recovery)
- Ensure the IMU module is firmly fixed inside the enclosure to maintain calibration

## License

MIT License - See LICENSE file
