# Heater Safety Controller Example

A complete working example using the tasmota-level driver for heater safety.

## Features

- **Tilt protection**: Heater won't start if tilt > 10°
- **Emergency stop**: Heater stops immediately if tilt > 10° while running
- **1-hour timeout**: Auto-stop after 1 hour (fire safety)
- **Manual control**: Button toggles heater on/off
- **Visual feedback**: LED blinks when tilt is unsafe

## Hardware Requirements

- ESP32x with Tasmota and Berry support
- MPU6050 I2C sensor (for tilt detection) Soon all IMU chips
- Push button (connected to Button-1)
- LED (built-in or external)
- Relay module (for heater control)

## Wiring

| Component | ESP32 Pin |
|-----------|-----------|
| MPU6050 or other IMU | see the 'level' driver pins |
| Button | configure as Button-1 in Tasmota |
| Relay/SSR | Interrupt-1 in Tasmota |
| Led | Interrupt-2 in Tasmota |

for easier cabling you can simulate VCC and GND with Any GPIO (Tasmota config-module-> Output Hi/Lo)

## Installation

1. **load and calibrate the level driver first**:
  see above 

2. **Calibrate the level sensor**:
   level.calibrate()

3. Download the application to the ESP32 flash

   berry Console
```sh
tasmota.urlfetch('https://raw.githubusercontent.com/pkarsy/tasmota-level/refs/heads/main/heater/heater.be')
```

3. **Upload `heater.be`** and add to `autoexec.be`:
   ```sh
   import level    # Load level driver
   import heater   # Load heater safety controller
```
## How It Works

### Starting the Heater
1. Place heater in upright position (tilt < 10°)
2. Press button → Heater starts
3. LED stays on (normal operation)
4. Tilt or push the heater. The heater stops and the LED blinks.
5. If not tilted, it will stop automatically in 1 hour

### Safety Features

| Condition | Action | LED |
|-----------|--------|-----|
| Tilt > 10° when starting | Won't start | Blinks |
| Tilt > 10° while running | Emergency stop | Blinks |
| Running for 1 hour | Auto-stop | Off |
| Button press while on | Stop | Off |

### LED Indicators

- **Off**: Normal operation or heater off
- **Blinking**: Tilt fault - heater cannot start or was emergency stopped

## Configuration

Edit these values in `heater.be` to customize:

```berry
var TILT_LIMIT = 10.0      # Max tilt in degrees (default: 10)
var TIMEOUT_MS = 3600000   # Timeout in ms (default: 1 hour)
var BLINK_INTERVAL = 200   # Blink speed in ms (default: 200)
```

## Testing

1. **Level test**: Place heater upright, press button - should start
2. **Tilt start test**: Tilt heater > 10°, press button - should blink, not start
3. **Tilt run test**: Start heater, then tilt > 10° - should stop and blink
4. **Timeout test**: Start heater, wait 1 hour - should auto-stop
5. **Button stop**: Start heater, press button - should stop

## Troubleshooting

| Problem | Solution |
|---------|----------|
| "level driver not loaded" | Load level.be first |
| Heater won't start | Check calibration with `level.tilt()` |
| LED not blinking | Check LED configuration in Tasmota |
| Button not working | Verify Switch1 configuration |

## ⚠️ SAFETY WARNING ⚠️

**THIS IS A HOBBYIST PROJECT. USE AT YOUR OWN RISK.**

- **Mains voltage is dangerous** - If you don't know what you're doing, stop now
- **This code comes with NO WARRANTY** - If you burn your house down, it's your fault
- **Always have backup safety mechanisms** - Mechanical thermostats, thermal fuses, etc.
- **Test thoroughly** before relying on this system
- **Never leave heaters unattended** - Software can fail, sensors can break
- **The 1-hour timeout is NOT a substitute** for proper thermal protection/monitoring

**By using this code, you accept full responsibility for any damage, injury, or fire that may occur.**

We are not responsible if:
- Your house burns down 🔥
- Your cat gets toasted 🐱
- Your insurance company laughs at you 📞
- You have to explain to your spouse why the living room is blackened 💔

**YOU HAVE BEEN WARNED.**
