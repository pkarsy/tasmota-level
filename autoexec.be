# Tasmota-Level Auto-execution script
# Loads the MPU6050 level driver on boot

# Load the MPU6050 driver
import level

# Auto-calibrate on boot (place device level before powering on)
# tasmota.set_timer(2000, /-> global.level.calibrate())

