# Tasmota-Level

Under CONSTRUCTION right now

A self-leveling/bubble level driver for Tasmota using Berry scripting and the MPU6050 IMU sensor. Hoever the goal is to include more low cost IMU chips. There is no need to install Tasmota's native MPU6050 driver (which requires re-compiling the Tasmota system).

> **⚠️ WORK IN PROGRESS ⚠️**  
This driver is currently being tested in real-world applications. The API may change as issues are discovered. Use with caution until v1.0 is released.

## Overview

Tasmota-Level provides a complete leveling solution that runs entirely within Tasmota's Berry scripting environment:

- **No recompilation required**: Install and configure without rebuilding Tasmota firmware. This is important as the support for MPU6050 and other IMUs is not currently compiled in stock tasmota builds.
- **Built-in calibration**: Calibrate the module to your specific mounting orientation
- **Auto-save calibration**: Calibration is saved to flash and restored on load
- **Simple API**: Just `level.tilt()` to get the tilt angle in degrees
- **Survives firmware updates**: Berry scripts persist across Tasmota updates

## Hardware Requirements

- ESP32-based module running Tasmota
- MPU6050 I2C accelerometer/gyroscope sensor(QMI8658 MMA8452 LSM6DS3 ADXL345 are coming soon)
- An enclosure or device where the ESP32 and MPU6050 are mounted

## Warning for fake parts
MPU6050 is EOL for a long time and most breakout boards on online stores, have fake or recycled parts. The other parts in can have similar problems(in a lesser degree however) so purchase through authorized distributors is a good startegy.

## Wiring

| IMU breakout | ESP32 (WebInterfcae -> Config -> Module)|
|---------|-------|
| VCC     | 3.3V  or Output Hi |
| GND     | GND or Output Lo  |
| SCL     | I2C SCL |
| SDA     | I2C SDA |

## Installation & Setup

### Step 1: Initial Setup (Interactive)

**First time only** - Tasnmota Web Interface -> Tools -> BerryConsole :

1. > tasmota.urlfetch('https://raw.githubusercontent.com/pkarsy/tasmota-level/refs/heads/main/level.be')

2. **Load the driver interactively** (berry console):
   > import level

   If MPU6050 is found, you'll see:
   ```
   LEVEL: MPU6050 found at 0x68
   LEVEL: No saved calibration found. Run: level.calibrate()
   ```

4. **Place your device in the "level" position** (the orientation you want to define as horizontal)
   The IMU must be well mounted inside the box, otherwise the calibration will be wrong.

5. **Calibrate**:
   
   > level.calibrate()
   
   This measures the gravity vector and saves it to flash.

   Note that if the internal orientation of the IMU changes, you have to recalibrate the device. 

6. **Test the readings**:
   
   > level.tilt()
   
   Should show 0 up to 1° when level, and increase as you tilt the device.

### Step 2: Auto-load on Boot
Having the driver loaded at boot and available as global module helps to see possible probles early and to recalibrate the device if needed. In
`autoexec.be`:

> import level  

**At this point you must have the module calibrated otherwise it wont work, obviously.**

On boot, the driver will:
- Scan for MPU6050
- Load saved calibration from flash

## API Reference

### Main Functions

| Function | Returns | Description |
|----------|---------|-------------|
| `level.calibrate()` | `[x,y,z]` or `nil` | Calibrate device. Saves to flash. |
| `level.tilt()` | degrees or `nil` | Get tilt from vertical in degrees |
| `level.tilt_rad()` | radians or `nil` | Get tilt from vertical in radians |
| `level.set_calibration([cal_x, cal_y, cal_z])` | `true`/`false` | apply calibration vector manually |

### Example Usage

```berry
# Get current tilt
var tilt = level.tilt()
if tilt != nil
  print("Tilt: " + str(tilt) + " degrees")
end

# Monitor the level and call a function
# when tilts exceeds 10deg
level.tilt_monitor( myfunction )
level.tilt_monitor( /->my.method() )
# the heater app depends on this

```

## Heater Safety Controller

See `heater/` for a complete working example that uses this driver for heater safety:

- Stops the heater/preventsstarting if tilted >10°
- 1-hour auto-timeout
- on/off pushbutton

## Contributing

This is a hobbyist project. Contributions welcome! Please test thoroughly and report issues.

## License

MIT License - See LICENSE file
