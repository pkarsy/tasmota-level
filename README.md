# Tasmota-Level

A self-leveling/bubble level driver for Tasmota using Berry scripting and the MPU6050 IMU sensor. Hoever the goal is to include more low cost IMU chips. There is no need to install Tasmota's native MPU6050 driver (which requires re-compiling the Tasmota system).

> **⚠️ WORK IN PROGRESS ⚠️**  
This driver is currently being tested in real-world applications. The API may change as issues are discovered. Use with caution until v1.0 is released.

## Overview

Tasmota-Level provides a complete leveling solution that runs entirely within Tasmota's Berry scripting environment:

- **No recompilation required**: Install and configure without rebuilding Tasmota firmware. Thius is important as the support for MPU6050 and other IMUS is not currently compiled in stock tasmota builds.
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

**First time only** - Tools -> BerryConsole :

1. > tasmota.fetcurl TODO

2. **Load the driver interactively**:
   > import level

   If MPU6050 is found, you'll see:
   ```
   LEVEL: MPU6050 found at 0x68
   LEVEL: No saved calibration found. Run: level.calibrate()
   ```

4. **Place your device in the "level" position** (the orientation you want to define as horizontal)
   The IMU must be well mounted inside the box, otherwise the calibration will be wrong.

5. **Calibrate**:
   ```
   level.calibrate()
   ```
   
   This measures the gravity vector and saves it to flash. You'll see:
   ```
   LEVEL: Calibrating... keep steady (20 samples)
   LEVEL: Calibration saved to flash
   LEVEL: Calibrated: [0.8727, -0.4452, 0.2007] (example)
   ```
   Note that if the internal orientation of the IMU changes, then you need to recalibrate the device. 

6. **Test the readings**:
   ```
   br level.tilt()
   ```
   
   Should show 0 up to 1° when level, and increase as you tilt the device.

### Step 2: Auto-load on Boot
This step is optional. You can import the 'level' driver from inside
your application.(The included heater application does this)

Once calibration is working, add to `autoexec.be`:

```berry
import level  # Automatically loads driver and restores calibration
```

On boot, the driver will:
- Scan for MPU6050
- Load saved calibration from flash

## API Reference

### Main Functions

| Function | Returns | Description |
|----------|---------|-------------|
| `level.calibrate(samples)` | `[x,y,z]` or `nil` | Calibrate device. Optional samples (default 20). Saves to flash. |
| `level.tilt()` | degrees or `nil` | Get total tilt from vertical in degrees |
| `level.tilt_rad()` | radians or `nil` | Get total tilt from vertical in radians |
| `level.set_calibration(vector, from_flash)` | `true`/`false` | Load calibration vector manually |

### Example Usage

```berry
# Get current tilt
var tilt = level.tilt()
if tilt != nil
  print("Tilt: " + str(tilt) + " degrees")
end

# Recalibrate if needed
level.calibrate()
```

## How It Works

The implementation uses **vector projection**:

1. **Calibration**: Measures and stores the normalized gravity vector when device is "level"
2. **Runtime**: Projects current acceleration onto the calibrated axes
3. **z_angle**: Calculated directly from gravity projection: `acos(device_Z / |accel|)`

This gives the total tilt from vertical regardless of which direction you tilt.

## Heater Safety Controller

See `heater/` for a complete working example that uses this driver for heater safety:

- Prevents heater from starting if tilted >10°
- Emergency stop if heater tilts while running
- 1-hour auto-timeout

> **"Tested on my daughter's heater"** - This driver is proven in real-world use for heater safety.  
> If it can satisfy a difficult teenager, it can handle your project too! 🔥😤

## Contributing

This is a hobbyist project. Contributions welcome! Please test thoroughly and report issues.

## License

MIT License - See LICENSE file
