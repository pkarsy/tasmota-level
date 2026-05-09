# Tasmota-Level

A self-leveling/bubble level driver for Tasmota using Berry scripting and an IMU/accelerometer (QMI8658, MPU6050/9150/9250, LSM6DS3, ADXL345, BMI160, MMA8452, LIS3DH, LIS3DSH - more can be added easily).

## Overview

This driver is primarily designed to be used by other Berry programs that need tilt sensing capabilities. It provides a simple API for reading tilt angles and monitoring tilt events.

- **Much easier hardware installation than bubble tilt sensors**: Mount the module in any orientation that is most convenient. When the hardware is ready, wirelessly calibrate the module.
- **More precise, and configurable tilt trigger** Depending on application you may want 10deg trigger for example or any other value. Most IMU chips can do better than 1deg accuracy.
- **No recompilation required**: Install and configure without rebuilding Tasmota firmware. This is important as the support for MPU6050 and other IMUs exists but is not currently compiled in stock Tasmota builds.
- **Survives firmware updates**: Berry scripts persist across Tasmota updates

## Hardware Requirements

- ESP32-based module running Tasmota
- QMI8658, MPU6050/9150/9250, LSM6DS3, ADXL345, BMI160, MMA8452, LIS3DH, or LIS3DSH I2C accelerometer/gyroscope sensor. Only the accelerometer is used (so no gyro, DMP or interrupts).

- An enclosure or device where the ESP32 and the sensor are mounted. For example a heater(see below) or a fan.

## Warning for fake parts
MPU6050 is EOL (for a long time) and most breakout boards on online stores have fake or recycled MPU6050 parts. The other parts can have similar problems (to a lesser degree, however), so purchasing through authorized distributors is a good strategy. The only part one can somewhat trust (no guarantees!) on Aliexpress/Ebay is QMI8658 because the original part is modern and of very low cost, so the incentive of making LOWER cost fakes, is minimal (faking costs too!). To be fair, I have purchased a lot of parts from Aliexpress (all the above brands), and seem to work perfectly OK, at least the accelerometer this driver uses.

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
   LEVEL: No supported IMU module found. Supported: QMI8658, MPU6050/9150/9250, LSM6DS3, ADXL345, BMI160, MMA8452, LIS3DH, LIS3DSH
   ```

3. **Place your device in the "level" position** (the orientation you want to define as horizontal)
   The IMU must be well fixed inside the box, otherwise the calibration will not last.

4. **Calibrate**:
   ```sh
   level.calibrate()
   ```
   This measures the gravity vector and saves it to flash. The .calibrate() method is only for interactive use and is performed once.

   You have to recalibrate the device:
   - The internal orientation of the accelerometer change.
   - When you update/replace the "level.be" driver.

5. **Test the readings**:
   ```sh
   level.tilt()
   ```
   Should show 0 up to 1° when level, increasing as you tilt the device.

6. The driver also registers the `tilt` command in the Tasmota console. 

### Step 2: Auto-load on Boot
Having the driver loaded at boot and available as a global module helps to see possible problems early and to recalibrate the device if needed. Add to `autoexec.be`:

```sh
import level
```

**Remember: The module must be calibrated to work properly.**

On boot, the driver will:
- Scan for the accelerometer chip
- Load saved calibration from flash

## Console Command

The driver exposes a single Tasmota console command:

| Command | Description |
|---------|-------------|
| `tilt` | Returns the current tilt angle in degrees |


Example:
```sh
# After calibration and reset, in Tasmota console:
tilt
# Response: 2.3 degrees
```
If one needs full access from the console there is always the 'br' command trick :
```sh
br level.tilt()
br level.calibrate()
```

## API Reference

### Main Functions

| Function | Returns | Description |
|----------|---------|-------------|
| `level.calibrate()` | `nil` | Calibrate device. Saves to flash. Prints the calibration vector. |
| `level.tilt()` | degrees or `nil` | Get tilt from vertical in degrees |
| `level.tilt_rad()` | radians or `nil` | Get tilt from vertical in radians |
| `level.tilt_monitor(callback, interval, max_tilt)` | `nil` | Start monitoring tilt. Calls `callback(tilt)` when tilt > max_tilt°. Interval in ms (default 100). max_tilt in degrees (default 10). |
| `level.stop_tilt_monitor()` | `nil` | Stop the tilt monitor |
| `level.set_calibration([cal_x, cal_y, cal_z])` | `true`/`false` | Apply calibration vector manually - probably you do not need this |

### Example Usage


**⚠️ IMPORTANT:** If no supported IMU is detected, `level` will be `nil`. Even then, there is the possibility that it is not calibrated. Any code using the level driver **MUST** check these two conditions before use:
```berry
import level
if level == nil
  print('No IMU detected - check wiring')
  return nil
end
if level.calibrated == false
  print('IMU not calibrated - run level.calibrate()')
  return nil
end
```
Now it is safe to use level.tilt() and the other methods:

```berry
# Get current tilt
var tilt = level.tilt()
if tilt != nil
  print('Tilt: ' + str(tilt) + ' degrees')
end

# Monitor the tilt and call a function when tilt() > max_tilt
# Note: The monitor is automatically disabled after triggering. Call tilt_monitor() again to re-enable.
level.tilt_monitor(myfunction)
level.tilt_monitor(/->my.method())
level.tilt_monitor(/->my.method(), 100, 15)  # custom interval (100ms) and max_tilt (15°)
```

## Heater tilt aware Controller

> **⚠️ WARNING:** Use of the Heater tilt aware Controller is at your own risk. See [LICENSE](LICENSE) for full disclaimer. The developer assumes no liability for any damages or injuries.

See `heater/` for a complete working example that uses this driver for heater safety (also fans etc):

- Stops the heater/prevents starting if tilted >10°
- 1-hour auto-timeout
- on/off pushbutton


## Troubleshooting

### No IMU detected

If `import level` reports that no supported IMU is found, the first step is to check whether the sensor is visible on the I2C bus at all.

**1. Scan the I2C bus**

Paste the following script into the Berry Console (Tasmota Web UI → Tools → Berry Console):

```berry
import string

print("\nScanning I2C bus...")
for addr: 0x03 .. 0x77
  if tasmota.wire_scan(addr)
    print("Found at " + string.format("0x%02X", addr))
  end
end
print("Scan done.")
```

If a device appears at one of the expected addresses (see table below), the wiring is correct but the driver may not be identifying the chip correctly — open a GitHub issue.

| Chip | Expected address(es) |
|------|---------------------|
| QMI8658 | 0x6A, 0x6B |
| MPU6050/9150/9250 | 0x68, 0x69 |
| LSM6DS3 | 0x6A, 0x6B |
| ADXL345 | 0x53, 0x1D |
| BMI160 | 0x68, 0x69 |
| MMA8452 | 0x1C, 0x1D |
| LIS3DH | 0x18, 0x19 |
| LIS3DSH | 0x1E, 0x1D |

**2. No I2C device found at all**

- Confirm the IMU is powered (VCC to 3.3V, GND to GND).
- Verify that **I2C pins are configured in Tasmota**: Web UI → Configuration → Module → assign **I2C SCL** and **I2C SDA** to the physical GPIOs you wired.
- Check the wiring: SCL → SCL, SDA → SDA. Swapping them or connecting to the wrong GPIOs will produce nothing.
- Try a slower bus speed if the sensor has pull-up resistors that are too weak for the default speed.

**3. No calibration saved**

If the driver loads but shows `No saved calibration found`, this is normal for first use. Run `level.calibrate()` with the device held in the orientation you want to define as level.

**4. Completely wrong tilt values**

If `level.tilt()` returns large or nonsensical angles (e.g. 90° when the device is sitting level), the calibration no longer matches the physical orientation. This can happen if:

- The **internal mounting** of the sensor shifted inside the enclosure (vibration, loose screw, etc.)
- The **sensor module was replaced** with a different one (even the same chip model can have a slightly different orientation on the breakout board)
- The **device's orientation changed** (relocated to a different surface, wall-mounted instead of desk-mounted, etc.)

**Fix:** Run `level.calibrate()` again with the device in the desired level position. No need to re-flash or re-download the driver.

## Tips
- Inside the box, make the USB port accessible (for easier recovery)
- Ensure the IMU module is firmly fixed inside the enclosure to maintain calibration

## License

MIT License - See LICENSE file
